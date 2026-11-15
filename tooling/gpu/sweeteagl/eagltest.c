/* Standalone phone test, E §9. All GL operations except the explicit FBO
 * completeness probe go through E §2's context-first table ABI. */
#include "abi.h"
#include "slots.h"
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
#define SEL_(s) o.selector(s) /* Every selector below is from E §§3/9. */
#define SEND(ret, types, object, selector, ...) \
    ((ret (*) types)o.send)(object, SEL_(selector), ##__VA_ARGS__)
/* All literal slot offsets below are E §§4/9 or eagl-offmap.txt. */
#define GL_CALL(ret, types, off, ...) ((ret (*) types)table[(off)/8])(table[0], ##__VA_ARGS__)

int main(int argc, char **argv)
{
    const char *shim = "/private/var/root/gpu/SweetEAGL.dylib";
    bool cpu = false;
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--cpu")) cpu = true;
        else shim = argv[i];
    }
    if (cpu) setenv("SWEETEAGL_CPU", "1", 1);
    void *gles = dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_NOW|RTLD_LOCAL);
    void *lib = shim[0] == '/' ? dlopen(shim, RTLD_NOW|RTLD_LOCAL) : NULL;
    struct objc_api o;
    if (!report("1 load OpenGLES, shim, ObjC", gles && lib && sweet_objc_load(&o))) {
        printf("loader: %s\n", dlerror()); return 1;
    }
    int (*install)(void) = (int (*)(void))dlsym(lib, "sweeteagl_install");
    if (!install || !install()) { report("1 install shim", 0); return 1; }
    CFMutableDictionaryRef props = dictionary();
    const void **accelerated = dlsym(gles, "kEAGLContextPropertyAccelerated");
    const void **retain_release = dlsym(gles, "kEAGLContextPropertyClientRetainRelease");
    if (!report("2 properties dictionary", props && accelerated && retain_release)) return 1;
    CFDictionarySetValue(props, *accelerated, kCFBooleanTrue);
    CFDictionarySetValue(props, *retain_release, kCFBooleanTrue);
    Class cls = o.getClass("EAGLContext");
    id allocated = SEND(id, (id, SEL), cls, "alloc");
    id ctx = SEND(id, (id, SEL, unsigned long, id), allocated, "initWithAPI:properties:", 3, props);
    CFRelease(props);
    if (!report("3 context API == 3", ctx && SEND(unsigned long, (id, SEL), ctx, "API") == 3)) return 1;
    if (!report("4 setCurrentContext", SEND(BOOL, (id, SEL, id), cls, "setCurrentContext:", ctx))) return 1;
    void **table = SEND(void **, (id, SEL), ctx, "getMacroContextPrivate");
    const unsigned offsets[] = SWEET_SLOT_OFFSETS;
    int complete = table && table[0];
    if (complete) for (size_t i = 0; i < sizeof(offsets)/sizeof(offsets[0]); ++i)
        if (!table[offsets[i]/8]) { printf("missing slot %#x\n", offsets[i]); complete = 0; }
    if (!report("5 every offmap/QC slot is non-NULL", complete)) return 1;
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
    const char *mesa_override = getenv("SWEETEAGL_MESA");
    void *mesa = mesa_override ? dlopen(mesa_override, RTLD_NOW|RTLD_LOCAL) :
        dlopen("/System/Library/Extensions/SweetGLES.bundle/libOSMesa.8.dylib", RTLD_NOW|RTLD_LOCAL);
    if (!mesa && !mesa_override) mesa = dlopen("/private/var/root/gpu/libOSMesa.8.dylib", RTLD_NOW|RTLD_LOCAL);
    GLenum (*status)(GLenum) = mesa ? (GLenum (*)(GLenum))dlsym(mesa, "glCheckFramebufferStatus") : NULL;
    if (!report("7 framebuffer complete (Mesa dlsym)", status && status(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE)) goto teardown;
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
    report(cpu ? "8 CPU-copy red pixel" : "8 red pixel", red && error == GL_NO_ERROR);
    GLsync sync = GL_CALL(GLsync, (void *, GLenum, GLbitfield), 0x1860, GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
    GL_CALL(void, (void *), 0x02d0);
    GLenum wait = sync ? GL_CALL(GLenum, (void *, GLsync, GLbitfield, GLuint64), 0x1878,
                                 sync, GL_SYNC_FLUSH_COMMANDS_BIT, (GLuint64)0) : 0;
    report("9 real fence", sync && (wait == GL_ALREADY_SIGNALED || wait == GL_CONDITION_SATISFIED));
    if (sync) GL_CALL(void, (void *, GLsync), 0x1870, sync);
teardown:
    GL_CALL(void, (void *, GLsizei, const GLuint *), 0x1510, 1, &fbo);
    GL_CALL(void, (void *, GLsizei, const GLuint *), 0x01e0, 1, &texture);
    int clean = GL_CALL(GLenum, (void *), 0x0338) == GL_NO_ERROR;
    clean &= SEND(BOOL, (id, SEL, id), cls, "setCurrentContext:", NULL);
    SEND(void, (id, SEL), ctx, "release");
    if (surface) CFRelease(surface);
    report("10 teardown", clean);
    return failures ? 1 : 0;
}
