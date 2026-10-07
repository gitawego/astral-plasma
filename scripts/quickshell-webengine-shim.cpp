// quickshell-webengine-shim.cpp
//
// Makes a *stock*, unpatched Quickshell host QtWebEngine, without rebuilding it
// and without root. Applied with LD_PRELOAD, it performs the same two steps a
// source patch would:
//
//   1. call QtWebEngineQuick::initialize() before Quickshell creates
//      QGuiApplication (QtWebEngine refuses to run otherwise);
//   2. force a program name into QGuiApplication (Quickshell passes argc = 0,
//      and Chromium aborts with "Argument list is empty" without one).
//
// It is inert everywhere except the main Quickshell process: helpers such as
// QtWebEngineProcess, servers and browsers the shell spawns are left untouched,
// and `quickshell ipc ...` does not pay for a Chromium boot.
#include <dlfcn.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>

extern "C" void _ZN15QGuiApplicationC1ERiPPci(void *, int &, char **, int);
extern "C" void _ZN15QGuiApplicationC2ERiPPci(void *, int &, char **, int);
extern "C" void _ZN12QApplicationC1ERiPPci(void *, int &, char **, int);
extern "C" void _ZN12QApplicationC2ERiPPci(void *, int &, char **, int);

namespace {
using CtorFn = void (*)(void *, int &, char **, int);

bool readFile(const char *path, char *buf, size_t cap) {
    FILE *f = std::fopen(path, "rb");
    if (!f) return false;
    size_t n = std::fread(buf, 1, cap - 1, f);
    std::fclose(f);
    buf[n] = 0;
    return true;
}

bool commStartsWith(const char *prefix) {
    char buf[256] = {0};
    if (!readFile("/proc/self/comm", buf, sizeof(buf))) return false;
    return std::strncmp(buf, prefix, std::strlen(prefix)) == 0;
}

bool invokedAsIpcClient() {
    char buf[4096] = {0};
    if (!readFile("/proc/self/cmdline", buf, sizeof(buf))) return false;
    for (size_t i = 0, start = 0; i < sizeof(buf); i++) {
        if (buf[i] == 0) {
            if (std::strcmp(buf + start, "ipc") == 0) return true;
            if (buf[i + 1] == 0) break;
            start = i + 1;
        }
    }
    return false;
}

void ensureProgramName(int &argc, char **argv) {
    if (argc < 1) argc = 1;
    if (argv && argv[0] == nullptr) argv[0] = const_cast<char *>("quickshell");
}

__attribute__((constructor)) void astralWebEngineEarlyInit() {
    // Only the main shell boots Chromium. Launcher wrappers (env, timeout,
    // setsid) also preload this library and must NOT strip LD_PRELOAD, or the
    // real shell would inherit nothing; helpers and IPC clients simply return.
    if (!commStartsWith("quickshell")) return;
    if (invokedAsIpcClient()) return;
    void *handle = dlopen("libQt6WebEngineQuick.so.6", RTLD_NOW | RTLD_GLOBAL);
    if (!handle) {
        std::fprintf(stderr, "astral-webengine-shim: dlopen failed: %s\n", dlerror());
        return;
    }
    auto initialize = reinterpret_cast<void (*)()>(
        dlsym(handle, "_ZN16QtWebEngineQuick10initializeEv"));
    if (!initialize) {
        std::fprintf(stderr, "astral-webengine-shim: initialize() not found\n");
        return;
    }
    initialize();
}
}

#define ASTRAL_INTERPOSE(sym)                                                     \
extern "C" void sym(void *self, int &argc, char **argv, int version) {            \
    static CtorFn real = nullptr;                                                 \
    if (!real) real = reinterpret_cast<CtorFn>(dlsym(RTLD_NEXT, #sym));           \
    ensureProgramName(argc, argv);                                                \
    if (real) { real(self, argc, argv, version); }                                \
    else { std::fprintf(stderr, "astral-webengine-shim: unresolved %s\n", #sym); } \
}

ASTRAL_INTERPOSE(_ZN15QGuiApplicationC1ERiPPci)
ASTRAL_INTERPOSE(_ZN15QGuiApplicationC2ERiPPci)
ASTRAL_INTERPOSE(_ZN12QApplicationC1ERiPPci)
ASTRAL_INTERPOSE(_ZN12QApplicationC2ERiPPci)
