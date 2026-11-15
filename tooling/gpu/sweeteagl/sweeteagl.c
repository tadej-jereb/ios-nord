/* SweetEAGL: E §§2–5, with OSMesa's IOSurface-ID import from Mesa patch 0005.
 * This is C; the Objective-C runtime is exclusively resolved at runtime. */
#include "internal.h"
#include "slots.h"
#include <dlfcn.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

#include <limits.h>
#include <pthread.h>
#include <mach/mach_time.h>

static struct objc_api objc;
static Class eagl_class;
static Ivar private_ivar;
static IMP super_dealloc;
static void *mesa_lib;
static int installed, log_fd = -1, trace;
static unsigned method_count;
static unsigned char traced[SWEET_TABLE_SIZE / 8];
static unsigned char missing[SWEET_TABLE_SIZE / 8];
static unsigned char events[16];

static void log_line(const char *fmt, ...)
{
    if (log_fd < 0) return;
    char line[768];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(line, sizeof(line), fmt, ap);
    va_end(ap);
    if (n > 0) (void)write(log_fd, line, (size_t)n < sizeof(line) ? (size_t)n : sizeof(line)-1);
}
static void event(unsigned which, const char *s)
{
    if (!__atomic_test_and_set(&events[which], __ATOMIC_RELAXED)) log_line("%s\n", s);
}
static void reject(const char *why, IOSurfaceRef s, unsigned long a, unsigned long b, unsigned long c);
static void method_entry(SEL cmd)
{
    /* E §3 method list; task logging bound N=200, global across contexts. */
    if (__atomic_fetch_add(&method_count, 1, __ATOMIC_RELAXED) < 200)
        log_line("method %s\n", objc.selectorName(cmd));
}

#define MESA_FUNCTIONS(F) \
 F(OSMesaContext, OSMesaCreateContextAttribs, (const int *, OSMesaContext)) \
 F(GLboolean, OSMesaMakeCurrent, (OSMesaContext, void *, GLenum, GLsizei, GLsizei)) \
 F(OSMesaContext, OSMesaGetCurrentContext, (void)) \
 F(void, OSMesaDestroyContext, (OSMesaContext)) \
 F(OSMESAproc, OSMesaGetProcAddress, (const char *))
#define DECL(ret, name, args) static ret (*p_##name) args;
MESA_FUNCTIONS(DECL)
#define GL_FUNCTIONS(F) \
 F(const GLubyte *, glGetString, (GLenum)) \
 F(GLenum, glGetError, (void)) \
 F(void, glGetIntegerv, (GLenum, GLint *)) \
 F(void, glBindTexture, (GLenum, GLuint)) \
 F(void, glTexImage2D, (GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void *)) \
 F(void, glTexSubImage2D, (GLenum, GLint, GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, const void *)) \
 F(void, glPixelStorei, (GLenum, GLint)) \
 F(void, glBindBuffer, (GLenum, GLuint)) \
 F(void, glEGLImageTargetTexture2DOES, (GLenum, GLeglImageOES)) \
 F(void, glFinish, (void)) \
 F(void, glGenFramebuffers, (GLsizei, GLuint *)) \
 F(void, glDeleteFramebuffers, (GLsizei, const GLuint *)) \
 F(void, glBindFramebuffer, (GLenum, GLuint)) \
 F(void, glFramebufferTexture2D, (GLenum, GLenum, GLenum, GLuint, GLint)) \
 F(GLenum, glCheckFramebufferStatus, (GLenum)) \
 F(void, glGetFramebufferAttachmentParameteriv, (GLenum, GLenum, GLenum, GLint *)) \
 F(void, glReadPixels, (GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *)) \
 F(GLboolean, glIsProgram, (GLuint)) \
 F(void, glDeleteProgram, (GLuint)) \
 F(void, glDeleteShader, (GLuint))
GL_FUNCTIONS(DECL)
#undef DECL

void *sweet_proc(const char *name)
{
    void *p = p_OSMesaGetProcAddress ? (void *)p_OSMesaGetProcAddress(name) : NULL;
    return p ? p : dlsym(mesa_lib, name);
}
int sweet_enter(struct sweet_context *e, unsigned offset)
{
    if (!e) return 0;
    /* Cheap Mesa TLS lookup avoids a stale shim-only TLS cache if somebody else
     * made an OSMesa context current on this thread. E §2 context-first ABI. */
    if (p_OSMesaGetCurrentContext() != e->mesa &&
        !p_OSMesaMakeCurrent(e->mesa, e->colour, GL_UNSIGNED_BYTE, 16, 16)) {
        event(0, "FAIL OSMesaMakeCurrent"); return 0;
    }
    if (trace && offset && !__atomic_test_and_set(&traced[offset/8], __ATOMIC_RELAXED))
        log_line("slot %#06x\n", offset);
    return 1;
}
void sweet_missing(unsigned offset)
{
    if (!__atomic_test_and_set(&missing[offset/8], __ATOMIC_RELAXED)) log_line("stub %#06x\n", offset);
}

