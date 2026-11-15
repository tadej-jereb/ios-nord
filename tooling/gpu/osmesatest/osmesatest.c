/* osmesatest — layer 6 stage 0: Mesa (OSMesa + freedreno on /dev/dri/renderD128) renders
 * into a user buffer, read back by the CPU. No compositor, no EAGL, nothing installed.
 *   osmesatest            GPU (OSMesa falls back to softpipe if renderD128 is missing)
 *   OSMESA_SOFTWARE=1 osmesatest     softpipe, for comparison
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <mach/mach_time.h>
#include <dlfcn.h>
#include <GL/osmesa.h>
#include <GL/gl.h>

/* dyld refuses @rpath here ("security policy does not allow @ path expansion"), so the
 * library is dlopen'ed by absolute path and every entry point comes from dlsym. */
#define FN(ret, name, args) static ret(*p_##name) args;
#define FNS                                                                                    \
	FN(OSMesaContext, OSMesaCreateContextExt, (GLenum, GLint, GLint, GLint, OSMesaContext))    \
	FN(GLboolean, OSMesaMakeCurrent, (OSMesaContext, void *, GLenum, GLsizei, GLsizei))        \
	FN(void, OSMesaDestroyContext, (OSMesaContext))                                            \
	FN(const GLubyte *, glGetString, (GLenum))                                                 \
	FN(void, glClearColor, (GLfloat, GLfloat, GLfloat, GLfloat))                               \
	FN(void, glClear, (GLbitfield))                                                            \
	FN(void, glFinish, (void))                                                                 \
	FN(void, glViewport, (GLint, GLint, GLsizei, GLsizei))                                     \
	FN(void, glColor4f, (GLfloat, GLfloat, GLfloat, GLfloat))                                  \
	FN(void, glBegin, (GLenum))                                                                \
	FN(void, glEnd, (void))                                                                    \
	FN(void, glVertex2f, (GLfloat, GLfloat))
FNS
#undef FN

static int load(const char *path)
{
	void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
	if (!h) {
		printf("FAIL dlopen %s: %s\n", path, dlerror());
		return -1;
	}
#define FN(ret, name, args)                                                                    \
	if (!(p_##name = (ret(*) args)dlsym(h, #name))) {                                          \
		printf("FAIL dlsym %s\n", #name);                                                     \
		return -1;                                                                         \
	}
	FNS
#undef FN
	return 0;
}
#define OSMesaCreateContextExt p_OSMesaCreateContextExt
#define OSMesaMakeCurrent p_OSMesaMakeCurrent
#define OSMesaDestroyContext p_OSMesaDestroyContext
#define glGetString p_glGetString
#define glClearColor p_glClearColor
#define glClear p_glClear
#define glFinish p_glFinish
#define glViewport p_glViewport
#define glColor4f p_glColor4f
#define glBegin p_glBegin
#define glEnd p_glEnd
#define glVertex2f p_glVertex2f

#define W 256
#define H 256

static double now_ms(void)
{
	static mach_timebase_info_data_t tb;
	if (!tb.denom)
		mach_timebase_info(&tb);
	return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

static unsigned px(const unsigned char *b, int x, int y)
{
	const unsigned char *p = b + 4 * (y * W + x);
	return (unsigned)p[0] << 24 | p[1] << 16 | p[2] << 8 | p[3];
}

int main(int argc, char **argv)
{
	int frames = argc > 1 ? atoi(argv[1]) : 100;
	const char *lib = getenv("OSMESA_LIB") ? getenv("OSMESA_LIB") : "/private/var/root/gpu/libOSMesa.8.dylib";
	double t0 = now_ms();
	if (load(lib))
		return 1;
	printf("dlopen %.1f ms\n", now_ms() - t0);
	t0 = now_ms();
	OSMesaContext ctx = OSMesaCreateContextExt(OSMESA_RGBA, 16, 0, 0, NULL);
	if (!ctx) {
		printf("FAIL OSMesaCreateContextExt\n");
		return 1;
	}
	unsigned char *buf = calloc(W * H, 4);
	if (!OSMesaMakeCurrent(ctx, buf, GL_UNSIGNED_BYTE, W, H)) {
		printf("FAIL OSMesaMakeCurrent\n");
		return 1;
	}
	printf("context %.1f ms\n", now_ms() - t0);
	printf("GL_VENDOR   %s\n", (const char *)glGetString(GL_VENDOR));
	printf("GL_RENDERER %s\n", (const char *)glGetString(GL_RENDERER));
	printf("GL_VERSION  %s\n", (const char *)glGetString(GL_VERSION));

	/* step 1: clear */
	glClearColor(1.0f, 0.0f, 0.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	glFinish();
	unsigned c = px(buf, 10, 10);
	printf("%s clear: pixel(10,10)=%08x want ff0000ff\n", c == 0xff0000ffu ? "PASS" : "FAIL", c);

	/* step 2: triangle (fixed function, compat profile) */
	glViewport(0, 0, W, H);
	glClearColor(0.0f, 0.0f, 1.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);
	glColor4f(0.0f, 1.0f, 0.0f, 1.0f);
	glBegin(GL_TRIANGLES);
	glVertex2f(-0.8f, -0.8f);
	glVertex2f(0.8f, -0.8f);
	glVertex2f(0.0f, 0.8f);
	glEnd();
	glFinish();
	unsigned in = px(buf, W / 2, H / 2), out = px(buf, 5, H - 5);
	int green = 0;
	for (int i = 0; i < W * H; i++)
		green += buf[4 * i + 1] == 0xff && buf[4 * i + 2] == 0;
	printf("%s triangle: centre=%08x corner=%08x green=%d/%d\n",
	       in == 0x00ff00ffu && out == 0x0000ffffu ? "PASS" : "FAIL", in, out, green, W * H);

	/* step 3: throughput — clear + triangle + finish per frame */
	t0 = now_ms();
	for (int f = 0; f < frames; f++) {
		glClearColor((f & 1) ? 1.0f : 0.0f, 0.0f, 0.0f, 1.0f);
		glClear(GL_COLOR_BUFFER_BIT);
		glBegin(GL_TRIANGLES);
		glVertex2f(-0.8f, -0.8f);
		glVertex2f(0.8f, -0.8f);
		glVertex2f(0.0f, 0.8f);
		glEnd();
		glFinish();
	}
	double dt = now_ms() - t0;
	printf("frames %d in %.1f ms = %.3f ms/frame\n", frames, dt, dt / frames);

	OSMesaDestroyContext(ctx);
	printf("DONE\n");
	return 0;
}
