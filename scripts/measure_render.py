#!/usr/bin/env python3
"""Measure a process's real GPU and CPU cost on the display GPU.

Why not `nvidia-smi`/`intel_gpu_top`: the display GPU here is the Intel iGPU, and
its per-process cost lives in the DRM engine counters of `/proc/<pid>/fdinfo/*`
(`drm-engine-render` and friends, in nanoseconds of GPU time).

Two traps this tool exists to avoid:

1. **Duplicated fds.** A process that opened the DRM node twice - or `dup()`ed an
   fd - lists the *same* counters several times, and summing them double-counts
   the work. Rows that agree on every engine counter belong to one DRM file, so
   they are counted once.
2. **Fd churn.** Fds appear and disappear while a process runs (dma-buf imports,
   temporary render targets). A naive "sum now minus sum then" counts new fds as
   work and turns negative when one disappears, so only fds present in both
   samples are paired.
3. **Wrong device.** A machine with several GPUs exposes several `drm-pdev`
   values; the display GPU is selected explicitly, not by the first row found.

Usage:
    scripts/measure_render.py <pid> [seconds] [--pdev 0000:00:02.0]

Output is GPU "% of one second of GPU time per second" (so >100 % means the
engine is oversubscribed) plus the process's CPU time per second.
"""

import argparse
import glob
import os
import time


def engine_rows(pid, pdev):
    """Engine counters per DRM file, keyed by device so samples can be paired.

    Returns {fd_number: (device_path, {engine: ns})}. Identical counter vectors
    are one DRM file reached through several fds and are collapsed here.
    """
    rows = {}
    seen = set()
    for path in glob.glob(f"/proc/{pid}/fdinfo/*"):
        try:
            with open(path, errors="ignore") as handle:
                text = handle.read()
        except OSError:
            continue
        if pdev not in text:
            continue
        counters = {}
        for line in text.splitlines():
            if not line.startswith("drm-engine-"):
                continue
            name, _, raw = line.partition(":")
            value = raw.strip().split()[0] if raw.strip() else "0"
            if not value.isdigit():
                continue
            counters[name] = int(value)
        if not counters:
            continue
        try:
            fd_number = int(os.path.basename(path))
            device = os.readlink(f"/proc/{pid}/fd/{fd_number}")
        except OSError:
            continue
        fingerprint = (device, tuple(sorted(counters.items())))
        if fingerprint in seen:
            continue
        seen.add(fingerprint)
        rows[fd_number] = (device, counters)
    return rows


def engine_delta(before, after):
    """GPU nanoseconds spent between two samples, matched fd by fd.

    A process opens and closes DRM fds while it runs (dma-buf imports, temporary
    render targets). Summing "all rows now" minus "all rows then" counts the fds
    that appeared and, worse, goes negative when one disappeared - which is how a
    real measurement turns into -4703 %. Only fds present in both samples count.
    """
    total = 0
    matched = 0
    for fd_number, (device, counters) in before.items():
        after_entry = after.get(fd_number)
        if after_entry is None or after_entry[0] != device:
            continue
        matched += 1
        for engine, value in counters.items():
            total += max(0, after_entry[1].get(engine, value) - value)
    return total, matched


def all_processes(pid_filter=None):
    """Every process that has the display GPU open."""
    pids = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid_filter is not None and pid != pid_filter:
            continue
        pids.append(pid)
    return pids


def cpu_seconds(pid):
    try:
        with open(f"/proc/{pid}/stat") as handle:
            fields = handle.read().split()
    except OSError:
        return 0.0
    ticks = int(fields[13]) + int(fields[14])
    return ticks / os.sysconf("SC_CLK_TCK")


def global_busy_percent(card="card2"):
    """Display GPU busy share from the i915 RC6 residency counter.

    The engine counters above answer "what did this process do", but a shell that
    keeps its surface updating also costs the *compositor* a blur+blend of that
    surface. The RC6 residency is the ground truth for total engine activity, so
    it is what a user sees as "GPU usage" in the shell's own performance tab.
    """
    path = f"/sys/class/drm/{card}/gt/gt0/rc6_residency_ms"
    try:
        with open(path) as handle:
            return float(handle.read().strip())
    except OSError:
        return None


def current_freq_mhz(card="card2"):
    """Current GT frequency, the number the shell's Intel GPU usage is derived from."""
    for candidate in (f"/sys/class/drm/{card}/gt_act_freq_mhz", f"/sys/class/drm/{card}/gt/gt0/rps_act_freq_mhz"):
        try:
            with open(candidate) as handle:
                return int(handle.read().strip())
        except OSError:
            continue
    return None