struct image {
    struct image *next;
    IOSurfaceRef surface;
    GLuint texture;
    GLsizei width, height;
    bool copy, dirty, invert;
    /* What QuartzCore asked for (texImageIOSurface:) and what the copy path passes to Mesa.
     * bgra: 4-byte BGRA, the only kind that is imported zero-copy or written back. */
    bool bgra;
    GLenum internal, format, type;
    unsigned bpp;
    uint32_t seed;
};
/* Isolate transfers from CA's pixel-store and PBO state. Row padding is copied
 * explicitly, so even a stride not divisible by four is safe (E §§5/10). */
struct pixel_state { GLint buffer, alignment, row, skip_rows, skip_pixels; };
static void pixel_begin(struct pixel_state *s, bool pack)
{
    GLenum base = pack ? GL_PACK_ALIGNMENT : GL_UNPACK_ALIGNMENT;
    p_glGetIntegerv(pack ? GL_PIXEL_PACK_BUFFER_BINDING : GL_PIXEL_UNPACK_BUFFER_BINDING, &s->buffer);
    p_glGetIntegerv(base, &s->alignment);
    p_glGetIntegerv(pack ? GL_PACK_ROW_LENGTH : GL_UNPACK_ROW_LENGTH, &s->row);
    p_glGetIntegerv(pack ? GL_PACK_SKIP_ROWS : GL_UNPACK_SKIP_ROWS, &s->skip_rows);
    p_glGetIntegerv(pack ? GL_PACK_SKIP_PIXELS : GL_UNPACK_SKIP_PIXELS, &s->skip_pixels);
    p_glBindBuffer(pack ? GL_PIXEL_PACK_BUFFER : GL_PIXEL_UNPACK_BUFFER, 0);
    p_glPixelStorei(base, 1);
    p_glPixelStorei(pack ? GL_PACK_ROW_LENGTH : GL_UNPACK_ROW_LENGTH, 0);
    p_glPixelStorei(pack ? GL_PACK_SKIP_ROWS : GL_UNPACK_SKIP_ROWS, 0);
    p_glPixelStorei(pack ? GL_PACK_SKIP_PIXELS : GL_UNPACK_SKIP_PIXELS, 0);
}
static void pixel_end(const struct pixel_state *s, bool pack)
{
    p_glBindBuffer(pack ? GL_PIXEL_PACK_BUFFER : GL_PIXEL_UNPACK_BUFFER, (GLuint)s->buffer);
    p_glPixelStorei(pack ? GL_PACK_ALIGNMENT : GL_UNPACK_ALIGNMENT, s->alignment);
    p_glPixelStorei(pack ? GL_PACK_ROW_LENGTH : GL_UNPACK_ROW_LENGTH, s->row);
    p_glPixelStorei(pack ? GL_PACK_SKIP_ROWS : GL_UNPACK_SKIP_ROWS, s->skip_rows);
    p_glPixelStorei(pack ? GL_PACK_SKIP_PIXELS : GL_UNPACK_SKIP_PIXELS, s->skip_pixels);
}
static int upload(struct image *im, bool allocate)
{
    size_t row = (size_t)im->width * im->bpp, total = row * (size_t)im->height;
    unsigned char *buf = malloc(total);
    if (!buf) return 0;
    if (IOSurfaceLock(im->surface, SWEET_SURFACE_READONLY, NULL)) { free(buf); return 0; }
    const unsigned char *base = IOSurfaceGetBaseAddress(im->surface);
    size_t stride = IOSurfaceGetBytesPerRow(im->surface);
    if (!base) { IOSurfaceUnlock(im->surface, SWEET_SURFACE_READONLY, NULL); free(buf); return 0; }
    for (int y = 0; y < im->height; ++y)
        memcpy(buf + row*y, base + stride*(im->invert ? im->height-1-y : y), row);
    im->seed = IOSurfaceGetSeed(im->surface);
    IOSurfaceUnlock(im->surface, SWEET_SURFACE_READONLY, NULL);
    struct pixel_state saved;
    pixel_begin(&saved, false);
    if (allocate)
        p_glTexImage2D(GL_TEXTURE_2D, 0, (GLint)im->internal, im->width, im->height, 0, im->format, im->type, buf);
    else
        p_glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, im->width, im->height, im->format, im->type, buf);
    pixel_end(&saved, false);
    free(buf);
    return p_glGetError() == GL_NO_ERROR;
}

