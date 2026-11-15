/* Mesa/Khronos declarations only. All GL calls resolve via OSMesaGetProcAddress. */
#define GL_GLEXT_PROTOTYPES
#include <GL/osmesa.h>
#include <GL/glext.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* OES_EGL_image is a GLES extension, omitted from desktop GL/glext.h. */
extern void APIENTRY glEGLImageTargetTexture2DOES(GLenum target, GLeglImageOES image);

#define FUNCS(F) \
    F(GetString) F(GetError) F(GetIntegerv) F(CreateShader) F(ShaderSource) \
    F(CompileShader) F(GetShaderiv) F(GetShaderInfoLog) F(DeleteShader) \
    F(CreateProgram) F(AttachShader) F(BindAttribLocation) F(LinkProgram) \
    F(GetProgramiv) F(GetProgramInfoLog) F(DeleteProgram) F(UseProgram) \
    F(GetUniformLocation) F(Uniform1i) F(UniformMatrix4fv) F(GenTextures) \
    F(BindTexture) F(TexParameteri) F(TexImage2D) F(DeleteTextures) \
    F(GenFramebuffers) F(BindFramebuffer) F(FramebufferTexture2D) \
    F(CheckFramebufferStatus) F(DeleteFramebuffers) F(GenBuffers) F(BindBuffer) \
    F(BufferData) F(DeleteBuffers) F(VertexAttribPointer) F(EnableVertexAttribArray) \
    F(DisableVertexAttribArray) F(Viewport) F(ClearColor) F(Clear) F(Enable) \
    F(Disable) F(BlendFuncSeparate) F(DrawArrays) F(ReadPixels) F(FenceSync) \
    F(ClientWaitSync) F(DeleteSync) F(EGLImageTargetTexture2DOES) F(AlphaFunc)
static struct {
#define DECL(n) __typeof__(&gl##n) n;
    FUNCS(DECL)
#undef DECL
} gl;

