/* Apple-path-only stage-1 probe. Minimal red-surface code copied from the
 * project's sweeteagl/eagltest.c. All binary claims: README.md addresses. */
#include "test_abi.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>

static int failures;
static int report(const char *step, int good)
{
    printf("%s %s\n", good ? "PASS" : "FAIL", step);
    if (!good) ++failures;
    return good;
}
static void number(CFMutableDictionaryRef d, CFStringRef key, int64_t value)
{
    /* CFNumber SInt64 type; E §9's IOSurface dictionary, own CF declarations. */
    CFNumberRef n = CFNumberCreate(NULL, 4, &value);
    if (n) { CFDictionarySetValue(d, key, n); CFRelease(n); }
}
static CFMutableDictionaryRef dictionary(void)
{
    return CFDictionaryCreateMutable(NULL, 0, kCFTypeDictionaryKeyCallBacks, kCFTypeDictionaryValueCallBacks);
}
struct objc_api {
    Class (*getClass)(const char *);
    SEL (*selector)(const char *);
    void (*send)(void);
};
static int objc_load(struct objc_api *o)
{
    void *h = dlopen("/usr/lib/libobjc.A.dylib", RTLD_NOW|RTLD_LOCAL);
    if (!h) return 0;
    o->getClass = (Class (*)(const char *))dlsym(h, "objc_getClass");
    o->selector = (SEL (*)(const char *))dlsym(h, "sel_registerName");
    o->send = (void (*)(void))dlsym(h, "objc_msgSend");
    return o->getClass && o->selector && o->send;
}
#define SHIM "/System/Library/Extensions/SweetGLES.bundle/SweetEAGL.dylib"
#define SEL_(s) o.selector(s)
#define SEND(ret, types, object, selector, ...) \
    ((ret (*) types)o.send)(object, SEL_(selector), ##__VA_ARGS__)
/* Slot evidence: README.md table; OpenGLES stubs and QuartzCore call sites. */
#define GL_CALL(ret, types, off, ...) ((ret (*) types)table[(off)/8])(table[0], ##__VA_ARGS__)

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc > 2 || (argc == 2 && strcmp(argv[1], "--via-bundle"))) {
        fprintf(stderr, "usage: bundletest [--via-bundle]\n"); return 1;
    }
    if (!report("0 clean environment", !getenv("DYLD_INSERT_LIBRARIES") &&
                !getenv("SWEETEAGL_MESA") && !getenv("SWEETEAGL_CPU"))) return 1;
    void *gles = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_NOW|RTLD_LOCAL);
    struct objc_api o;
    if (!report("1 load Apple OpenGLES and ObjC", gles && objc_load(&o))) return 1;
    void *probe = dlopen(SHIM, RTLD_NOLOAD|RTLD_NOW|RTLD_LOCAL);
    if (probe) dlclose(probe);
    if (!report("1 SweetEAGL absent before context request", !probe)) return 1;
    CFMutableDictionaryRef props = dictionary();
    const void **accelerated = dlsym(gles, "kEAGLContextPropertyAccelerated");
    const void **retain_release = dlsym(gles, "kEAGLContextPropertyClientRetainRelease");
    if (!report("2 properties dictionary", props && accelerated && retain_release)) return 1;
    CFDictionarySetValue(props, *accelerated, kCFBooleanTrue);
    CFDictionarySetValue(props, *retain_release, kCFBooleanTrue);
    Class cls = o.getClass("EAGLContext");
    if (!report("2 EAGLContext class", cls != NULL)) { CFRelease(props); return 1; }
    id contexts[3] = {NULL, NULL, NULL};
    const unsigned long requests[] = {3, 2, 3};
    for (unsigned i = 0; i < 3; ++i) {
        id allocated = SEND(id, (id, SEL), cls, "alloc");
        contexts[i] = SEND(id, (id, SEL, unsigned long, id), allocated,
                           "initWithAPI:properties:", requests[i], props);
        if (contexts[i]) printf("request[%u] API %lu => non-nil, reported API=%lu\n", i,
                               requests[i], SEND(unsigned long, (id, SEL), contexts[i], "API"));
        else printf("request[%u] API %lu => nil, reported API=n/a\n", i, requests[i]);
    }
    CFRelease(props);
    report("3 initial API 3 returns nil (UNVERIFIED prediction)", contexts[0] == NULL);
    report("3 API 2 retry reports API 3", contexts[1] &&
           SEND(unsigned long, (id, SEL), contexts[1], "API") == 3);
    report("3 API 3 retry reports API 3", contexts[2] &&
           SEND(unsigned long, (id, SEL), contexts[2], "API") == 3);
    probe = dlopen(SHIM, RTLD_NOLOAD|RTLD_NOW|RTLD_LOCAL);
    report("4 SweetEAGL loaded by Apple path", probe != NULL);
    if (probe) dlclose(probe);
    /* Probe reference is gone before exercising the replacement IMPs. */
    if (failures) return 1;
    id ctx = contexts[1]; /* Exercise the exact fallback QuartzCore would use. */
    if (!report("4 setCurrentContext", SEND(BOOL, (id, SEL, id), cls, "setCurrentContext:", ctx))) return 1;
    void **table = SEND(void **, (id, SEL), ctx, "getMacroContextPrivate");
    const unsigned offsets[] = {0x318, 0x30, 0x988, 0x1518, 0x1508, 0x1530,
                               0x1520, 0xa80, 0x68, 0x58, 0x2d0, 0x338, 0x1510, 0x1e0};
    int complete = table && table[0];
    if (complete) for (size_t i = 0; i < sizeof(offsets)/sizeof(offsets[0]); ++i)
        if (!table[offsets[i]/8]) { printf("missing slot %#x\n", offsets[i]); complete = 0; }
    if (!report("5 required table slots non-NULL", complete)) return 1;
    CFMutableDictionaryRef desc = dictionary();
    if (!desc) { report("6 IOSurface dictionary", 0); return 1; }
    number(desc, kIOSurfaceWidth, 64); number(desc, kIOSurfaceHeight, 64);
    number(desc, kIOSurfaceBytesPerElement, 4); number(desc, kIOSurfaceBytesPerRow, 256);
    number(desc, kIOSurfacePixelFormat, SWEET_BGRA);
    IOSurfaceRef surface = IOSurfaceCreate(desc);
    CFRelease(desc);
    GLuint texture = 0, fbo = 0;
    GL_CALL(void, (void *, GLsizei, GLuint *), 0x0318, 1, &texture);
    GL_CALL(void, (void *, GLenum, GLuint), 0x0030, GL_TEXTURE_2D, texture);
    GL_CALL(void, (void *, GLenum, GLenum, GLint), 0x0988, GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    GL_CALL(void, (void *, GLenum, GLenum, GLint), 0x0988, GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    BOOL attached = surface && SEND(BOOL, (id, SEL, unsigned long, IOSurfaceRef, BOOL), ctx,
                                   "attachImage:toCoreSurface:invertedRender:", GL_TEXTURE_2D, surface, false);
    GL_CALL(void, (void *, GLsizei, GLuint *), 0x1518, 1, &fbo);
    GL_CALL(void, (void *, GLenum, GLuint), 0x1508, GL_FRAMEBUFFER, fbo);
    GL_CALL(void, (void *, GLenum, GLenum, GLenum, GLuint, GLint), 0x1530,
            GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
    if (!report("6 BGRA IOSurface, texture and FBO via table", attached && texture && fbo)) goto teardown;
    if (!report("7 framebuffer complete via table", GL_CALL(GLenum, (void *, GLenum),
                0x1520, GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE)) goto teardown;
    GL_CALL(void, (void *, GLint, GLint, GLsizei, GLsizei), 0x0a80, 0, 0, 64, 64);
    GL_CALL(void, (void *, GLfloat, GLfloat, GLfloat, GLfloat), 0x0068, 1.f, 0.f, 0.f, 1.f);
    GL_CALL(void, (void *, GLbitfield), 0x0058, GL_COLOR_BUFFER_BIT);
    GL_CALL(void, (void *), 0x02d0);
    GLenum error = GL_CALL(GLenum, (void *), 0x0338);
    bool red = false;
    if (!IOSurfaceLock(surface, SWEET_SURFACE_READONLY, NULL)) {
        const unsigned char *base = IOSurfaceGetBaseAddress(surface);
        if (base) {
            const unsigned char *p = base + 32*IOSurfaceGetBytesPerRow(surface) + 32*4;
            red = p[0] == 0 && p[1] == 0 && p[2] == 255 && p[3] == 255;
            printf("pixel(32,32)=%02x %02x %02x %02x GL error=%#x\n", p[0], p[1], p[2], p[3], error);
        }
        IOSurfaceUnlock(surface, SWEET_SURFACE_READONLY, NULL);
    }
    report("8 red pixel", red && error == GL_NO_ERROR);
teardown:
    GL_CALL(void, (void *, GLsizei, const GLuint *), 0x1510, 1, &fbo);
    GL_CALL(void, (void *, GLsizei, const GLuint *), 0x01e0, 1, &texture);
    int clean = GL_CALL(GLenum, (void *), 0x0338) == GL_NO_ERROR;
    clean &= SEND(BOOL, (id, SEL, id), cls, "setCurrentContext:", NULL);
    for (unsigned i = 0; i < 3; ++i)
        if (contexts[i]) SEND(void, (id, SEL), contexts[i], "release");
    if (surface) CFRelease(surface);
    report("9 teardown", clean);
    return failures ? 1 : 0;
}