/* CPU-copy targets need the reverse transfer too: E §5's upload-only fallback
 * cannot satisfy E §9. Write back only textures actually used as draw targets. */
void sweet_writeback(struct sweet_context *e)
{
    for (struct image *im = e->images; im; im = im->next) {
        if (!im->copy || !im->dirty || !im->bgra) continue;
        size_t row = (size_t)im->width * 4;
        unsigned char *buf = malloc(row * (size_t)im->height);
        if (!buf) { event(1, "FAIL writeback allocation"); continue; }
        GLint read_fbo;
        GLuint fbo;
        p_glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &read_fbo);
        p_glGenFramebuffers(1, &fbo);
        p_glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo);
        p_glFramebufferTexture2D(GL_READ_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, im->texture, 0);
        struct pixel_state saved;
        pixel_begin(&saved, true);
        bool good = p_glCheckFramebufferStatus(GL_READ_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
        if (good) {
            p_glReadPixels(0, 0, im->width, im->height, GL_BGRA, GL_UNSIGNED_BYTE, buf);
            good = p_glGetError() == GL_NO_ERROR;
        }
        pixel_end(&saved, true);
        p_glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)read_fbo);
        p_glDeleteFramebuffers(1, &fbo);
        if (good && !IOSurfaceLock(im->surface, 0, NULL)) {
            unsigned char *base = IOSurfaceGetBaseAddress(im->surface);
            size_t stride = IOSurfaceGetBytesPerRow(im->surface);
            if (base) {
                for (int y = 0; y < im->height; ++y)
                    memcpy(base + stride*(im->invert ? im->height-1-y : y), buf + row*y, row);
                im->dirty = false;
            }
            IOSurfaceUnlock(im->surface, 0, NULL);
        }
        if (im->dirty) event(2, "FAIL CPU writeback");
        free(buf);
    }
}
void sweet_before_draw(struct sweet_context *e)
{
    if (!e->images) return;
    GLint framebuffer, texture = 0, kind = 0, bound;
    p_glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &framebuffer);
    if (framebuffer) {
        p_glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                               GL_FRAMEBUFFER_ATTACHMENT_OBJECT_TYPE, &kind);
        if (kind == GL_TEXTURE)
            p_glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                                   GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, &texture);
    }
    p_glGetIntegerv(GL_TEXTURE_BINDING_2D, &bound);
    for (struct image *im = e->images; im; im = im->next) {
        if (!im->copy) continue;
        /* Re-upload only when the CPU changed the surface since the last copy. */
        if (!im->dirty && IOSurfaceGetSeed(im->surface) != im->seed) {
            event(15, "surface CPU refresh on seed change");
            p_glBindTexture(GL_TEXTURE_2D, im->texture);
            if (!upload(im, false)) { event(3, "FAIL CPU refresh"); reject("refresh-upload", im->surface, im->texture, im->invert, p_glGetError()); }
        }
        if (im->bgra && im->texture == (GLuint)texture) im->dirty = true;
    }
    p_glBindTexture(GL_TEXTURE_2D, (GLuint)bound);
}
void sweet_delete_textures(struct sweet_context *e, GLsizei n, const GLuint *textures)
{
    for (GLsizei i = 0; i < n; ++i) {
        struct image **link = &e->images;
        while (*link) {
            struct image *im = *link;
            if (im->texture != textures[i]) { link = &im->next; continue; }
            *link = im->next;
            CFRelease(im->surface);
            free(im);
        }
    }
}
void sweet_finish(struct sweet_context *e) { p_glFinish(); sweet_writeback(e); }
/*
 * Frame-end calls (glFlush 0x2d8, glFinish 0x2d0, glFenceSync 0x1860, glClientWaitSync 0x1878,
 * glFinishObjectAPPLE 0xeb8): log the first 60 in order, to see how the window server ends a
 * frame. And glFlush waits for the GPU: the kernel's display copy has no GPU fence to wait on,
 * so a flushed-but-unfinished frame can be copied half drawn. Disable with the file
 * /private/var/tmp/sweeteagl.flushonly (checked once per process).
 */