def freq_limits(card="card2"):
    limits = []
    for suffix in ("gt_min_freq_mhz", "gt_max_freq_mhz"):
        for candidate in (f"/sys/class/drm/{card}/{suffix}", f"/sys/class/drm/{card}/gt/gt0/rps_{suffix[3:]}"):
            try:
                with open(candidate) as handle:
                    limits.append(int(handle.read().strip()))
                break
            except OSError:
                continue
    return limits if len(limits) == 2 else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pid", type=int, nargs="?", default=None, help="process to measure (omit with --total)")
    parser.add_argument("seconds", nargs="?", type=float, default=6.0)
    parser.add_argument("--pdev", default="0000:00:02.0", help="display GPU PCI address")
    parser.add_argument("--card", default="card2", help="DRM card node of the display GPU")
    parser.add_argument(
        "--total",
        action="store_true",
        help="GPU work summed over every process (oversubscription aware, i.e. can exceed 100 %%)",
    )
    parser.add_argument(
        "--freq",
        action="store_true",
        help="sample the GT frequency the shell's Intel GPU usage is derived from",
    )
    args = parser.parse_args()

    if args.freq:
        limits = freq_limits(args.card)
        samples = []
        deadline = time.time() + args.seconds
        while time.time() < deadline:
            value = current_freq_mhz(args.card)
            if value is not None:
                samples.append(value)
            time.sleep(0.1)
        if not samples:
            print("  no GT frequency readable")
            return
        lo, hi = (limits if limits else (min(samples), max(samples)))
        span = max(1, hi - lo)
        print(f"GT frequency over {args.seconds:g}s  (min {lo} max {hi} MHz):")
        print(f"  samples  : min {min(samples)}  max {max(samples)}  mean {sum(samples) / len(samples):.0f} MHz")
        print(f"  as usage : min {100 * (min(samples) - lo) / span:.0f} %  max {100 * (max(samples) - lo) / span:.0f} %"
              f"  mean {100 * (sum(samples) / len(samples) - lo) / span:.0f} %")
        print(f"  fraction of samples above min: {100 * sum(1 for s in samples if s > lo + 5) / len(samples):.0f} %")
        return

    if args.total:
        before = {}
        for pid in all_processes():
            rows = engine_rows(pid, args.pdev)
            if rows:
                before[pid] = rows
        rc6_before = global_busy_percent(args.card)
        time.sleep(args.seconds)
        rc6_after = global_busy_percent(args.card)
        total = 0.0
        per_process = []
        for pid, rows in before.items():
            after_rows = engine_rows(pid, args.pdev)
            if not after_rows:
                continue
            ns, _ = engine_delta(rows, after_rows)
            if ns <= 0:
                continue
            per_process.append((ns / 1e9 / args.seconds * 100, pid))
        for share, pid in sorted(per_process, reverse=True)[:6]:
            name = "?"
            try:
                with open(f"/proc/{pid}/comm") as handle:
                    name = handle.read().strip()
            except OSError:
                pass
            print(f"  {share:7.1f} %  pid {pid:>7} {name}")
            total += share
        print(f"  {'-' * 7}")
        print(f"  total GPU work : {total:7.1f} % of one second per second ({len(per_process)} processes)")
        if rc6_before is not None and rc6_after is not None:
            busy = 100.0 * (1.0 - (rc6_after - rc6_before) / (args.seconds * 1000.0))
            print(f"  iGPU busy (RC6): {busy:7.1f} %")
        return

    pid = args.pid if args.pid is not None else os.getpid()
    before_gpu = engine_rows(pid, args.pdev)
    before_cpu = cpu_seconds(pid)
    before_rc6 = global_busy_percent(args.card)
    time.sleep(args.seconds)
    after_gpu = engine_rows(args.pid, args.pdev)
    after_cpu = cpu_seconds(pid)
    after_rc6 = global_busy_percent(args.card)

    render_before = sum(row.get("drm-engine-render", 0) for _, row in before_gpu.values())
    render_after = sum(row.get("drm-engine-render", 0) for _, row in after_gpu.values())
    _ = (render_before, render_after)
    gpu_ns, matched = engine_delta(before_gpu, after_gpu)
    gpu = gpu_ns / 1e9 / args.seconds * 100
    cpu = (after_cpu - before_cpu) / args.seconds * 100

    name = "?"
    try:
        with open(f"/proc/{pid}/comm") as handle:
            name = handle.read().strip()
    except OSError:
        pass

    print(f"{name} (pid {pid}) over {args.seconds:g}s on {args.pdev}:")
    print(f"  GPU render engine : {gpu:6.1f} %   ({matched} DRM file(s) sampled)")
    print(f"  CPU               : {cpu:6.1f} %")
    if before_rc6 is not None and after_rc6 is not None:
        busy = 100.0 * (1.0 - (after_rc6 - before_rc6) / (args.seconds * 1000.0))
        print(f"  iGPU busy (RC6)   : {busy:6.1f} %   <- what a user reads as GPU usage")


if __name__ == "__main__":
    main()