#define REQUIRE(c, msg) do { if (!(c)) { fprintf(stderr, "FAIL: %s (line %d)\n", msg, __LINE__); exit(1); } } while (0)
static void no_error(const char *where)
{
    GLenum err = gl.GetError();
    if (err) { fprintf(stderr, "FAIL: %s GL error 0x%x\n", where, err); exit(1); }
}
static int extension(const char *list, const char *name)
{
    size_t n = strlen(name);
    for (const char *p = list; (p = strstr(p, name)); p += n)
        if ((p == list || p[-1] == ' ') && (p[n] == ' ' || !p[n])) return 1;
    return 0;
}
static OSMesaContext make_context(int profile, int major, int minor, void *pixels)
{
    const int attrs[] = { OSMESA_PROFILE, profile, OSMESA_CONTEXT_MAJOR_VERSION, major,
        OSMESA_CONTEXT_MINOR_VERSION, minor, OSMESA_FORMAT, OSMESA_RGBA, 0 };
    OSMesaContext ctx = OSMesaCreateContextAttribs(attrs, NULL);
    if (ctx) REQUIRE(OSMesaMakeCurrent(ctx, pixels, GL_UNSIGNED_BYTE, 16, 16), "MakeCurrent");
    return ctx;
}
static GLuint shader(GLenum type, const char *source, const char *label)
{
    GLuint s = gl.CreateShader(type);
    REQUIRE(s, "CreateShader");
    gl.ShaderSource(s, 1, &source, NULL);
    gl.CompileShader(s);
    GLint ok = 0;
    char log[4096] = {0};
    gl.GetShaderiv(s, GL_COMPILE_STATUS, &ok);
    gl.GetShaderInfoLog(s, sizeof(log), NULL, log);
    printf("%s %s %s compile%s%s\n", ok ? "PASS" : "INFO", label,
           type == GL_VERTEX_SHADER ? "vertex" : "fragment", log[0] ? ": " : "", log);
    if (!ok) { gl.DeleteShader(s); return 0; }
    return s;
}
static GLuint program(int version, const char *context)
{
    const char *vs100 = "#version 100\nprecision highp float;\n"
        "attribute vec2 position; attribute vec2 texcoord; varying vec2 uv;\n"
        "uniform mat4 transform; void main() { uv=texcoord; gl_Position=transform*vec4(position,0.0,1.0); }\n";
    const char *fs100 = "#version 100\nprecision mediump float;\n"
        "varying vec2 uv; uniform sampler2D image; void main() { gl_FragColor=texture2D(image,uv); }\n";
    const char *vs300 = "#version 300 es\nprecision highp float;\n"
        "in vec2 position; in vec2 texcoord; out vec2 uv; uniform mat4 transform;\n"
        "void main() { uv=texcoord; gl_Position=transform*vec4(position,0.0,1.0); }\n";
    const char *fs300 = "#version 300 es\nprecision mediump float;\n"
        "in vec2 uv; uniform sampler2D image; out vec4 color; void main() { color=texture(image,uv); }\n";
    char label[128];
    snprintf(label, sizeof(label), "%s GLSL ES %d", context, version);
    GLuint v = shader(GL_VERTEX_SHADER, version == 100 ? vs100 : vs300, label);
    GLuint f = shader(GL_FRAGMENT_SHADER, version == 100 ? fs100 : fs300, label);
    if (!v || !f) { if (v) gl.DeleteShader(v); if (f) gl.DeleteShader(f); return 0; }
    GLuint p = gl.CreateProgram();
    gl.AttachShader(p, v); gl.AttachShader(p, f);
    gl.BindAttribLocation(p, 0, "position"); gl.BindAttribLocation(p, 1, "texcoord");
    gl.LinkProgram(p);
    GLint ok = 0;
    char log[4096] = {0};
    gl.GetProgramiv(p, GL_LINK_STATUS, &ok);
    gl.GetProgramInfoLog(p, sizeof(log), NULL, log);
    printf("%s %s link%s%s\n", ok ? "PASS" : "INFO", label, log[0] ? ": " : "", log);
    gl.DeleteShader(v); gl.DeleteShader(f);
    if (!ok) { gl.DeleteProgram(p); return 0; }
    return p;
}
static void render(GLuint p, const char *label)
{
    /* x scaled by 1/2: only columns 4..11 are covered. This tests the mat4,
     * BGRA channel order, all four texels, untouched background and alpha. */
    static const GLfloat vertices[] = {-1,-1,0,0, 1,-1,1,0, -1,1,0,1, 1,1,1,1};
    static const GLfloat matrix[] = {.5f,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1};
    static const GLubyte bgra[] = {0,0,255,128, 0,255,0,255, 255,0,0,255, 0,255,255,255};
    static const GLubyte colors[][4] = {{128,0,127,128}, {0,255,0,255}, {0,0,255,255}, {255,255,0,255}};
    static const GLubyte background[] = {0,0,255,255};
    GLuint tex[2], fbo, vbo;
    gl.GenTextures(2, tex);
    gl.BindTexture(GL_TEXTURE_2D, tex[0]);
    gl.TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 16, 16, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    gl.GenFramebuffers(1, &fbo); gl.BindFramebuffer(GL_FRAMEBUFFER, fbo);
    gl.FramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex[0], 0);
    REQUIRE(gl.CheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, "RGBA8 FBO complete");
    gl.BindTexture(GL_TEXTURE_2D, tex[1]);
    gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    gl.TexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    /* Same sized internal format / BGRA bytes combination used by SweetEAGL. */
    gl.TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 2, 2, 0, GL_BGRA_EXT, GL_UNSIGNED_BYTE, bgra);
    no_error("BGRA_EXT texture upload");
    gl.GenBuffers(1, &vbo); gl.BindBuffer(GL_ARRAY_BUFFER, vbo);
    gl.BufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
    gl.VertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4*sizeof(GLfloat), NULL);
    gl.VertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4*sizeof(GLfloat), (void *)(2*sizeof(GLfloat)));
    gl.EnableVertexAttribArray(0); gl.EnableVertexAttribArray(1);
    gl.UseProgram(p);
    GLint loc = gl.GetUniformLocation(p, "transform"); REQUIRE(loc >= 0, "mat4 uniform active");
    gl.UniformMatrix4fv(loc, 1, GL_FALSE, matrix);
    loc = gl.GetUniformLocation(p, "image"); REQUIRE(loc >= 0, "sampler uniform active");
    gl.Uniform1i(loc, 0);
    gl.Viewport(0,0,16,16); gl.ClearColor(0,0,1,1); gl.Clear(GL_COLOR_BUFFER_BIT);
    gl.Enable(GL_BLEND); gl.BlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ZERO);
    gl.DrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    GLsync sync = gl.FenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0); REQUIRE(sync, "FenceSync");
    GLenum wait = gl.ClientWaitSync(sync, GL_SYNC_FLUSH_COMMANDS_BIT, UINT64_C(1000000000));
    REQUIRE(wait == GL_ALREADY_SIGNALED || wait == GL_CONDITION_SATISFIED, "ClientWaitSync completion");
    gl.DeleteSync(sync);
    GLubyte pixels[16*16*4]; gl.ReadPixels(0,0,16,16,GL_RGBA,GL_UNSIGNED_BYTE,pixels);
    no_error("draw, fence and readback");
    for (int y=0; y<16; ++y) for (int x=0; x<16; ++x) {
        const GLubyte *expected = (x < 4 || x >= 12) ? background : colors[(y>=8)*2 + (x>=8)];
        const GLubyte *actual = pixels + (y*16+x)*4;
        if (memcmp(actual, expected, 4)) {
            fprintf(stderr,"FAIL %s pixel(%d,%d): %u,%u,%u,%u expected %u,%u,%u,%u\n",label,x,y,
                actual[0],actual[1],actual[2],actual[3],expected[0],expected[1],expected[2],expected[3]);
            exit(1);
        }
    }
    printf("PASS %s RGBA8 FBO: all 256 pixels exact; blended pixel(4,0)=128,0,127,128; GLsync wait=0x%x\n",label,wait);
    gl.Disable(GL_BLEND); gl.DisableVertexAttribArray(0); gl.DisableVertexAttribArray(1);
    gl.BindBuffer(GL_ARRAY_BUFFER,0); gl.DeleteBuffers(1,&vbo);
    gl.BindFramebuffer(GL_FRAMEBUFFER,0); gl.DeleteFramebuffers(1,&fbo);
    gl.BindTexture(GL_TEXTURE_2D,0); gl.DeleteTextures(2,tex); gl.UseProgram(0);
    no_error("cleanup");
}
static void extensions(void)
{
    static const char *qc[] = {
        "GL_APPLE_fence", "GL_APPLE_texture_filter_cubic", "GL_APPLE_texture_ycbcr_basic_formats",
        "GL_APPLE_texture_ycbcr_extended_formats", "GL_APPLE_texture_xr", "GL_APPLE_tile_order_rot",
        "GL_EXT_shader_framebuffer_fetch", "GL_EXT_texture_filter_anisotropic", "GL_EXT_texture_lod_bias",
        "GL_IMG_texture_compression_pvrtc", "GL_KHR_texture_compression_astc_ldr",
        "GL_OES_standard_derivatives", "GL_OES_texture_float", "GL_OES_texture_float_linear",
        "GL_OES_texture_half_float", "GL_OES_texture_half_float_linear"
    };
    const char *ext = (const char *)gl.GetString(GL_EXTENSIONS);
    REQUIRE(ext, "ES GL_EXTENSIONS");
    printf("ES extensions (raw Mesa, no SweetEAGL additions):\n%s\n", ext);
    unsigned present = 0;
    for (unsigned i=0; i<sizeof(qc)/sizeof(qc[0]); ++i) {
        int has = extension(ext,qc[i]); present += has;
        printf("E section 4: %-46s %s\n",qc[i],has ? "present" : "absent");
    }
    printf("INFO E section 4: %u/16 present on native softpipe (freedreno may differ)\n",present);
    REQUIRE(extension(ext,"GL_EXT_texture_format_BGRA8888"), "GL_EXT_texture_format_BGRA8888 exposed");
    REQUIRE(extension(ext,"GL_OES_EGL_image"), "patch 0005 OES_EGL_image exposed in ES");
    printf("PASS GL_EXT_texture_format_BGRA8888 and GL_OES_EGL_image exposed\n");
}
int main(void)
{
    unsigned char buffer[16*16*4];
    OSMesaContext es = make_context(OSMESA_ES_PROFILE,3,0,buffer);
    REQUIRE(es, "ES 3.0 context");
#define LOAD(n) do { \
    OSMESAproc proc=OSMesaGetProcAddress("gl" #n); \
    _Static_assert(sizeof(gl.n)==sizeof(proc), "Linux function pointer size"); \
    memcpy(&gl.n,&proc,sizeof(proc)); REQUIRE(gl.n, "resolve gl" #n); \
} while (0);
    FUNCS(LOAD)
#undef LOAD
    const char *v=(const char *)gl.GetString(GL_VERSION), *s=(const char *)gl.GetString(GL_SHADING_LANGUAGE_VERSION);
    printf("ES GL_VERSION: %s\nES GLSL_VERSION: %s\nES GL_RENDERER: %s\n",v,s,gl.GetString(GL_RENDERER));
    REQUIRE(!strncmp(v,"OpenGL ES 3.",12), "real ES3 GL_VERSION");
    REQUIRE(!strncmp(s,"OpenGL ES GLSL ES",17), "real ES GLSL_VERSION");
    GLint max_major=0,max_minor=0;
    gl.GetIntegerv(GL_MAJOR_VERSION,&max_major); gl.GetIntegerv(GL_MINOR_VERSION,&max_minor);
    extensions();
    for (int ver=100; ver<=300; ver+=200) {
        GLuint p=program(ver,"ES"); REQUIRE(p,"ES compile and link");
        render(p,ver == 100 ? "ES GLSL100" : "ES GLSL300"); gl.DeleteProgram(p);
    }
    /* The Linux softpipe import callback returns NULL, so an invalid ID must
     * reach image validation and report INVALID_VALUE, not an unavailable API. */
    GLuint tex; gl.GenTextures(1,&tex); gl.BindTexture(GL_TEXTURE_2D,tex);
    gl.EGLImageTargetTexture2DOES(GL_TEXTURE_2D,(GLeglImageOES)(uintptr_t)1);
    GLenum err=gl.GetError();
    REQUIRE(err == GL_INVALID_VALUE, "ES EGLImage invalid-ID validation path");
    printf("PASS ES glEGLImageTargetTexture2DOES invalid ID -> GL_INVALID_VALUE (Linux has no IOSurface)\n");
    gl.DeleteTextures(1,&tex);
    gl.AlphaFunc(GL_ALWAYS,0); err=gl.GetError();
    REQUIRE(err == GL_INVALID_OPERATION,"ES rejects desktop-only AlphaFunc");
    printf("PASS ES glAlphaFunc -> GL_INVALID_OPERATION (genuine ES dispatch)\n");
    OSMesaDestroyContext(es);
    const int defaults[]={OSMESA_PROFILE,OSMESA_ES_PROFILE,0};
    es=OSMesaCreateContextAttribs(defaults,NULL); REQUIRE(es,"default ES3 request");
    REQUIRE(OSMesaMakeCurrent(es,buffer,GL_UNSIGNED_BYTE,16,16),"default MakeCurrent");
    REQUIRE(!strncmp((const char *)gl.GetString(GL_VERSION),"OpenGL ES 3.",12),"default is ES3");
    OSMesaDestroyContext(es);
    const int versions[][2]={{2,0},{3,0},{3,1},{3,2},{1,0},{2,1},{3,3},{4,0}};
    for (unsigned i=0;i<sizeof(versions)/sizeof(versions[0]);++i) {
        int major=versions[i][0],minor=versions[i][1];
        es=make_context(OSMESA_ES_PROFILE,major,minor,buffer);
        int valid=(major==2 && minor==0)||(major==3 && minor<=2);
        if (!valid) REQUIRE(!es,"invalid ES version rejected");
        else REQUIRE(!!es == (major*10+minor <= max_major*10+max_minor),"request follows screen capability");
        printf("PASS request ES %d.%d: %s\n",major,minor,es ? (const char *)gl.GetString(GL_VERSION) : "rejected (invalid or above screen capability)");
        if (es) OSMesaDestroyContext(es);
    }
    OSMesaContext desktop=make_context(OSMESA_COMPAT_PROFILE,3,3,buffer);
    REQUIRE(desktop,"desktop compat 3.3 negative control");
    printf("DESKTOP GL_VERSION: %s\nDESKTOP GLSL_VERSION: %s\n",gl.GetString(GL_VERSION),gl.GetString(GL_SHADING_LANGUAGE_VERSION));
    REQUIRE(strncmp((const char *)gl.GetString(GL_VERSION),"OpenGL ES",9),"desktop stays desktop");
    for (int ver=100;ver<=300;ver+=200) {
        GLuint p=program(ver,"DESKTOP negative control");
        printf("INFO DESKTOP same GLSL ES %d: %s\n",ver,p ? "accepted by Mesa compatibility" : "compile/link rejected");
        if (p) { render(p,ver == 100 ? "DESKTOP GLSL100" : "DESKTOP GLSL300"); gl.DeleteProgram(p); }
    }
    gl.AlphaFunc(GL_ALWAYS,0); no_error("desktop AlphaFunc accepted");
    printf("PASS negative control: desktop strings and AlphaFunc semantics differ even if ES shaders compile\n");
    no_error("final"); OSMesaDestroyContext(desktop);
    printf("PASS all native GLES context checks\n");
    return 0;
}