void sweet_frame_mark(struct sweet_context *e, unsigned offset)
{
    static unsigned marks;
    static int flush_finishes = -1;
    if (flush_finishes < 0)
        flush_finishes = access("/private/var/tmp/sweeteagl.flushonly", F_OK) != 0;
    if (__atomic_fetch_add(&marks, 1, __ATOMIC_RELAXED) < 60)
        log_line("frame-mark %#06x\n", offset);
    if (offset != 0x2d8) { (void)e; return; }
    /* Frame rate while frames flow: QuartzCore flushes once per frame. Intervals over 100 ms
     * (idle between gestures) are left out. Every 120 frames: fps, mean frame interval, the
     * slowest interval, and the mean time this thread waited for the GPU. */
    static uint64_t last, active, waited, worst, frames;
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    uint64_t a = mach_absolute_time();
    if (flush_finishes) p_glFinish();
    uint64_t b = mach_absolute_time();
    uint64_t gap = last ? b - last : 0;
    last = b;
    double gap_ms = (double)gap * tb.numer / tb.denom / 1e6;
    if (!gap || gap_ms > 100.0) return;
    active += gap; waited += b - a; frames++;
    if (gap > worst) worst = gap;
    if (frames == 120) {
        double span = (double)active * tb.numer / tb.denom / 1e9;
        log_line("fps %.1f active (%.1f ms/frame, worst %.1f ms), gpu wait %.2f ms/frame\n",
                 frames / span, span * 1e3 / frames, (double)worst * tb.numer / tb.denom / 1e6,
                 (double)waited * tb.numer / tb.denom / 1e6 / frames);
        active = waited = worst = frames = 0;
    }
    (void)e;
}
/* Offmap 0x0e80–0x0eb0: synchronous APPLE_fence compatibility. Waiting
 * eagerly in SetFence is conservative but makes advertising E §4's APPLE_fence
 * honest, without relying on Mesa exporting that legacy API. QC's 0x1860/
 * 0x1878 path still uses real Mesa GLsync objects, independently of this list. */
struct apple_fence { struct apple_fence *next; GLuint name; bool set; };
static struct apple_fence *find_fence(struct sweet_context *e, GLuint name)
{
    for (struct apple_fence *f = e->fences; f; f = f->next) if (f->name == name) return f;
    return NULL;
}
void sweet_glGenFencesAPPLE(struct sweet_context *e, GLsizei n, GLuint *names)
{
    for (GLsizei i = 0; i < n; ++i) {
        struct apple_fence *f = calloc(1, sizeof(*f));
        if (!f) { names[i] = 0; continue; }
        do { ++e->next_fence; } while (!e->next_fence || find_fence(e, e->next_fence));
        f->name = e->next_fence; f->next = e->fences; e->fences = f;
        names[i] = f->name;
    }
}
void sweet_glDeleteFencesAPPLE(struct sweet_context *e, GLsizei n, const GLuint *names)
{
    for (GLsizei i = 0; i < n; ++i) {
        struct apple_fence **link = &e->fences;
        while (*link) {
            struct apple_fence *f = *link;
            if (f->name == names[i]) { *link = f->next; free(f); break; }
            link = &f->next;
        }
    }
}
void sweet_glSetFenceAPPLE(struct sweet_context *e, GLuint name)
{
    struct apple_fence *f = find_fence(e, name);
    if (f) { sweet_finish(e); f->set = true; }
}
GLboolean sweet_glIsFenceAPPLE(struct sweet_context *e, GLuint name)
{
    struct apple_fence *f = find_fence(e, name); return f && f->set;
}
GLboolean sweet_glTestFenceAPPLE(struct sweet_context *e, GLuint name)
{
    return sweet_glIsFenceAPPLE(e, name);
}
void sweet_glFinishFenceAPPLE(struct sweet_context *e, GLuint name)
{
    if (sweet_glIsFenceAPPLE(e, name)) sweet_finish(e);
}
GLboolean sweet_glTestObjectAPPLE(struct sweet_context *e, GLenum object, GLuint name)
{
    if (object == GL_FENCE_APPLE) return sweet_glTestFenceAPPLE(e, name);
    if (object == GL_TEXTURE) { sweet_finish(e); return GL_TRUE; }
    return GL_FALSE;
}
void sweet_delete_program(GLuint name)
{
    /* Offmap 0x1280 aliases DeleteProgram and DeleteShader, E §6 reference. */
    if (p_glIsProgram(name)) p_glDeleteProgram(name); else p_glDeleteShader(name);
}
const GLubyte *sweet_string(struct sweet_context *e, GLenum name)
{
    const GLubyte *s = p_glGetString(name);
    if (name != GL_EXTENSIONS || !s) return s;
    if (!e->extensions) {
        /* E §4: these entry points are honoured as finish/debug no-ops. Do not
         * invent PVRTC, YCbCr, texture_xr, cubic, tile rotation or shader fetch.
         * Keep Mesa's actual capabilities and actual version (see README). */
        const char *extra[] = {"GL_APPLE_fence", "GL_EXT_debug_label", "GL_EXT_debug_marker"};
        size_t n = strlen((const char *)s) + 1;
        for (unsigned i = 0; i < 3; ++i) n += strlen(extra[i]) + 1;
        e->extensions = malloc(n);
        if (!e->extensions) return s;
        strcpy(e->extensions, (const char *)s);
        for (unsigned i = 0; i < 3; ++i) if (!strstr(e->extensions, extra[i])) {
            strcat(e->extensions, " "); strcat(e->extensions, extra[i]);
        }
    }
    return (const GLubyte *)e->extensions;
}

