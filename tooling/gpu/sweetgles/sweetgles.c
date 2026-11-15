/* Own GLD seam, observed in gfxs.dis 0x1d3f6e8c4–0x1d3f6e95c.
 * No Apple implementation, headers, or SDK are used. */
#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define BUNDLE "/System/Library/Extensions/SweetGLES.bundle/"
static unsigned lines;
static int state; /* 0 unattempted, 1 installing, 2 success, -1 failed */
static void *self_pin, *eagl_pin; /* Intentionally never dlclose either handle. */

static void event(const char *message)
{
    int saved_errno = errno;
    unsigned n = __atomic_load_n(&lines, __ATOMIC_RELAXED);
    while (n < 50 && !__atomic_compare_exchange_n(&lines, &n, n + 1, 1, __ATOMIC_RELAXED, __ATOMIC_RELAXED)) {}
    if (n < 50) {
        char buf[512];
        const char *name = getprogname();
        int len = snprintf(buf, sizeof(buf), "SweetGLES pid=%ld process=%.80s %s\n",
                           (long)getpid(), name ? name : "?", message);
        if (len > 0) {
            size_t count = (size_t)len < sizeof(buf) ? (size_t)len : sizeof(buf) - 1;
            /* Exactly one line per reserved event, even for an unusual process name. */
            for (size_t i = 0; i + 1 < count; ++i)
                if (buf[i] == '\n' || buf[i] == '\r') buf[i] = ' ';
            buf[count - 1] = '\n';
            int fd = open("/private/var/tmp/sweetgles.log", O_WRONLY|O_CREAT|O_APPEND, 0666);
            if (fd >= 0) { (void)write(fd, buf, count); (void)close(fd); }
        }
    }
    errno = saved_errno;
}

static void install(void)
{
    int expected = 0;
    if (!__atomic_compare_exchange_n(&state, &expected, 1, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
        event(expected == 2 ? "install already succeeded" :
              expected == 1 ? "install in progress (no recursive wait)" : "install already failed");
        return;
    }
    /* gfxs.dis 0x1d3f6ed48 dlcloses us after the deliberate version failure.
     * RTLD_NODELETE keeps our state and SweetEAGL's installed ObjC IMPs alive.
     * Never wait on a once/mutex here: dlopen constructors can reenter this seam. */
    self_pin = dlopen(BUNDLE "SweetGLES", RTLD_NOLOAD|RTLD_NODELETE);
    event(self_pin ? "self pin success" : "self pin FAILED (continuing with retained EAGL handle)");
    eagl_pin = dlopen(BUNDLE "SweetEAGL.dylib", RTLD_NOW|RTLD_GLOBAL|RTLD_NODELETE);
    if (!eagl_pin) { event("install FAIL SweetEAGL dlopen"); __atomic_store_n(&state, -1, __ATOMIC_RELEASE); return; }
    int (*setup)(void) = (int (*)(void))dlsym(eagl_pin, "sweeteagl_install");
    if (!setup) { event("install FAIL sweeteagl_install symbol"); __atomic_store_n(&state, -1, __ATOMIC_RELEASE); return; }
    int result = setup();
    char msg[96];
    (void)snprintf(msg, sizeof(msg), "install %s sweeteagl_install=%d", result ? "success" : "FAIL", result);
    event(msg);
    __atomic_store_n(&state, result ? 2 : -1, __ATOMIC_RELEASE);
}

__attribute__((constructor)) static void constructor(void)
{
    event("constructor");
    install();
}

/* gfxs.dis 0x1d3f6e8e8–0x1d3f6e904 sets x0,x1,w2,x3,x4,x5.
 * x3/x4 are callback addresses, w2 is a device bitmask (0x1d3f6e678).
 * x5 carries x19 flags (0x1d3f6e310, 0x1d3f6e3e0–0x1d3f6e3ec, 0x1d3f6e900).
 * Remaining pointer types are opaque: none of these arguments is dereferenced.
 * The return register is unused at 0x1d3f6e908. */
__attribute__((visibility("default")))
int gldInitializeLibrary(void *global0, void *global1, uint32_t devices,
                         void (*callback0)(void), void (*callback1)(void), uintptr_t flags)
{
    (void)global0; (void)global1; (void)devices;
    (void)callback0; (void)callback1; (void)flags;
    event("gldInitializeLibrary");
    install();
    return 0;
}

/* gfxs.dis 0x1d3f6e934–0x1d3f6e948: four uint32_t outputs, zero return
 * takes the disconnect branch. Do not advertise a driver ABI we cannot supply. */
__attribute__((visibility("default")))
int gldGetVersion(uint32_t *a, uint32_t *b, uint32_t *c, uint32_t *d)
{
    event("gldGetVersion deliberate rejection");
    if (a) *a = 0;
    if (b) *b = 0;
    if (c) *c = 0;
    if (d) *d = 0;
    return 0;
}
