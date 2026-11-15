/* Exercise the real loader seam with fake host services; no phone execution. */
#define _GNU_SOURCE
#include <assert.h>
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>
static int mode, opens, setups, writes, reenter, fail_log;
static void install(void);
static int setup(void) { ++setups; return mode != 3; }
static const char *fake_name(void) { return "host\nprobe"; }
static void *fake_dlopen(const char *path, int flags)
{
    ++opens;
    if (strstr(path, "SweetEAGL")) {
        assert(flags == (RTLD_NOW|RTLD_GLOBAL|RTLD_NODELETE));
        if (reenter) install();
        return mode == 1 ? NULL : (void *)(uintptr_t)2;
    }
    assert(flags == (RTLD_NOLOAD|RTLD_NODELETE));
    return mode == 4 ? NULL : (void *)(uintptr_t)1;
}
static void *fake_dlsym(void *handle, const char *symbol)
{
    assert(handle == (void *)(uintptr_t)2 && !strcmp(symbol, "sweeteagl_install"));
    return mode == 2 ? NULL : (void *)setup;
}
static int fake_open(const char *path, int flags, ...)
{
    assert(!strcmp(path, "/private/var/root/gpu/sweetgles.log"));
    assert(flags == (O_WRONLY|O_CREAT|O_APPEND));
    return fail_log ? -1 : 42;
}
static ssize_t fake_write(int fd, const void *data, size_t count)
{
    assert(fd == 42 && count && count < 512);
    const char *s = data;
    assert(s[count - 1] == '\n');
    for (size_t i = 0; i + 1 < count; ++i) assert(s[i] != '\n' && s[i] != '\r');
    ++writes;
    return (ssize_t)count;
}
static int fake_close(int fd) { assert(fd == 42); return 0; }
#define dlopen fake_dlopen
#define dlsym fake_dlsym
#define getprogname fake_name
#define open fake_open
#define write fake_write
#define close fake_close
#include "sweetgles.c"
#undef dlopen
#undef dlsym
#undef open
#undef write
#undef close

static void reset(int next_mode)
{
    mode = next_mode; opens = setups = writes = reenter = fail_log = 0;
    __atomic_store_n(&state, 0, __ATOMIC_RELAXED);
    __atomic_store_n(&lines, 0, __ATOMIC_RELAXED);
}
int main(void)
{
    assert(state == 2 && setups == 1); /* Real constructor executed. */
    for (int m = 0; m < 5; ++m) {
        reset(m);
        reenter = 1;
        errno = EDOM;
        gldInitializeLibrary(NULL, NULL, UINT32_MAX, NULL, NULL, 0);
        gldInitializeLibrary(NULL, NULL, 0, NULL, NULL, 0);
        assert(opens == 2 && setups == (m == 1 || m == 2 ? 0 : 1));
        assert(state == (m == 1 || m == 2 || m == 3 ? -1 : 2));
        assert(errno == EDOM);
        uint32_t a = 1, b = 2, c = 3, d = 4;
        assert(gldGetVersion(&a, &b, &c, &d) == 0 && !(a|b|c|d));
        assert(gldGetVersion(NULL, NULL, NULL, NULL) == 0);
    }
    reset(0);
    for (int i = 0; i < 100; ++i) gldGetVersion(NULL, NULL, NULL, 0);
    assert(writes == 50 && lines == 50);
    reset(0); fail_log = 1;
    gldInitializeLibrary(NULL, NULL, 0, NULL, NULL, 0);
    assert(state == 2 && writes == 0);
    puts("PASS host loader: constructor, idempotence, recursive entry, load/symbol/install/pin/log failures, zeroed version, 50-line cap");
    return 0;
}