static struct sweet_context *context(id self)
{
    unsigned char *p = objc.getIvar(self, private_ivar);
    return p ? *(struct sweet_context **)(p + SWEET_TABLE_OFFSET) : NULL;
}
static void release_object(id self)
{
    ((void (*)(id, SEL))objc.send)(self, objc.selector("release")); /* E §9 teardown */
}
static id init_context(id self, SEL cmd, unsigned long api, id properties)
{
    method_entry(cmd); (void)properties;
    if (api != 2 && api != 3) { release_object(self); return NULL; }
    struct sweet_context *e = calloc(1, sizeof(*e));
    if (!e) { release_object(self); return NULL; }
    /* Mesa patch 0007's public token; keep building with the old header too,
     * so an older libOSMesa can reject ES and take the desktop fallback. */
#ifndef OSMESA_ES_PROFILE
#define OSMESA_ES_PROFILE 0x38
#endif
    const int es_attrs[] = {OSMESA_FORMAT, OSMESA_RGBA, OSMESA_PROFILE, OSMESA_ES_PROFILE,
                           OSMESA_CONTEXT_MAJOR_VERSION, 3, OSMESA_CONTEXT_MINOR_VERSION, 0, 0};
    const int desktop_attrs[] = {OSMESA_FORMAT, OSMESA_RGBA, OSMESA_PROFILE, OSMESA_COMPAT_PROFILE,
                                OSMESA_CONTEXT_MAJOR_VERSION, 3, OSMESA_CONTEXT_MINOR_VERSION, 3, 0};
    const char *desktop = getenv("SWEETEAGL_DESKTOP");
    int forced_desktop = desktop && !strcmp(desktop, "1");
    int using_es = 0;
    e->api = 3; /* E §1: QuartzCore retries API 2, then requires API == 3. */
    if (!forced_desktop) {
        e->mesa = p_OSMesaCreateContextAttribs(es_attrs, NULL);
        using_es = e->mesa != NULL;
    }
    if (!e->mesa) e->mesa = p_OSMesaCreateContextAttribs(desktop_attrs, NULL);
    e->priv = calloc(1, SWEET_PRIVATE_SIZE); /* E §2 */
    if (!e->mesa || !e->priv || !sweet_enter(e, 0)) {
        if (e->mesa) p_OSMesaDestroyContext(e->mesa);
        free(e->priv); free(e); release_object(self); return NULL;
    }
    unsigned char *p = e->priv;
    *(id *)(p + 0x00) = self; /* E §2: +currentContext's owner */
    *(uint64_t *)(p + 0x10) = 3; /* E §2: API */
    void **table = (void **)(p + SWEET_TABLE_OFFSET);
    table[0] = e; /* E §2 context-first ABI; table[1] is intentionally NULL */
    sweet_slots_fill(table);
    objc.setIvar(self, private_ivar, p);
    event(using_es ? 4 : 14, using_es
          ? "context created (OSMesa OpenGL ES profile, requested 3.0)"
          : "context created (OSMesa desktop compatibility profile, requested 3.3)");
    log_line("context API 3: %s%s\n", (const char *)p_glGetString(GL_VERSION),
             forced_desktop ? " (SWEETEAGL_DESKTOP=1)" : (using_es ? "" : " (ES fallback)"));
    return self;
}
static unsigned long get_api(id self, SEL cmd)
{
    method_entry(cmd); return context(self) ? 3 : 0;
}
static void *get_table(id self, SEL cmd)
{
    method_entry(cmd); struct sweet_context *e = context(self);
    return e ? (unsigned char *)e->priv + SWEET_TABLE_OFFSET : NULL;
}
static unsigned long parameter(id self, SEL cmd, unsigned p, const int *values)
{
    method_entry(cmd); (void)self; (void)p; (void)values; return 0; /* E §3 0x260 */
}
static id sharegroup(id self, SEL cmd) { method_entry(cmd); (void)self; return NULL; }

