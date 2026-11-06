#!/usr/bin/env bash
# Grant the GPU engine perf counters to Astral Plasma's metrics reader.
#
# Why a capability and not a clock ratio: `/proc/<pid>/fdinfo` only exposes DRM
# clients the reader may open, and KWin - installed with `cap_sys_nice=ep` file
# capabilities - is non-dumpable, so the compositor is invisible to it. On a
# 240Hz panel that halves the reported number. The i915 perf PMU counts engine
# busy nanoseconds for the whole GT (every client) and needs `CAP_PERFMON`.
#
# Two ways to hand that capability over, tried in order:
#
#   1. File capabilities on this checkout's binary - only honoured when the
#      filesystem does not carry the `nosuid` mount flag.
#   2. A copy installed under /usr/local/libexec (never nosuid) carrying
#      `cap_perfmon=ep`. The unprivileged daemon then reads the counters by
#      running `astral-plasma gpu-pmu-counters` from there.
#
# Nothing here is required for the shell to run: without the capability the GPU
# reading falls back to fdinfo, exactly as before, and `doctor` says so.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="$REPO_ROOT/bin/astral-plasma"
HELPER="/usr/local/libexec/astral-plasma/astral-plasma"

if [[ $EUID -ne 0 ]]; then
    echo "Re-running with sudo (both routes need CAP_SETFCAP)..." >&2
    exec sudo --preserve-env=PATH bash "${BASH_SOURCE[0]}" "$@"
fi

if [[ ! -x "$BINARY" ]]; then
    echo "error: $BINARY not found - run 'make build' first" >&2
    exit 1
fi

# Does this filesystem honour file capabilities? A `nosuid` mount silently drops
# them, which would look like "setcap worked but nothing changed".
mount_point="$(findmnt -no TARGET -T "$BINARY" 2>/dev/null || echo "")"
mount_opts="$(findmnt -no OPTIONS -T "$BINARY" 2>/dev/null || echo "")"
honours_caps=1
if [[ "$mount_opts" == *nosuid* ]]; then
    honours_caps=0
fi

if [[ $honours_caps -eq 1 ]]; then
    setcap cap_perfmon=ep "$BINARY"
    echo "Granted cap_perfmon to $BINARY"
    verify_target="$BINARY"
else
    echo "note: $mount_point is mounted nosuid, so file capabilities are ignored there."
    echo "      Installing a privileged copy outside the checkout instead."
    install -Dm755 "$BINARY" "$HELPER"
    setcap cap_perfmon=ep "$HELPER"
    echo "Granted cap_perfmon to $HELPER"
    verify_target="$HELPER"
fi

echo
echo "Verifying as user '${SUDO_USER:-$USER}':"
verify_user="${SUDO_USER:-$USER}"
if counters="$(runuser -u "$verify_user" -- "$verify_target" gpu-pmu-counters 2>/dev/null)"; then
    head -3 <<< "$counters"
    echo
    echo "OK - the dashboard's GPU percentage now counts every client, like intel_gpu_top."
else
    echo
    echo "error: the counters could not be read even with the capability." >&2
    echo "       perf_event_paranoid=$(cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null)" >&2
    exit 1
fi

echo
echo "Re-run this after 'make build' if you used the helper copy at $HELPER,"
echo "so it picks up new binaries."