/* Rejected surfaces, first 40 per process: what QuartzCore actually hands us. */
static unsigned rejects;
static void reject(const char *why, IOSurfaceRef s, unsigned long a, unsigned long b, unsigned long c)
{
    if (__atomic_fetch_add(&rejects, 1, __ATOMIC_RELAXED) >= 40) return;
    if (!s) { log_line("reject %s (no surface)\n", why); return; }
    uint32_t f = IOSurfaceGetPixelFormat(s);
    log_line("reject %s id=%u fmt=%#x '%c%c%c%c' %zux%zu bpe=%zu bpr=%zu planes=%zu args=%#lx,%#lx,%#lx\n",
             why, IOSurfaceGetID(s), f, (char)(f >> 24), (char)(f >> 16), (char)(f >> 8), (char)f,
             IOSurfaceGetWidth(s), IOSurfaceGetHeight(s), IOSurfaceGetBytesPerElement(s),
             IOSurfaceGetBytesPerRow(s), IOSurfaceGetPlaneCount(s), a, b, c);
}
/* Bytes per pixel of a client (format, type) pair, 0 if unknown. */
static unsigned pixel_bytes(GLenum format, GLenum type)
{
    unsigned n;
    switch (format) {
    case GL_ALPHA: case GL_LUMINANCE: case GL_RED: n = 1; break;
    case GL_LUMINANCE_ALPHA: case GL_RG: n = 2; break;
    case GL_RGB: n = 3; break;
    case GL_RGBA: case GL_BGRA: n = 4; break;
    default: return 0;
    }
    switch (type) {
    case GL_UNSIGNED_BYTE: return n;
    case GL_HALF_FLOAT: case 0x8D61 /* GL_HALF_FLOAT_OES */: case GL_UNSIGNED_SHORT: return 2 * n;
    case GL_FLOAT: return 4 * n;
    default: return 0;
    }
}
struct fmt_desc { GLenum internal, format, type; };
static const struct fmt_desc bgra_desc = { GL_RGBA8, GL_BGRA, GL_UNSIGNED_BYTE };

static BOOL attach(struct sweet_context *e, unsigned long target, IOSurfaceRef s, BOOL invert,
                   const struct fmt_desc *d)
{
    if (!e || !s || target != GL_TEXTURE_2D || !sweet_enter(e, 0)) { reject("attach-target", s, target, 0, 0); return false; }
    uint32_t fmt = IOSurfaceGetPixelFormat(s);
    size_t w = IOSurfaceGetWidth(s), h = IOSurfaceGetHeight(s);
    bool bgra = d->format == GL_BGRA && d->type == GL_UNSIGNED_BYTE;
    unsigned bpp = pixel_bytes(d->format, d->type);
    /* A BGRA copy of a surface in another 32-bit format would be wrong; such surfaces ('w30r')
     * are only usable through the zero-copy import, where Mesa picks the format (patch 0008). */
    bool copyable = !bgra || fmt == SWEET_BGRA || fmt == 0;
    if (!bpp || IOSurfaceGetBytesPerElement(s) != bpp ||
        IOSurfaceGetPlaneCount(s) || !w || !h || w > INT_MAX || h > INT_MAX ||
        w > SIZE_MAX/bpp/h || IOSurfaceGetBytesPerRow(s) < w*bpp) { reject("attach-format", s, d->internal, d->format, d->type); return false; }
    GLint tex;
    p_glGetIntegerv(GL_TEXTURE_BINDING_2D, &tex);
    if (!tex) { reject("attach-no-texture", s, 0, 0, 0); return false; }
    GLuint texture = (GLuint)tex;
    sweet_writeback(e);
    sweet_delete_textures(e, 1, &texture);
    struct image *im = calloc(1, sizeof(*im));
    if (!im) return false;
    im->surface = (IOSurfaceRef)CFRetain(s); im->texture = texture;
    im->width = (GLsizei)w; im->height = (GLsizei)h; im->invert = invert;
    im->bgra = bgra; im->bpp = bpp; im->format = d->format; im->type = d->type;
    /* Apple's GL_BGRA internal token means BGRA8; Mesa's ES takes GL_RGBA8 + GL_BGRA (eagltest --cpu). */
    im->internal = bgra ? GL_RGBA8 : d->internal;
    const char *cpu = getenv("SWEETEAGL_CPU");
    /* Import every surface Mesa can take (patch 0008: BGRA, A8, L8, LA88, RGBA16F, w30r), so the
     * GPU reads the surface's own memory and sees every CPU update; IOSurface seeds do not change
     * on CPU writes here (lock/unlock never enter the kernel), so copies go stale. */
    im->copy = (cpu && !strcmp(cpu, "1")) || invert || !p_glEGLImageTargetTexture2DOES;
    if (!im->copy) {
        /* E §5 superseded by Mesa patch 0005: image is an IOSurface ID, no EGL. */
        for (unsigned i = 0; i < 32 && p_glGetError() != GL_NO_ERROR; ++i) {}
        p_glEGLImageTargetTexture2DOES(GL_TEXTURE_2D, (void *)(uintptr_t)IOSurfaceGetID(s));
        im->copy = p_glGetError() != GL_NO_ERROR;
    }
    if (im->copy && !copyable) { reject("attach-not-importable", s, d->internal, d->format, d->type); CFRelease(s); free(im); return false; }
    if (im->copy && !upload(im, true)) { reject("attach-upload", s, d->internal, d->format, d->type); CFRelease(s); free(im); return false; }
    event(im->copy ? 5 : 6, im->copy ? "surface CPU copy" : "surface IOSurface-ID import");
    im->next = e->images; e->images = im;
    return true;
}
static BOOL attach_image(id self, SEL cmd, unsigned long target, IOSurfaceRef s, BOOL invert)
{
    method_entry(cmd); return attach(context(self), target, s, invert, &bgra_desc);
}
static BOOL tex_surface(id self, SEL cmd, IOSurfaceRef s, unsigned long target, unsigned long internal,
                        unsigned w, unsigned h, unsigned long fmt, unsigned long type, unsigned plane, BOOL invert)
{
    method_entry(cmd);
    if (!s || plane || w != IOSurfaceGetWidth(s) || h != IOSurfaceGetHeight(s)) {
        reject("teximage-args", s, internal, fmt, type | (unsigned long)plane << 32); return false;
    }
    /* Any (internal, format, type) QuartzCore passes is copied with exactly that triple: seen on
     * the phone A8 (GL_ALPHA), LA88 (GL_LUMINANCE_ALPHA), RGBA16F/GL_HALF_FLOAT, BGRA. */
    struct fmt_desc d = { (GLenum)internal, (GLenum)fmt, (GLenum)type };
    if (fmt == GL_BGRA && type == GL_UNSIGNED_BYTE) d = bgra_desc;
    return attach(context(self), target, s, invert, &d);
}
static void dealloc_context(id self, SEL cmd)
{
    method_entry(cmd);
    struct sweet_context *e = context(self);
    if (e) {
        if (sweet_enter(e, 0)) sweet_finish(e);
        while (e->images) { GLuint t = e->images->texture; sweet_delete_textures(e, 1, &t); }
        while (e->fences) { GLuint f = e->fences->name; sweet_glDeleteFencesAPPLE(e, 1, &f); }
        if (p_OSMesaGetCurrentContext() == e->mesa)
            p_OSMesaMakeCurrent(NULL, NULL, GL_UNSIGNED_BYTE, 0, 0);
        p_OSMesaDestroyContext(e->mesa);
        objc.setIvar(self, private_ivar, NULL);
        free(e->extensions); free(e->priv); free(e);
    }
    ((void (*)(id, SEL))super_dealloc)(self, cmd);
}

/*
 * +setCurrentContext: / +currentContext. Apple's (OpenGLES 0x1d3f517ec) stores _private with
 * _eagl_ctx_tls_set: pthread_setspecific(30, priv) -- the static slot TPIDRRO_EL0+0xf0 that the
 * gl* stubs read (E §2) -- and then on a key that only _eagl_init creates (pthread_once ->
 * pthread_key_create, 0x1d3f52488 / 0x1d3f52760). _eagl_init runs inside Apple's
 * initWithAPI:, which this shim replaces, so that key is never made and setCurrentContext:
 * returns NO (seen on the phone, logs/phone/eagltest-1.txt). Own both class methods:
 * same static slot, own key for the object, retain new / release old as Apple does.
 */
#define SWEET_OPENGL_TSD_SLOT 30 /* 0xf0 / 8 */
static pthread_key_t current_key;
static pthread_once_t current_once = PTHREAD_ONCE_INIT;
static void current_key_make(void) { (void)pthread_key_create(&current_key, NULL); }
static id current_context(id cls, SEL cmd)
{
    (void)cls; (void)cmd;
    pthread_once(&current_once, current_key_make);
    return (id)pthread_getspecific(current_key);
}
static BOOL set_current_context(id cls, SEL cmd, id ctx)
{
    method_entry(cmd);
    id old = current_context(cls, cmd);
    if (ctx == old) return true;
    void *priv = ctx ? objc.getIvar(ctx, private_ivar) : NULL;
    if (ctx && !priv) return false;
    if (pthread_setspecific(SWEET_OPENGL_TSD_SLOT, priv) || pthread_setspecific(current_key, ctx))
        return false;
    if (ctx) {
        objc.retain(ctx);
        struct sweet_context *e = context(ctx);
        if (e) (void)sweet_enter(e, 0);
    }
    if (old) objc.release(old);
    return true;
}

int sweeteagl_install(void)
{
    if (installed) return 1;
    if (log_fd < 0) log_fd = open("/private/var/tmp/sweeteagl.log", O_WRONLY|O_CREAT|O_APPEND, 0666);
    const char *t = getenv("SWEETEAGL_TRACE"); trace = t && !strcmp(t, "1");
    if (!dlopen("/System/Library/Frameworks/OpenGLES.framework/OpenGLES", RTLD_NOW|RTLD_LOCAL) ||
        !sweet_objc_load(&objc) || !(eagl_class = objc.getClass("EAGLContext")) ||
        !(private_ivar = objc.ivar(eagl_class, "_private"))) {
        event(7, "FAIL ObjC/OpenGLES setup"); return 0;
    }
    const char *path = getenv("SWEETEAGL_MESA");
    if (path) { if (path[0] == '/') mesa_lib = dlopen(path, RTLD_NOW|RTLD_LOCAL); }
    else {
        mesa_lib = dlopen("/System/Library/Extensions/SweetGLES.bundle/libOSMesa.8.dylib", RTLD_NOW|RTLD_LOCAL);
        if (!mesa_lib) mesa_lib = dlopen("/private/var/root/gpu/libOSMesa.8.dylib", RTLD_NOW|RTLD_LOCAL);
    }
    if (!mesa_lib) { event(8, "FAIL Mesa dlopen (override must be absolute)"); return 0; }
#define LOAD_MESA(ret, name, args) \
    p_##name = (ret (*) args)dlsym(mesa_lib, #name); \
    if (!p_##name) { event(9, "FAIL OSMesa symbol"); return 0; }
    MESA_FUNCTIONS(LOAD_MESA)
#undef LOAD_MESA
#define LOAD_GL(ret, name, args) p_##name = (ret (*) args)sweet_proc(#name);
    GL_FUNCTIONS(LOAD_GL)
#undef LOAD_GL
#define CHECK_GL(ret, name, args) if (!p_##name && strcmp(#name, "glEGLImageTargetTexture2DOES")) { event(10, "FAIL GL helper symbol"); return 0; }
    GL_FUNCTIONS(CHECK_GL)
#undef CHECK_GL
    if (!sweet_slots_init()) { event(11, "FAIL required table symbol"); return 0; }
    /* All selectors and exact encodings below: E §3. E §2 supplies _private. */
    super_dealloc = objc.implementation(objc.method(objc.superclass(eagl_class), objc.selector("dealloc")));
    if (!super_dealloc) return 0;
    const struct { const char *name, *encoding; IMP imp; } methods[] = {
        {"initWithAPI:properties:", "@32@0:8Q16@24", (IMP)init_context},
        {"API", "Q16@0:8", (IMP)get_api},
        {"getMacroContextPrivate", "^{EAGLMacroContext=}16@0:8", (IMP)get_table},
        {"setParameter:to:", "Q28@0:8I16^i20", (IMP)parameter},
        {"attachImage:toCoreSurface:invertedRender:", "B36@0:8Q16^{__IOSurface=}24B32", (IMP)attach_image},
        {"texImageIOSurface:target:internalFormat:width:height:format:type:plane:invert:",
         "B72@0:8^{__IOSurface=}16Q24Q32I40I44Q48Q56I64B68", (IMP)tex_surface},
        {"dealloc", "v16@0:8", (IMP)dealloc_context},
        {"sharegroup", "@16@0:8", (IMP)sharegroup}
    };
    for (unsigned i = 0; i < sizeof(methods)/sizeof(methods[0]); ++i)
        objc.replace(eagl_class, objc.selector(methods[i].name), methods[i].imp, methods[i].encoding);
    Class meta = objc.metaClass("EAGLContext");
    if (!meta) { event(13, "FAIL EAGLContext metaclass"); return 0; }
    objc.replace(meta, objc.selector("setCurrentContext:"), (IMP)set_current_context, "B24@0:8@16");
    objc.replace(meta, objc.selector("currentContext"), (IMP)current_context, "@16@0:8");
    installed = 1; event(12, "SweetEAGL installed (8 methods + 2 class methods)"); return 1;
}
__attribute__((constructor)) static void install_constructor(void) { (void)sweeteagl_install(); }
