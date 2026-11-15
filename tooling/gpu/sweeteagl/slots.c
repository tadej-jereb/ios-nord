/* Generated; offsets from data/eagl-offmap.txt and E §4 repairs.
 * GL signatures: Mesa Khronos registry (Apache-2.0).
 * Every entry is a context-first adapter, including kind=direct. */
#include "internal.h"
#include "slots.h"
/* E §4 / offmap 0x0010: glAlphaFunc */
static void (*p_slot_0010)(GLenum, GLfloat);
static void slot_0010(void *opaque, GLenum a0, GLfloat a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 16)) { return; }
    if (!p_slot_0010) { sweet_missing(16); return; }
    p_slot_0010(a0, a1);
}
/* E §4 / offmap 0x0018: glGetFramebufferParameteriAPPLE */
static uintptr_t slot_0018(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 24)) { return 0; }
    sweet_missing(24); return 0;
}
/* E §4 / offmap 0x0030: glBindTexture */
static void (*p_slot_0030)(GLenum, GLuint);
static void slot_0030(void *opaque, GLenum a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 48)) { return; }
    if (!p_slot_0030) { sweet_missing(48); return; }
    p_slot_0030(a0, a1);
}
/* E §4 / offmap 0x0040: glBlendFunc */
static void (*p_slot_0040)(GLenum, GLenum);
static void slot_0040(void *opaque, GLenum a0, GLenum a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 64)) { return; }
    if (!p_slot_0040) { sweet_missing(64); return; }
    p_slot_0040(a0, a1);
}
/* E §4 / offmap 0x0058: glClear */
static void (*p_slot_0058)(GLbitfield);
static void slot_0058(void *opaque, GLbitfield a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 88)) { return; }
    if (!p_slot_0058) { sweet_missing(88); return; }
    sweet_before_draw(e);
    p_slot_0058(a0);
}
/* E §4 / offmap 0x0068: glClearColor */
static void (*p_slot_0068)(GLfloat, GLfloat, GLfloat, GLfloat);
static void slot_0068(void *opaque, GLfloat a0, GLfloat a1, GLfloat a2, GLfloat a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 104)) { return; }
    if (!p_slot_0068) { sweet_missing(104); return; }
    p_slot_0068(a0, a1, a2, a3);
}
/* E §4 / offmap 0x0080: glClearStencil */
static void (*p_slot_0080)(GLint);
static void slot_0080(void *opaque, GLint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 128)) { return; }
    if (!p_slot_0080) { sweet_missing(128); return; }
    p_slot_0080(a0);
}
/* E §4 / offmap 0x00b8: glGetFramebufferParameteriAPPLE */
static uintptr_t slot_00b8(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 184)) { return 0; }
    sweet_missing(184); return 0;
}
/* E §4 / offmap 0x00c0: glGetFramebufferParameteriAPPLE */
static uintptr_t slot_00c0(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 192)) { return 0; }
    sweet_missing(192); return 0;
}
/* E §4 / offmap 0x0130: glColor4f */
static void (*p_slot_0130)(GLfloat, GLfloat, GLfloat, GLfloat);
static void slot_0130(void *opaque, GLfloat a0, GLfloat a1, GLfloat a2, GLfloat a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 304)) { return; }
    if (!p_slot_0130) { sweet_missing(304); return; }
    p_slot_0130(a0, a1, a2, a3);
}
/* E §4 / offmap 0x0160: glColor4ub */
static void (*p_slot_0160)(GLubyte, GLubyte, GLubyte, GLubyte);
static void slot_0160(void *opaque, GLubyte a0, GLubyte a1, GLubyte a2, GLubyte a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 352)) { return; }
    if (!p_slot_0160) { sweet_missing(352); return; }
    p_slot_0160(a0, a1, a2, a3);
}
/* E §4 / offmap 0x0190: glColorMask */
static void (*p_slot_0190)(GLboolean, GLboolean, GLboolean, GLboolean);
static void slot_0190(void *opaque, GLboolean a0, GLboolean a1, GLboolean a2, GLboolean a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 400)) { return; }
    if (!p_slot_0190) { sweet_missing(400); return; }
    p_slot_0190(a0, a1, a2, a3);
}
/* E §4 / offmap 0x01a0: glColorPointer */
static void (*p_slot_01a0)(GLint, GLenum, GLsizei, const void *);
static void slot_01a0(void *opaque, GLint a0, GLenum a1, GLsizei a2, const void * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 416)) { return; }
    if (!p_slot_01a0) { sweet_missing(416); return; }
    p_slot_01a0(a0, a1, a2, a3);
}
/* E §4 / offmap 0x01c8: glCopyTexSubImage2D */
static void (*p_slot_01c8)(GLenum, GLint, GLint, GLint, GLint, GLint, GLsizei, GLsizei);
static void slot_01c8(void *opaque, GLenum a0, GLint a1, GLint a2, GLint a3, GLint a4, GLint a5, GLsizei a6, GLsizei a7) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 456)) { return; }
    if (!p_slot_01c8) { sweet_missing(456); return; }
    p_slot_01c8(a0, a1, a2, a3, a4, a5, a6, a7);
}
/* E §4 / offmap 0x01d0: glCullFace */
static void (*p_slot_01d0)(GLenum);
static void slot_01d0(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 464)) { return; }
    if (!p_slot_01d0) { sweet_missing(464); return; }
    p_slot_01d0(a0);
}
/* E §4 / offmap 0x01e0: glDeleteTextures */
static void (*p_slot_01e0)(GLsizei, const GLuint *);
static void slot_01e0(void *opaque, GLsizei a0, const GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 480)) { return; }
    if (!p_slot_01e0) { sweet_missing(480); return; }
    sweet_delete_textures(e, a0, a1);
    p_slot_01e0(a0, a1);
}
/* E §4 / offmap 0x01e8: glDepthFunc */
static void (*p_slot_01e8)(GLenum);
static void slot_01e8(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 488)) { return; }
    if (!p_slot_01e8) { sweet_missing(488); return; }
    p_slot_01e8(a0);
}
/* E §4 / offmap 0x01f0: glDepthMask */
static void (*p_slot_01f0)(GLboolean);
static void slot_01f0(void *opaque, GLboolean a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 496)) { return; }
    if (!p_slot_01f0) { sweet_missing(496); return; }
    p_slot_01f0(a0);
}
/* E §4 / offmap 0x0200: glDisable */
static void (*p_slot_0200)(GLenum);
static void slot_0200(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 512)) { return; }
    if (!p_slot_0200) { sweet_missing(512); return; }
    p_slot_0200(a0);
}
/* E §4 / offmap 0x0208: glDisableClientState */
static void (*p_slot_0208)(GLenum);
static void slot_0208(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 520)) { return; }
    if (!p_slot_0208) { sweet_missing(520); return; }
    p_slot_0208(a0);
}
/* E §4 / offmap 0x0210: glDrawArrays */
static void (*p_slot_0210)(GLenum, GLint, GLsizei);
static void slot_0210(void *opaque, GLenum a0, GLint a1, GLsizei a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 528)) { return; }
    if (!p_slot_0210) { sweet_missing(528); return; }
    sweet_before_draw(e);
    p_slot_0210(a0, a1, a2);
}
/* E §4 / offmap 0x0220: glDrawElements */
static void (*p_slot_0220)(GLenum, GLsizei, GLenum, const void *);
static void slot_0220(void *opaque, GLenum a0, GLsizei a1, GLenum a2, const void * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 544)) { return; }
    if (!p_slot_0220) { sweet_missing(544); return; }
    sweet_before_draw(e);
    p_slot_0220(a0, a1, a2, a3);
}
/* E §4 / offmap 0x0248: glEnable */
static void (*p_slot_0248)(GLenum);
static void slot_0248(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 584)) { return; }
    if (!p_slot_0248) { sweet_missing(584); return; }
    p_slot_0248(a0);
}
/* E §4 / offmap 0x0250: glEnableClientState */
static void (*p_slot_0250)(GLenum);
static void slot_0250(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 592)) { return; }
    if (!p_slot_0250) { sweet_missing(592); return; }
    p_slot_0250(a0);
}
/* E §4 / offmap 0x02d0: glFinish */
static void (*p_slot_02d0)(void);
static void slot_02d0(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 720)) { return; }
    if (!p_slot_02d0) { sweet_missing(720); return; }
    p_slot_02d0();
    sweet_writeback(e);
    sweet_frame_mark(e, 720);
}
/* E §4 / offmap 0x02d8: glFlush */
static void (*p_slot_02d8)(void);
static void slot_02d8(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 728)) { return; }
    if (!p_slot_02d8) { sweet_missing(728); return; }
    p_slot_02d8();
    sweet_writeback(e);
    sweet_frame_mark(e, 728);
}
/* E §4 / offmap 0x02e0: glFogf */
static void (*p_slot_02e0)(GLenum, GLfloat);
static void slot_02e0(void *opaque, GLenum a0, GLfloat a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 736)) { return; }
    if (!p_slot_02e0) { sweet_missing(736); return; }
    p_slot_02e0(a0, a1);
}
/* E §4 / offmap 0x02e8: glFogfv */
static void (*p_slot_02e8)(GLenum, const GLfloat *);
static void slot_02e8(void *opaque, GLenum a0, const GLfloat * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 744)) { return; }
    if (!p_slot_02e8) { sweet_missing(744); return; }
    p_slot_02e8(a0, a1);
}
/* E §4 / offmap 0x0300: glFrontFace */
static void (*p_slot_0300)(GLenum);
static void slot_0300(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 768)) { return; }
    if (!p_slot_0300) { sweet_missing(768); return; }
    p_slot_0300(a0);
}
/* E §4 / offmap 0x0318: glGenTextures */
static void (*p_slot_0318)(GLsizei, GLuint *);
static void slot_0318(void *opaque, GLsizei a0, GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 792)) { return; }
    if (!p_slot_0318) { sweet_missing(792); return; }
    p_slot_0318(a0, a1);
}
/* E §4 / offmap 0x0320: glGetBooleanv */
static void (*p_slot_0320)(GLenum, GLboolean *);
static void slot_0320(void *opaque, GLenum a0, GLboolean * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 800)) { return; }
    if (!p_slot_0320) { sweet_missing(800); return; }
    p_slot_0320(a0, a1);
}
/* E §4 / offmap 0x0338: glGetError */
static GLenum (*p_slot_0338)(void);
static GLenum slot_0338(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 824)) { return 0; }
    if (!p_slot_0338) { sweet_missing(824); return 0; }
    return p_slot_0338();
}
/* E §4 / offmap 0x0340: glGetFloatv */
static void (*p_slot_0340)(GLenum, GLfloat *);
static void slot_0340(void *opaque, GLenum a0, GLfloat * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 832)) { return; }
    if (!p_slot_0340) { sweet_missing(832); return; }
    p_slot_0340(a0, a1);
}
/* E §4 / offmap 0x0348: glGetIntegerv */
static void (*p_slot_0348)(GLenum, GLint *);
static void slot_0348(void *opaque, GLenum a0, GLint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 840)) { return; }
    if (!p_slot_0348) { sweet_missing(840); return; }
    p_slot_0348(a0, a1);
}
/* E §4 / offmap 0x0350: glGetLightfv */
static void (*p_slot_0350)(GLenum, GLenum, GLfloat *);
static void slot_0350(void *opaque, GLenum a0, GLenum a1, GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 848)) { return; }
    if (!p_slot_0350) { sweet_missing(848); return; }
    p_slot_0350(a0, a1, a2);
}
/* E §4 / offmap 0x0378: glGetMaterialfv */
static void (*p_slot_0378)(GLenum, GLenum, GLfloat *);
static void slot_0378(void *opaque, GLenum a0, GLenum a1, GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 888)) { return; }
    if (!p_slot_0378) { sweet_missing(888); return; }
    p_slot_0378(a0, a1, a2);
}
/* E §4 / offmap 0x03a0: glGetPointerv */
static void (*p_slot_03a0)(GLenum, void **);
static void slot_03a0(void *opaque, GLenum a0, void ** a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 928)) { return; }
    if (!p_slot_03a0) { sweet_missing(928); return; }
    p_slot_03a0(a0, a1);
}
/* E §4 / offmap 0x03b0: glGetString */
static const GLubyte * slot_03b0(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 944)) { return 0; }
    return sweet_string(e, a0);
}
/* E §4 / offmap 0x03b8: glGetTexEnvfv */
static void (*p_slot_03b8)(GLenum, GLenum, GLfloat *);
static void slot_03b8(void *opaque, GLenum a0, GLenum a1, GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 952)) { return; }
    if (!p_slot_03b8) { sweet_missing(952); return; }
    p_slot_03b8(a0, a1, a2);
}
/* E §4 / offmap 0x03c0: glGetTexEnviv */
static void (*p_slot_03c0)(GLenum, GLenum, GLint *);
static void slot_03c0(void *opaque, GLenum a0, GLenum a1, GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 960)) { return; }
    if (!p_slot_03c0) { sweet_missing(960); return; }
    p_slot_03c0(a0, a1, a2);
}
/* E §4 / offmap 0x03e0: glGetTexImage */
static void (*p_slot_03e0)(GLenum, GLint, GLenum, GLenum, void *);
static void slot_03e0(void *opaque, GLenum a0, GLint a1, GLenum a2, GLenum a3, void * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 992)) { return; }
    if (!p_slot_03e0) { sweet_missing(992); return; }
    p_slot_03e0(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x03e8: glGetTexLevelParameterfv */
static void (*p_slot_03e8)(GLenum, GLint, GLenum, GLfloat *);
static void slot_03e8(void *opaque, GLenum a0, GLint a1, GLenum a2, GLfloat * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1000)) { return; }
    if (!p_slot_03e8) { sweet_missing(1000); return; }
    p_slot_03e8(a0, a1, a2, a3);
}
/* E §4 / offmap 0x03f0: glGetTexLevelParameteriv */
static void (*p_slot_03f0)(GLenum, GLint, GLenum, GLint *);
static void slot_03f0(void *opaque, GLenum a0, GLint a1, GLenum a2, GLint * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1008)) { return; }
    if (!p_slot_03f0) { sweet_missing(1008); return; }
    p_slot_03f0(a0, a1, a2, a3);
}
/* E §4 / offmap 0x03f8: glGetTexParameterfv */
static void (*p_slot_03f8)(GLenum, GLenum, GLfloat *);
static void slot_03f8(void *opaque, GLenum a0, GLenum a1, GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1016)) { return; }
    if (!p_slot_03f8) { sweet_missing(1016); return; }
    p_slot_03f8(a0, a1, a2);
}
/* E §4 / offmap 0x0400: glGetTexParameteriv */
static void (*p_slot_0400)(GLenum, GLenum, GLint *);
static void slot_0400(void *opaque, GLenum a0, GLenum a1, GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1024)) { return; }
    if (!p_slot_0400) { sweet_missing(1024); return; }
    p_slot_0400(a0, a1, a2);
}
/* E §4 / offmap 0x0408: glHint */
static void (*p_slot_0408)(GLenum, GLenum);
static void slot_0408(void *opaque, GLenum a0, GLenum a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1032)) { return; }
    if (!p_slot_0408) { sweet_missing(1032); return; }
    p_slot_0408(a0, a1);
}
/* E §4 / offmap 0x0480: glIsEnabled */
static GLboolean (*p_slot_0480)(GLenum);
static GLboolean slot_0480(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1152)) { return 0; }
    if (!p_slot_0480) { sweet_missing(1152); return 0; }
    return p_slot_0480(a0);
}
/* E §4 / offmap 0x0490: glIsTexture */
static GLboolean (*p_slot_0490)(GLuint);
static GLboolean slot_0490(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1168)) { return 0; }
    if (!p_slot_0490) { sweet_missing(1168); return 0; }
    return p_slot_0490(a0);
}
/* E §4 / offmap 0x0498: glLightModelf */
static void (*p_slot_0498)(GLenum, GLfloat);
static void slot_0498(void *opaque, GLenum a0, GLfloat a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1176)) { return; }
    if (!p_slot_0498) { sweet_missing(1176); return; }
    p_slot_0498(a0, a1);
}
/* E §4 / offmap 0x04a0: glLightModelfv */
static void (*p_slot_04a0)(GLenum, const GLfloat *);
static void slot_04a0(void *opaque, GLenum a0, const GLfloat * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1184)) { return; }
    if (!p_slot_04a0) { sweet_missing(1184); return; }
    p_slot_04a0(a0, a1);
}
/* E §4 / offmap 0x04b8: glLightf */
static void (*p_slot_04b8)(GLenum, GLenum, GLfloat);
static void slot_04b8(void *opaque, GLenum a0, GLenum a1, GLfloat a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1208)) { return; }
    if (!p_slot_04b8) { sweet_missing(1208); return; }
    p_slot_04b8(a0, a1, a2);
}
/* E §4 / offmap 0x04c0: glLightfv */
static void (*p_slot_04c0)(GLenum, GLenum, const GLfloat *);
static void slot_04c0(void *opaque, GLenum a0, GLenum a1, const GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1216)) { return; }
    if (!p_slot_04c0) { sweet_missing(1216); return; }
    p_slot_04c0(a0, a1, a2);
}
/* E §4 / offmap 0x04e0: glLineWidth */
static void (*p_slot_04e0)(GLfloat);
static void slot_04e0(void *opaque, GLfloat a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1248)) { return; }
    if (!p_slot_04e0) { sweet_missing(1248); return; }
    p_slot_04e0(a0);
}
/* E §4 / offmap 0x04f0: glLoadIdentity */
static void (*p_slot_04f0)(void);
static void slot_04f0(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1264)) { return; }
    if (!p_slot_04f0) { sweet_missing(1264); return; }
    p_slot_04f0();
}
/* E §4 / offmap 0x0500: glLoadMatrixf */
static void (*p_slot_0500)(const GLfloat *);
static void slot_0500(void *opaque, const GLfloat * a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1280)) { return; }
    if (!p_slot_0500) { sweet_missing(1280); return; }
    p_slot_0500(a0);
}
/* E §4 / offmap 0x0510: glLogicOp */
static void (*p_slot_0510)(GLenum);
static void slot_0510(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1296)) { return; }
    if (!p_slot_0510) { sweet_missing(1296); return; }
    p_slot_0510(a0);
}
/* E §4 / offmap 0x0558: glMaterialf */
static void (*p_slot_0558)(GLenum, GLenum, GLfloat);
static void slot_0558(void *opaque, GLenum a0, GLenum a1, GLfloat a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1368)) { return; }
    if (!p_slot_0558) { sweet_missing(1368); return; }
    p_slot_0558(a0, a1, a2);
}
/* E §4 / offmap 0x0560: glMaterialfv */
static void (*p_slot_0560)(GLenum, GLenum, const GLfloat *);
static void slot_0560(void *opaque, GLenum a0, GLenum a1, const GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1376)) { return; }
    if (!p_slot_0560) { sweet_missing(1376); return; }
    p_slot_0560(a0, a1, a2);
}
/* E §4 / offmap 0x0578: glMatrixMode */
static void (*p_slot_0578)(GLenum);
static void slot_0578(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1400)) { return; }
    if (!p_slot_0578) { sweet_missing(1400); return; }
    p_slot_0578(a0);
}
/* E §4 / offmap 0x0588: glMultMatrixf */
static void (*p_slot_0588)(const GLfloat *);
static void slot_0588(void *opaque, const GLfloat * a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1416)) { return; }
    if (!p_slot_0588) { sweet_missing(1416); return; }
    p_slot_0588(a0);
}
/* E §4 / offmap 0x05b8: glNormal3f */
static void (*p_slot_05b8)(GLfloat, GLfloat, GLfloat);
static void slot_05b8(void *opaque, GLfloat a0, GLfloat a1, GLfloat a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1464)) { return; }
    if (!p_slot_05b8) { sweet_missing(1464); return; }
    p_slot_05b8(a0, a1, a2);
}
/* E §4 / offmap 0x05e8: glNormalPointer */
static void (*p_slot_05e8)(GLenum, GLsizei, const void *);
static void slot_05e8(void *opaque, GLenum a0, GLsizei a1, const void * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1512)) { return; }
    if (!p_slot_05e8) { sweet_missing(1512); return; }
    p_slot_05e8(a0, a1, a2);
}
/* E §4 / offmap 0x0620: glPixelStorei */
static void (*p_slot_0620)(GLenum, GLint);
static void slot_0620(void *opaque, GLenum a0, GLint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1568)) { return; }
    if (!p_slot_0620) { sweet_missing(1568); return; }
    p_slot_0620(a0, a1);
}
/* E §4 / offmap 0x0640: glPointSize */
static void (*p_slot_0640)(GLfloat);
static void slot_0640(void *opaque, GLfloat a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1600)) { return; }
    if (!p_slot_0640) { sweet_missing(1600); return; }
    p_slot_0640(a0);
}
/* E §4 / offmap 0x0650: glPolygonOffset */
static void (*p_slot_0650)(GLfloat, GLfloat);
static void slot_0650(void *opaque, GLfloat a0, GLfloat a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1616)) { return; }
    if (!p_slot_0650) { sweet_missing(1616); return; }
    p_slot_0650(a0, a1);
}
/* E §4 / offmap 0x0660: glGetFramebufferParameteriAPPLE */
static uintptr_t slot_0660(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1632)) { return 0; }
    sweet_missing(1632); return 0;
}
/* E §4 / offmap 0x0668: glGetFramebufferParameteriAPPLE */
static uintptr_t slot_0668(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1640)) { return 0; }
    sweet_missing(1640); return 0;
}
/* E §4 / offmap 0x0670: glPopMatrix */
static void (*p_slot_0670)(void);
static void slot_0670(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1648)) { return; }
    if (!p_slot_0670) { sweet_missing(1648); return; }
    p_slot_0670();
}
/* E §4 / offmap 0x0678: glGetFramebufferParameteriAPPLE */
static uintptr_t slot_0678(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1656)) { return 0; }
    sweet_missing(1656); return 0;
}
/* E §4 / offmap 0x0688: glGetFramebufferParameteriAPPLE */
static uintptr_t slot_0688(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1672)) { return 0; }
    sweet_missing(1672); return 0;
}
/* E §4 / offmap 0x0690: glGetFramebufferParameteriAPPLE */
static uintptr_t slot_0690(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1680)) { return 0; }
    sweet_missing(1680); return 0;
}
/* E §4 / offmap 0x0698: glPushMatrix */
static void (*p_slot_0698)(void);
static void slot_0698(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1688)) { return; }
    if (!p_slot_0698) { sweet_missing(1688); return; }
    p_slot_0698();
}
/* E §4 / offmap 0x0768: glReadBuffer */
static void (*p_slot_0768)(GLenum);
static void slot_0768(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1896)) { return; }
    if (!p_slot_0768) { sweet_missing(1896); return; }
    p_slot_0768(a0);
}
/* E §4 / offmap 0x0770: glReadPixels */
static void (*p_slot_0770)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *);
static void slot_0770(void *opaque, GLint a0, GLint a1, GLsizei a2, GLsizei a3, GLenum a4, GLenum a5, void * a6) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1904)) { return; }
    if (!p_slot_0770) { sweet_missing(1904); return; }
    p_slot_0770(a0, a1, a2, a3, a4, a5, a6);
}
/* E §4 / offmap 0x07c8: glRotatef */
static void (*p_slot_07c8)(GLfloat, GLfloat, GLfloat, GLfloat);
static void slot_07c8(void *opaque, GLfloat a0, GLfloat a1, GLfloat a2, GLfloat a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 1992)) { return; }
    if (!p_slot_07c8) { sweet_missing(1992); return; }
    p_slot_07c8(a0, a1, a2, a3);
}
/* E §4 / offmap 0x07d8: glScalef */
static void (*p_slot_07d8)(GLfloat, GLfloat, GLfloat);
static void slot_07d8(void *opaque, GLfloat a0, GLfloat a1, GLfloat a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2008)) { return; }
    if (!p_slot_07d8) { sweet_missing(2008); return; }
    p_slot_07d8(a0, a1, a2);
}
/* E §4 / offmap 0x07e0: glScissor */
static void (*p_slot_07e0)(GLint, GLint, GLsizei, GLsizei);
static void slot_07e0(void *opaque, GLint a0, GLint a1, GLsizei a2, GLsizei a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2016)) { return; }
    if (!p_slot_07e0) { sweet_missing(2016); return; }
    p_slot_07e0(a0, a1, a2, a3);
}
/* E §4 / offmap 0x07f0: glShadeModel */
static void (*p_slot_07f0)(GLenum);
static void slot_07f0(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2032)) { return; }
    if (!p_slot_07f0) { sweet_missing(2032); return; }
    p_slot_07f0(a0);
}
/* E §4 / offmap 0x07f8: glStencilFunc */
static void (*p_slot_07f8)(GLenum, GLint, GLuint);
static void slot_07f8(void *opaque, GLenum a0, GLint a1, GLuint a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2040)) { return; }
    if (!p_slot_07f8) { sweet_missing(2040); return; }
    p_slot_07f8(a0, a1, a2);
}
/* E §4 / offmap 0x0800: glStencilMask */
static void (*p_slot_0800)(GLuint);
static void slot_0800(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2048)) { return; }
    if (!p_slot_0800) { sweet_missing(2048); return; }
    p_slot_0800(a0);
}
/* E §4 / offmap 0x0808: glStencilOp */
static void (*p_slot_0808)(GLenum, GLenum, GLenum);
static void slot_0808(void *opaque, GLenum a0, GLenum a1, GLenum a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2056)) { return; }
    if (!p_slot_0808) { sweet_missing(2056); return; }
    p_slot_0808(a0, a1, a2);
}
/* E §4 / offmap 0x0910: glTexCoordPointer */
static void (*p_slot_0910)(GLint, GLenum, GLsizei, const void *);
static void slot_0910(void *opaque, GLint a0, GLenum a1, GLsizei a2, const void * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2320)) { return; }
    if (!p_slot_0910) { sweet_missing(2320); return; }
    p_slot_0910(a0, a1, a2, a3);
}
/* E §4 / offmap 0x0918: glTexEnvf */
static void (*p_slot_0918)(GLenum, GLenum, GLfloat);
static void slot_0918(void *opaque, GLenum a0, GLenum a1, GLfloat a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2328)) { return; }
    if (!p_slot_0918) { sweet_missing(2328); return; }
    p_slot_0918(a0, a1, a2);
}
/* E §4 / offmap 0x0920: glTexEnvfv */
static void (*p_slot_0920)(GLenum, GLenum, const GLfloat *);
static void slot_0920(void *opaque, GLenum a0, GLenum a1, const GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2336)) { return; }
    if (!p_slot_0920) { sweet_missing(2336); return; }
    p_slot_0920(a0, a1, a2);
}
/* E §4 / offmap 0x0928: glTexEnvi */
static void (*p_slot_0928)(GLenum, GLenum, GLint);
static void slot_0928(void *opaque, GLenum a0, GLenum a1, GLint a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2344)) { return; }
    if (!p_slot_0928) { sweet_missing(2344); return; }
    p_slot_0928(a0, a1, a2);
}
/* E §4 / offmap 0x0930: glTexEnviv */
static void (*p_slot_0930)(GLenum, GLenum, const GLint *);
static void slot_0930(void *opaque, GLenum a0, GLenum a1, const GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2352)) { return; }
    if (!p_slot_0930) { sweet_missing(2352); return; }
    p_slot_0930(a0, a1, a2);
}
/* E §4 / offmap 0x0970: glTexImage2D */
static void (*p_slot_0970)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void *);
static void slot_0970(void *opaque, GLenum a0, GLint a1, GLint a2, GLsizei a3, GLsizei a4, GLint a5, GLenum a6, GLenum a7, const void * a8) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2416)) { return; }
    if (!p_slot_0970) { sweet_missing(2416); return; }
    if (a2 == GL_BGRA) a2 = GL_RGBA8; /* E §4 Apple internal format */
    p_slot_0970(a0, a1, a2, a3, a4, a5, a6, a7, a8);
}
/* E §4 / offmap 0x0978: glTexParameterf */
static void (*p_slot_0978)(GLenum, GLenum, GLfloat);
static void slot_0978(void *opaque, GLenum a0, GLenum a1, GLfloat a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2424)) { return; }
    if (!p_slot_0978) { sweet_missing(2424); return; }
    p_slot_0978(a0, a1, a2);
}
/* E §4 / offmap 0x0980: glTexParameterfv */
static void (*p_slot_0980)(GLenum, GLenum, const GLfloat *);
static void slot_0980(void *opaque, GLenum a0, GLenum a1, const GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2432)) { return; }
    if (!p_slot_0980) { sweet_missing(2432); return; }
    p_slot_0980(a0, a1, a2);
}
/* E §4 / offmap 0x0988: glTexParameteri */
static void (*p_slot_0988)(GLenum, GLenum, GLint);
static void slot_0988(void *opaque, GLenum a0, GLenum a1, GLint a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2440)) { return; }
    if (!p_slot_0988) { sweet_missing(2440); return; }
    p_slot_0988(a0, a1, a2);
}
/* E §4 / offmap 0x0990: glTexParameteriv */
static void (*p_slot_0990)(GLenum, GLenum, const GLint *);
static void slot_0990(void *opaque, GLenum a0, GLenum a1, const GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2448)) { return; }
    if (!p_slot_0990) { sweet_missing(2448); return; }
    p_slot_0990(a0, a1, a2);
}
/* E §4 / offmap 0x09a0: glTexSubImage2D */
static void (*p_slot_09a0)(GLenum, GLint, GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, const void *);
static void slot_09a0(void *opaque, GLenum a0, GLint a1, GLint a2, GLint a3, GLsizei a4, GLsizei a5, GLenum a6, GLenum a7, const void * a8) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2464)) { return; }
    if (!p_slot_09a0) { sweet_missing(2464); return; }
    p_slot_09a0(a0, a1, a2, a3, a4, a5, a6, a7, a8);
}
/* E §4 / offmap 0x09b0: glTranslatef */
static void (*p_slot_09b0)(GLfloat, GLfloat, GLfloat);
static void slot_09b0(void *opaque, GLfloat a0, GLfloat a1, GLfloat a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2480)) { return; }
    if (!p_slot_09b0) { sweet_missing(2480); return; }
    p_slot_09b0(a0, a1, a2);
}
/* E §4 / offmap 0x0a78: glVertexPointer */
static void (*p_slot_0a78)(GLint, GLenum, GLsizei, const void *);
static void slot_0a78(void *opaque, GLint a0, GLenum a1, GLsizei a2, const void * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2680)) { return; }
    if (!p_slot_0a78) { sweet_missing(2680); return; }
    p_slot_0a78(a0, a1, a2, a3);
}
/* E §4 / offmap 0x0a80: glViewport */
static void (*p_slot_0a80)(GLint, GLint, GLsizei, GLsizei);
static void slot_0a80(void *opaque, GLint a0, GLint a1, GLsizei a2, GLsizei a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2688)) { return; }
    if (!p_slot_0a80) { sweet_missing(2688); return; }
    p_slot_0a80(a0, a1, a2, a3);
}
/* E §4 / offmap 0x0a88: glBlendFuncSeparate */
static void (*p_slot_0a88)(GLenum, GLenum, GLenum, GLenum);
static void slot_0a88(void *opaque, GLenum a0, GLenum a1, GLenum a2, GLenum a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2696)) { return; }
    if (!p_slot_0a88) { sweet_missing(2696); return; }
    p_slot_0a88(a0, a1, a2, a3);
}
/* E §4 / offmap 0x0a90: glBlendColor */
static void (*p_slot_0a90)(GLfloat, GLfloat, GLfloat, GLfloat);
static void slot_0a90(void *opaque, GLfloat a0, GLfloat a1, GLfloat a2, GLfloat a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2704)) { return; }
    if (!p_slot_0a90) { sweet_missing(2704); return; }
    p_slot_0a90(a0, a1, a2, a3);
}
/* E §4 / offmap 0x0a98: glBlendEquation */
static void (*p_slot_0a98)(GLenum);
static void slot_0a98(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2712)) { return; }
    if (!p_slot_0a98) { sweet_missing(2712); return; }
    p_slot_0a98(a0);
}
/* E §4 / offmap 0x0ab0: glClientActiveTexture */
static void (*p_slot_0ab0)(GLenum);
static void slot_0ab0(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2736)) { return; }
    if (!p_slot_0ab0) { sweet_missing(2736); return; }
    p_slot_0ab0(a0);
}
/* E §4 / offmap 0x0ab8: glActiveTexture */
static void (*p_slot_0ab8)(GLenum);
static void slot_0ab8(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2744)) { return; }
    if (!p_slot_0ab8) { sweet_missing(2744); return; }
    p_slot_0ab8(a0);
}
/* E §4 / offmap 0x0b00: glGetFramebufferParameteriAPPLE */
static uintptr_t slot_0b00(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2816)) { return 0; }
    sweet_missing(2816); return 0;
}
/* E §4 / offmap 0x0b90: glMultiTexCoord4f */
static void (*p_slot_0b90)(GLenum, GLfloat, GLfloat, GLfloat, GLfloat);
static void slot_0b90(void *opaque, GLenum a0, GLfloat a1, GLfloat a2, GLfloat a3, GLfloat a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 2960)) { return; }
    if (!p_slot_0b90) { sweet_missing(2960); return; }
    p_slot_0b90(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x0be8: glCompressedTexImage2D */
static void (*p_slot_0be8)(GLenum, GLint, GLenum, GLsizei, GLsizei, GLint, GLsizei, const void *);
static void slot_0be8(void *opaque, GLenum a0, GLint a1, GLenum a2, GLsizei a3, GLsizei a4, GLint a5, GLsizei a6, const void * a7) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3048)) { return; }
    if (!p_slot_0be8) { sweet_missing(3048); return; }
    p_slot_0be8(a0, a1, a2, a3, a4, a5, a6, a7);
}
/* E §4 / offmap 0x0cb0: glDrawRangeElements */
static void (*p_slot_0cb0)(GLenum, GLuint, GLuint, GLsizei, GLenum, const void *);
static void slot_0cb0(void *opaque, GLenum a0, GLuint a1, GLuint a2, GLsizei a3, GLenum a4, const void * a5) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3248)) { return; }
    if (!p_slot_0cb0) { sweet_missing(3248); return; }
    sweet_before_draw(e);
    p_slot_0cb0(a0, a1, a2, a3, a4, a5);
}
/* E §4 / offmap 0x0dd0: glGetUniformIndices */
static void (*p_slot_0dd0)(GLuint, GLsizei, const GLchar *const*, GLuint *);
static void slot_0dd0(void *opaque, GLuint a0, GLsizei a1, const GLchar *const* a2, GLuint * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3536)) { return; }
    if (!p_slot_0dd0) { sweet_missing(3536); return; }
    p_slot_0dd0(a0, a1, a2, a3);
}
/* E §4 / offmap 0x0dd8: glGetActiveUniformsiv */
static void (*p_slot_0dd8)(GLuint, GLsizei, const GLuint *, GLenum, GLint *);
static void slot_0dd8(void *opaque, GLuint a0, GLsizei a1, const GLuint * a2, GLenum a3, GLint * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3544)) { return; }
    if (!p_slot_0dd8) { sweet_missing(3544); return; }
    p_slot_0dd8(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x0de8: glGetUniformBlockIndex */
static GLuint (*p_slot_0de8)(GLuint, const GLchar *);
static GLuint slot_0de8(void *opaque, GLuint a0, const GLchar * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3560)) { return 0; }
    if (!p_slot_0de8) { sweet_missing(3560); return 0; }
    return p_slot_0de8(a0, a1);
}
/* E §4 / offmap 0x0df0: glGetActiveUniformBlockiv */
static void (*p_slot_0df0)(GLuint, GLuint, GLenum, GLint *);
static void slot_0df0(void *opaque, GLuint a0, GLuint a1, GLenum a2, GLint * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3568)) { return; }
    if (!p_slot_0df0) { sweet_missing(3568); return; }
    p_slot_0df0(a0, a1, a2, a3);
}
/* E §4 / offmap 0x0df8: glGetActiveUniformBlockName */
static void (*p_slot_0df8)(GLuint, GLuint, GLsizei, GLsizei *, GLchar *);
static void slot_0df8(void *opaque, GLuint a0, GLuint a1, GLsizei a2, GLsizei * a3, GLchar * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3576)) { return; }
    if (!p_slot_0df8) { sweet_missing(3576); return; }
    p_slot_0df8(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x0e00: glUniformBlockBinding */
static void (*p_slot_0e00)(GLuint, GLuint, GLuint);
static void slot_0e00(void *opaque, GLuint a0, GLuint a1, GLuint a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3584)) { return; }
    if (!p_slot_0e00) { sweet_missing(3584); return; }
    p_slot_0e00(a0, a1, a2);
}
/* E §4 / offmap 0x0e58: glBlendEquationSeparate */
static void (*p_slot_0e58)(GLenum, GLenum);
static void slot_0e58(void *opaque, GLenum a0, GLenum a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3672)) { return; }
    if (!p_slot_0e58) { sweet_missing(3672); return; }
    p_slot_0e58(a0, a1);
}
/* E §4 / offmap 0x0e60: glSampleCoverage */
static void (*p_slot_0e60)(GLfloat, GLboolean);
static void slot_0e60(void *opaque, GLfloat a0, GLboolean a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3680)) { return; }
    if (!p_slot_0e60) { sweet_missing(3680); return; }
    p_slot_0e60(a0, a1);
}
/* E §4 / offmap 0x0e80: glGenFencesAPPLE */
static void slot_0e80(void *opaque, GLsizei a0, GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3712)) { return; }
    sweet_glGenFencesAPPLE(e, a0, a1);
}
/* E §4 / offmap 0x0e88: glDeleteFencesAPPLE */
static void slot_0e88(void *opaque, GLsizei a0, const GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3720)) { return; }
    sweet_glDeleteFencesAPPLE(e, a0, a1);
}
/* E §4 / offmap 0x0e90: glSetFenceAPPLE */
static void slot_0e90(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3728)) { return; }
    sweet_glSetFenceAPPLE(e, a0);
}
/* E §4 / offmap 0x0e98: glIsFenceAPPLE */
static GLboolean slot_0e98(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3736)) { return 0; }
    return sweet_glIsFenceAPPLE(e, a0);
}
/* E §4 / offmap 0x0ea0: glTestFenceAPPLE */
static GLboolean slot_0ea0(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3744)) { return 0; }
    return sweet_glTestFenceAPPLE(e, a0);
}
/* E §4 / offmap 0x0ea8: glFinishFenceAPPLE */
static void slot_0ea8(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3752)) { return; }
    sweet_glFinishFenceAPPLE(e, a0);
}
/* E §4 / offmap 0x0eb0: glTestObjectAPPLE */
static GLboolean slot_0eb0(void *opaque, GLenum a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3760)) { return 0; }
    return sweet_glTestObjectAPPLE(e, a0, a1);
}
/* E §4 / offmap 0x0eb8: glFinishObjectAPPLE */
static void slot_0eb8(void *opaque, GLenum a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3768)) { return; }
    (void)a0; (void)a1; sweet_finish(e); sweet_frame_mark(e, 0xeb8);
}
/* E §4 / offmap 0x0ee8: glVertexAttrib1f */
static void (*p_slot_0ee8)(GLuint, GLfloat);
static void slot_0ee8(void *opaque, GLuint a0, GLfloat a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3816)) { return; }
    if (!p_slot_0ee8) { sweet_missing(3816); return; }
    p_slot_0ee8(a0, a1);
}
/* E §4 / offmap 0x0f00: glVertexAttrib2f */
static void (*p_slot_0f00)(GLuint, GLfloat, GLfloat);
static void slot_0f00(void *opaque, GLuint a0, GLfloat a1, GLfloat a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3840)) { return; }
    if (!p_slot_0f00) { sweet_missing(3840); return; }
    p_slot_0f00(a0, a1, a2);
}
/* E §4 / offmap 0x0f18: glVertexAttrib3f */
static void (*p_slot_0f18)(GLuint, GLfloat, GLfloat, GLfloat);
static void slot_0f18(void *opaque, GLuint a0, GLfloat a1, GLfloat a2, GLfloat a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3864)) { return; }
    if (!p_slot_0f18) { sweet_missing(3864); return; }
    p_slot_0f18(a0, a1, a2, a3);
}
/* E §4 / offmap 0x0f30: glVertexAttrib4f */
static void (*p_slot_0f30)(GLuint, GLfloat, GLfloat, GLfloat, GLfloat);
static void slot_0f30(void *opaque, GLuint a0, GLfloat a1, GLfloat a2, GLfloat a3, GLfloat a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3888)) { return; }
    if (!p_slot_0f30) { sweet_missing(3888); return; }
    p_slot_0f30(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x0f50: glVertexAttrib1fv */
static void (*p_slot_0f50)(GLuint, const GLfloat *);
static void slot_0f50(void *opaque, GLuint a0, const GLfloat * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3920)) { return; }
    if (!p_slot_0f50) { sweet_missing(3920); return; }
    p_slot_0f50(a0, a1);
}
/* E §4 / offmap 0x0f68: glVertexAttrib2fv */
static void (*p_slot_0f68)(GLuint, const GLfloat *);
static void slot_0f68(void *opaque, GLuint a0, const GLfloat * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3944)) { return; }
    if (!p_slot_0f68) { sweet_missing(3944); return; }
    p_slot_0f68(a0, a1);
}
/* E §4 / offmap 0x0f80: glVertexAttrib3fv */
static void (*p_slot_0f80)(GLuint, const GLfloat *);
static void slot_0f80(void *opaque, GLuint a0, const GLfloat * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 3968)) { return; }
    if (!p_slot_0f80) { sweet_missing(3968); return; }
    p_slot_0f80(a0, a1);
}
/* E §4 / offmap 0x0fc0: glVertexAttrib4fv */
static void (*p_slot_0fc0)(GLuint, const GLfloat *);
static void slot_0fc0(void *opaque, GLuint a0, const GLfloat * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4032)) { return; }
    if (!p_slot_0fc0) { sweet_missing(4032); return; }
    p_slot_0fc0(a0, a1);
}
/* E §4 / offmap 0x1000: glVertexAttribPointer */
static void (*p_slot_1000)(GLuint, GLint, GLenum, GLboolean, GLsizei, const void *);
static void slot_1000(void *opaque, GLuint a0, GLint a1, GLenum a2, GLboolean a3, GLsizei a4, const void * a5) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4096)) { return; }
    if (!p_slot_1000) { sweet_missing(4096); return; }
    p_slot_1000(a0, a1, a2, a3, a4, a5);
}
/* E §4 / offmap 0x1008: glEnableVertexAttribArray */
static void (*p_slot_1008)(GLuint);
static void slot_1008(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4104)) { return; }
    if (!p_slot_1008) { sweet_missing(4104); return; }
    p_slot_1008(a0);
}
/* E §4 / offmap 0x1010: glDisableVertexAttribArray */
static void (*p_slot_1010)(GLuint);
static void slot_1010(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4112)) { return; }
    if (!p_slot_1010) { sweet_missing(4112); return; }
    p_slot_1010(a0);
}
/* E §4 / offmap 0x1020: glGetVertexAttribfv */
static void (*p_slot_1020)(GLuint, GLenum, GLfloat *);
static void slot_1020(void *opaque, GLuint a0, GLenum a1, GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4128)) { return; }
    if (!p_slot_1020) { sweet_missing(4128); return; }
    p_slot_1020(a0, a1, a2);
}
/* E §4 / offmap 0x1028: glGetVertexAttribiv */
static void (*p_slot_1028)(GLuint, GLenum, GLint *);
static void slot_1028(void *opaque, GLuint a0, GLenum a1, GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4136)) { return; }
    if (!p_slot_1028) { sweet_missing(4136); return; }
    p_slot_1028(a0, a1, a2);
}
/* E §4 / offmap 0x1030: glGetVertexAttribPointerv */
static void (*p_slot_1030)(GLuint, GLenum, void **);
static void slot_1030(void *opaque, GLuint a0, GLenum a1, void ** a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4144)) { return; }
    if (!p_slot_1030) { sweet_missing(4144); return; }
    p_slot_1030(a0, a1, a2);
}
/* E §4 / offmap 0x10e8: glPointParameterf */
static void (*p_slot_10e8)(GLenum, GLfloat);
static void slot_10e8(void *opaque, GLenum a0, GLfloat a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4328)) { return; }
    if (!p_slot_10e8) { sweet_missing(4328); return; }
    p_slot_10e8(a0, a1);
}
/* E §4 / offmap 0x10f0: glPointParameterfv */
static void (*p_slot_10f0)(GLenum, const GLfloat *);
static void slot_10f0(void *opaque, GLenum a0, const GLfloat * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4336)) { return; }
    if (!p_slot_10f0) { sweet_missing(4336); return; }
    p_slot_10f0(a0, a1);
}
/* E §4 / offmap 0x1258: glStencilOpSeparate */
static void (*p_slot_1258)(GLenum, GLenum, GLenum, GLenum);
static void slot_1258(void *opaque, GLenum a0, GLenum a1, GLenum a2, GLenum a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4696)) { return; }
    if (!p_slot_1258) { sweet_missing(4696); return; }
    p_slot_1258(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1280: glDeleteProgram */
static void slot_1280(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4736)) { return; }
    sweet_delete_program(a0); /* shared shader/program slot, offmap */
}
/* E §4 / offmap 0x1290: glDetachShader */
static void (*p_slot_1290)(GLuint, GLuint);
static void slot_1290(void *opaque, GLuint a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4752)) { return; }
    if (!p_slot_1290) { sweet_missing(4752); return; }
    p_slot_1290(a0, a1);
}
/* E §4 / offmap 0x1298: glCreateShader */
static GLuint (*p_slot_1298)(GLenum);
static GLuint slot_1298(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4760)) { return 0; }
    if (!p_slot_1298) { sweet_missing(4760); return 0; }
    return p_slot_1298(a0);
}
/* E §4 / offmap 0x12a0: glShaderSource */
static void (*p_slot_12a0)(GLuint, GLsizei, const GLchar *const*, const GLint *);
static void slot_12a0(void *opaque, GLuint a0, GLsizei a1, const GLchar *const* a2, const GLint * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4768)) { return; }
    if (!p_slot_12a0) { sweet_missing(4768); return; }
    p_slot_12a0(a0, a1, a2, a3);
}
/* E §4 / offmap 0x12a8: glCompileShader */
static void (*p_slot_12a8)(GLuint);
static void slot_12a8(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4776)) { return; }
    if (!p_slot_12a8) { sweet_missing(4776); return; }
    p_slot_12a8(a0);
}
/* E §4 / offmap 0x12b0: glCreateProgram */
static GLuint (*p_slot_12b0)(void);
static GLuint slot_12b0(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4784)) { return 0; }
    if (!p_slot_12b0) { sweet_missing(4784); return 0; }
    return p_slot_12b0();
}
/* E §4 / offmap 0x12b8: glAttachShader */
static void (*p_slot_12b8)(GLuint, GLuint);
static void slot_12b8(void *opaque, GLuint a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4792)) { return; }
    if (!p_slot_12b8) { sweet_missing(4792); return; }
    p_slot_12b8(a0, a1);
}
/* E §4 / offmap 0x12c0: glLinkProgram */
static void (*p_slot_12c0)(GLuint);
static void slot_12c0(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4800)) { return; }
    if (!p_slot_12c0) { sweet_missing(4800); return; }
    p_slot_12c0(a0);
}
/* E §4 / offmap 0x12c8: glUseProgram */
static void (*p_slot_12c8)(GLuint);
static void slot_12c8(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4808)) { return; }
    if (!p_slot_12c8) { sweet_missing(4808); return; }
    p_slot_12c8(a0);
}
/* E §4 / offmap 0x12d0: glValidateProgram */
static void (*p_slot_12d0)(GLuint);
static void slot_12d0(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4816)) { return; }
    if (!p_slot_12d0) { sweet_missing(4816); return; }
    p_slot_12d0(a0);
}
/* E §4 / offmap 0x12d8: glUniform1f */
static void (*p_slot_12d8)(GLint, GLfloat);
static void slot_12d8(void *opaque, GLint a0, GLfloat a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4824)) { return; }
    if (!p_slot_12d8) { sweet_missing(4824); return; }
    p_slot_12d8(a0, a1);
}
/* E §4 / offmap 0x12e0: glUniform2f */
static void (*p_slot_12e0)(GLint, GLfloat, GLfloat);
static void slot_12e0(void *opaque, GLint a0, GLfloat a1, GLfloat a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4832)) { return; }
    if (!p_slot_12e0) { sweet_missing(4832); return; }
    p_slot_12e0(a0, a1, a2);
}
/* E §4 / offmap 0x12e8: glUniform3f */
static void (*p_slot_12e8)(GLint, GLfloat, GLfloat, GLfloat);
static void slot_12e8(void *opaque, GLint a0, GLfloat a1, GLfloat a2, GLfloat a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4840)) { return; }
    if (!p_slot_12e8) { sweet_missing(4840); return; }
    p_slot_12e8(a0, a1, a2, a3);
}
/* E §4 / offmap 0x12f0: glUniform4f */
static void (*p_slot_12f0)(GLint, GLfloat, GLfloat, GLfloat, GLfloat);
static void slot_12f0(void *opaque, GLint a0, GLfloat a1, GLfloat a2, GLfloat a3, GLfloat a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4848)) { return; }
    if (!p_slot_12f0) { sweet_missing(4848); return; }
    p_slot_12f0(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x12f8: glUniform1i */
static void (*p_slot_12f8)(GLint, GLint);
static void slot_12f8(void *opaque, GLint a0, GLint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4856)) { return; }
    if (!p_slot_12f8) { sweet_missing(4856); return; }
    p_slot_12f8(a0, a1);
}
/* E §4 / offmap 0x1300: glUniform2i */
static void (*p_slot_1300)(GLint, GLint, GLint);
static void slot_1300(void *opaque, GLint a0, GLint a1, GLint a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4864)) { return; }
    if (!p_slot_1300) { sweet_missing(4864); return; }
    p_slot_1300(a0, a1, a2);
}
/* E §4 / offmap 0x1308: glUniform3i */
static void (*p_slot_1308)(GLint, GLint, GLint, GLint);
static void slot_1308(void *opaque, GLint a0, GLint a1, GLint a2, GLint a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4872)) { return; }
    if (!p_slot_1308) { sweet_missing(4872); return; }
    p_slot_1308(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1310: glUniform4i */
static void (*p_slot_1310)(GLint, GLint, GLint, GLint, GLint);
static void slot_1310(void *opaque, GLint a0, GLint a1, GLint a2, GLint a3, GLint a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4880)) { return; }
    if (!p_slot_1310) { sweet_missing(4880); return; }
    p_slot_1310(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1318: glUniform1fv */
static void (*p_slot_1318)(GLint, GLsizei, const GLfloat *);
static void slot_1318(void *opaque, GLint a0, GLsizei a1, const GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4888)) { return; }
    if (!p_slot_1318) { sweet_missing(4888); return; }
    p_slot_1318(a0, a1, a2);
}
/* E §4 / offmap 0x1320: glUniform2fv */
static void (*p_slot_1320)(GLint, GLsizei, const GLfloat *);
static void slot_1320(void *opaque, GLint a0, GLsizei a1, const GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4896)) { return; }
    if (!p_slot_1320) { sweet_missing(4896); return; }
    p_slot_1320(a0, a1, a2);
}
/* E §4 / offmap 0x1328: glUniform3fv */
static void (*p_slot_1328)(GLint, GLsizei, const GLfloat *);
static void slot_1328(void *opaque, GLint a0, GLsizei a1, const GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4904)) { return; }
    if (!p_slot_1328) { sweet_missing(4904); return; }
    p_slot_1328(a0, a1, a2);
}
/* E §4 / offmap 0x1330: glUniform4fv */
static void (*p_slot_1330)(GLint, GLsizei, const GLfloat *);
static void slot_1330(void *opaque, GLint a0, GLsizei a1, const GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4912)) { return; }
    if (!p_slot_1330) { sweet_missing(4912); return; }
    p_slot_1330(a0, a1, a2);
}
/* E §4 / offmap 0x1338: glUniform1iv */
static void (*p_slot_1338)(GLint, GLsizei, const GLint *);
static void slot_1338(void *opaque, GLint a0, GLsizei a1, const GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4920)) { return; }
    if (!p_slot_1338) { sweet_missing(4920); return; }
    p_slot_1338(a0, a1, a2);
}
/* E §4 / offmap 0x1340: glUniform2iv */
static void (*p_slot_1340)(GLint, GLsizei, const GLint *);
static void slot_1340(void *opaque, GLint a0, GLsizei a1, const GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4928)) { return; }
    if (!p_slot_1340) { sweet_missing(4928); return; }
    p_slot_1340(a0, a1, a2);
}
/* E §4 / offmap 0x1348: glUniform3iv */
static void (*p_slot_1348)(GLint, GLsizei, const GLint *);
static void slot_1348(void *opaque, GLint a0, GLsizei a1, const GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4936)) { return; }
    if (!p_slot_1348) { sweet_missing(4936); return; }
    p_slot_1348(a0, a1, a2);
}
/* E §4 / offmap 0x1350: glUniform4iv */
static void (*p_slot_1350)(GLint, GLsizei, const GLint *);
static void slot_1350(void *opaque, GLint a0, GLsizei a1, const GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4944)) { return; }
    if (!p_slot_1350) { sweet_missing(4944); return; }
    p_slot_1350(a0, a1, a2);
}
/* E §4 / offmap 0x1358: glUniformMatrix2fv */
static void (*p_slot_1358)(GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1358(void *opaque, GLint a0, GLsizei a1, GLboolean a2, const GLfloat * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4952)) { return; }
    if (!p_slot_1358) { sweet_missing(4952); return; }
    p_slot_1358(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1360: glUniformMatrix3fv */
static void (*p_slot_1360)(GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1360(void *opaque, GLint a0, GLsizei a1, GLboolean a2, const GLfloat * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4960)) { return; }
    if (!p_slot_1360) { sweet_missing(4960); return; }
    p_slot_1360(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1368: glUniformMatrix4fv */
static void (*p_slot_1368)(GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1368(void *opaque, GLint a0, GLsizei a1, GLboolean a2, const GLfloat * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 4968)) { return; }
    if (!p_slot_1368) { sweet_missing(4968); return; }
    p_slot_1368(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1390: glGetUniformLocation */
static GLint (*p_slot_1390)(GLuint, const GLchar *);
static GLint slot_1390(void *opaque, GLuint a0, const GLchar * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5008)) { return 0; }
    if (!p_slot_1390) { sweet_missing(5008); return 0; }
    return p_slot_1390(a0, a1);
}
/* E §4 / offmap 0x1398: glGetActiveUniform */
static void (*p_slot_1398)(GLuint, GLuint, GLsizei, GLsizei *, GLint *, GLenum *, GLchar *);
static void slot_1398(void *opaque, GLuint a0, GLuint a1, GLsizei a2, GLsizei * a3, GLint * a4, GLenum * a5, GLchar * a6) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5016)) { return; }
    if (!p_slot_1398) { sweet_missing(5016); return; }
    p_slot_1398(a0, a1, a2, a3, a4, a5, a6);
}
/* E §4 / offmap 0x13a0: glGetUniformfv */
static void (*p_slot_13a0)(GLuint, GLint, GLfloat *);
static void slot_13a0(void *opaque, GLuint a0, GLint a1, GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5024)) { return; }
    if (!p_slot_13a0) { sweet_missing(5024); return; }
    p_slot_13a0(a0, a1, a2);
}
/* E §4 / offmap 0x13a8: glGetUniformiv */
static void (*p_slot_13a8)(GLuint, GLint, GLint *);
static void slot_13a8(void *opaque, GLuint a0, GLint a1, GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5032)) { return; }
    if (!p_slot_13a8) { sweet_missing(5032); return; }
    p_slot_13a8(a0, a1, a2);
}
/* E §4 / offmap 0x13b0: glGetShaderSource */
static void (*p_slot_13b0)(GLuint, GLsizei, GLsizei *, GLchar *);
static void slot_13b0(void *opaque, GLuint a0, GLsizei a1, GLsizei * a2, GLchar * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5040)) { return; }
    if (!p_slot_13b0) { sweet_missing(5040); return; }
    p_slot_13b0(a0, a1, a2, a3);
}
/* E §4 / offmap 0x13b8: glBindAttribLocation */
static void (*p_slot_13b8)(GLuint, GLuint, const GLchar *);
static void slot_13b8(void *opaque, GLuint a0, GLuint a1, const GLchar * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5048)) { return; }
    if (!p_slot_13b8) { sweet_missing(5048); return; }
    p_slot_13b8(a0, a1, a2);
}
/* E §4 / offmap 0x13c0: glGetActiveAttrib */
static void (*p_slot_13c0)(GLuint, GLuint, GLsizei, GLsizei *, GLint *, GLenum *, GLchar *);
static void slot_13c0(void *opaque, GLuint a0, GLuint a1, GLsizei a2, GLsizei * a3, GLint * a4, GLenum * a5, GLchar * a6) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5056)) { return; }
    if (!p_slot_13c0) { sweet_missing(5056); return; }
    p_slot_13c0(a0, a1, a2, a3, a4, a5, a6);
}
/* E §4 / offmap 0x13c8: glGetAttribLocation */
static GLint (*p_slot_13c8)(GLuint, const GLchar *);
static GLint slot_13c8(void *opaque, GLuint a0, const GLchar * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5064)) { return 0; }
    if (!p_slot_13c8) { sweet_missing(5064); return 0; }
    return p_slot_13c8(a0, a1);
}
/* E §4 / offmap 0x13d8: glGenQueries */
static void (*p_slot_13d8)(GLsizei, GLuint *);
static void slot_13d8(void *opaque, GLsizei a0, GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5080)) { return; }
    if (!p_slot_13d8) { sweet_missing(5080); return; }
    p_slot_13d8(a0, a1);
}
/* E §4 / offmap 0x13e0: glDeleteQueries */
static void (*p_slot_13e0)(GLsizei, const GLuint *);
static void slot_13e0(void *opaque, GLsizei a0, const GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5088)) { return; }
    if (!p_slot_13e0) { sweet_missing(5088); return; }
    p_slot_13e0(a0, a1);
}
/* E §4 / offmap 0x13e8: glIsQuery */
static GLboolean (*p_slot_13e8)(GLuint);
static GLboolean slot_13e8(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5096)) { return 0; }
    if (!p_slot_13e8) { sweet_missing(5096); return 0; }
    return p_slot_13e8(a0);
}
/* E §4 / offmap 0x13f0: glBeginQuery */
static void (*p_slot_13f0)(GLenum, GLuint);
static void slot_13f0(void *opaque, GLenum a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5104)) { return; }
    if (!p_slot_13f0) { sweet_missing(5104); return; }
    p_slot_13f0(a0, a1);
}
/* E §4 / offmap 0x13f8: glEndQuery */
static void (*p_slot_13f8)(GLenum);
static void slot_13f8(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5112)) { return; }
    if (!p_slot_13f8) { sweet_missing(5112); return; }
    p_slot_13f8(a0);
}
/* E §4 / offmap 0x1400: glGetQueryiv */
static void (*p_slot_1400)(GLenum, GLenum, GLint *);
static void slot_1400(void *opaque, GLenum a0, GLenum a1, GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5120)) { return; }
    if (!p_slot_1400) { sweet_missing(5120); return; }
    p_slot_1400(a0, a1, a2);
}
/* E §4 / offmap 0x1408: glGetQueryObjectivEXT */
static void (*p_slot_1408)(GLuint, GLenum, GLint *);
static void slot_1408(void *opaque, GLuint a0, GLenum a1, GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5128)) { return; }
    if (!p_slot_1408) { sweet_missing(5128); return; }
    p_slot_1408(a0, a1, a2);
}
/* E §4 / offmap 0x1410: glGetQueryObjectuiv */
static void (*p_slot_1410)(GLuint, GLenum, GLuint *);
static void slot_1410(void *opaque, GLuint a0, GLenum a1, GLuint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5136)) { return; }
    if (!p_slot_1410) { sweet_missing(5136); return; }
    p_slot_1410(a0, a1, a2);
}
/* E §4 / offmap 0x1418: glBindBuffer */
static void (*p_slot_1418)(GLenum, GLuint);
static void slot_1418(void *opaque, GLenum a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5144)) { return; }
    if (!p_slot_1418) { sweet_missing(5144); return; }
    p_slot_1418(a0, a1);
}
/* E §4 / offmap 0x1420: glDeleteBuffers */
static void (*p_slot_1420)(GLsizei, const GLuint *);
static void slot_1420(void *opaque, GLsizei a0, const GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5152)) { return; }
    if (!p_slot_1420) { sweet_missing(5152); return; }
    p_slot_1420(a0, a1);
}
/* E §4 / offmap 0x1428: glGenBuffers */
static void (*p_slot_1428)(GLsizei, GLuint *);
static void slot_1428(void *opaque, GLsizei a0, GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5160)) { return; }
    if (!p_slot_1428) { sweet_missing(5160); return; }
    p_slot_1428(a0, a1);
}
/* E §4 / offmap 0x1430: glIsBuffer */
static GLboolean (*p_slot_1430)(GLuint);
static GLboolean slot_1430(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5168)) { return 0; }
    if (!p_slot_1430) { sweet_missing(5168); return 0; }
    return p_slot_1430(a0);
}
/* E §4 / offmap 0x1438: glBufferData */
static void (*p_slot_1438)(GLenum, GLsizeiptr, const void *, GLenum);
static void slot_1438(void *opaque, GLenum a0, GLsizeiptr a1, const void * a2, GLenum a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5176)) { return; }
    if (!p_slot_1438) { sweet_missing(5176); return; }
    p_slot_1438(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1440: glBufferSubData */
static void (*p_slot_1440)(GLenum, GLintptr, GLsizeiptr, const void *);
static void slot_1440(void *opaque, GLenum a0, GLintptr a1, GLsizeiptr a2, const void * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5184)) { return; }
    if (!p_slot_1440) { sweet_missing(5184); return; }
    p_slot_1440(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1450: glMapBufferOES */
static void * (*p_slot_1450)(GLenum, GLenum);
static void * slot_1450(void *opaque, GLenum a0, GLenum a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5200)) { return 0; }
    if (!p_slot_1450) { sweet_missing(5200); return 0; }
    return p_slot_1450(a0, a1);
}
/* E §4 / offmap 0x1458: glUnmapBuffer */
static GLboolean (*p_slot_1458)(GLenum);
static GLboolean slot_1458(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5208)) { return 0; }
    if (!p_slot_1458) { sweet_missing(5208); return 0; }
    return p_slot_1458(a0);
}
/* E §4 / offmap 0x1460: glGetBufferParameteriv */
static void (*p_slot_1460)(GLenum, GLenum, GLint *);
static void slot_1460(void *opaque, GLenum a0, GLenum a1, GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5216)) { return; }
    if (!p_slot_1460) { sweet_missing(5216); return; }
    p_slot_1460(a0, a1, a2);
}
/* E §4 / offmap 0x1468: glGetBufferPointerv */
static void (*p_slot_1468)(GLenum, GLenum, void **);
static void slot_1468(void *opaque, GLenum a0, GLenum a1, void ** a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5224)) { return; }
    if (!p_slot_1468) { sweet_missing(5224); return; }
    p_slot_1468(a0, a1, a2);
}
/* E §4 / offmap 0x1478: glDrawBuffers */
static void (*p_slot_1478)(GLsizei, const GLenum *);
static void slot_1478(void *opaque, GLsizei a0, const GLenum * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5240)) { return; }
    if (!p_slot_1478) { sweet_missing(5240); return; }
    p_slot_1478(a0, a1);
}
/* E §4 / offmap 0x1480: glIsShader */
static GLboolean (*p_slot_1480)(GLuint);
static GLboolean slot_1480(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5248)) { return 0; }
    if (!p_slot_1480) { sweet_missing(5248); return 0; }
    return p_slot_1480(a0);
}
/* E §4 / offmap 0x1488: glIsProgram */
static GLboolean (*p_slot_1488)(GLuint);
static GLboolean slot_1488(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5256)) { return 0; }
    if (!p_slot_1488) { sweet_missing(5256); return 0; }
    return p_slot_1488(a0);
}
/* E §4 / offmap 0x1490: glGetShaderiv */
static void (*p_slot_1490)(GLuint, GLenum, GLint *);
static void slot_1490(void *opaque, GLuint a0, GLenum a1, GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5264)) { return; }
    if (!p_slot_1490) { sweet_missing(5264); return; }
    p_slot_1490(a0, a1, a2);
}
/* E §4 / offmap 0x1498: glGetProgramiv */
static void (*p_slot_1498)(GLuint, GLenum, GLint *);
static void slot_1498(void *opaque, GLuint a0, GLenum a1, GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5272)) { return; }
    if (!p_slot_1498) { sweet_missing(5272); return; }
    p_slot_1498(a0, a1, a2);
}
/* E §4 / offmap 0x14a0: glGetShaderInfoLog */
static void (*p_slot_14a0)(GLuint, GLsizei, GLsizei *, GLchar *);
static void slot_14a0(void *opaque, GLuint a0, GLsizei a1, GLsizei * a2, GLchar * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5280)) { return; }
    if (!p_slot_14a0) { sweet_missing(5280); return; }
    p_slot_14a0(a0, a1, a2, a3);
}
/* E §4 / offmap 0x14a8: glGetProgramInfoLog */
static void (*p_slot_14a8)(GLuint, GLsizei, GLsizei *, GLchar *);
static void slot_14a8(void *opaque, GLuint a0, GLsizei a1, GLsizei * a2, GLchar * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5288)) { return; }
    if (!p_slot_14a8) { sweet_missing(5288); return; }
    p_slot_14a8(a0, a1, a2, a3);
}
/* E §4 / offmap 0x14b0: glStencilFuncSeparate */
static void (*p_slot_14b0)(GLenum, GLenum, GLint, GLuint);
static void slot_14b0(void *opaque, GLenum a0, GLenum a1, GLint a2, GLuint a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5296)) { return; }
    if (!p_slot_14b0) { sweet_missing(5296); return; }
    p_slot_14b0(a0, a1, a2, a3);
}
/* E §4 / offmap 0x14b8: glStencilMaskSeparate */
static void (*p_slot_14b8)(GLenum, GLuint);
static void slot_14b8(void *opaque, GLenum a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5304)) { return; }
    if (!p_slot_14b8) { sweet_missing(5304); return; }
    p_slot_14b8(a0, a1);
}
/* E §4 / offmap 0x14d0: glIsRenderbuffer */
static GLboolean (*p_slot_14d0)(GLuint);
static GLboolean slot_14d0(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5328)) { return 0; }
    if (!p_slot_14d0) { sweet_missing(5328); return 0; }
    return p_slot_14d0(a0);
}
/* E §4 / offmap 0x14d8: glBindRenderbuffer */
static void (*p_slot_14d8)(GLenum, GLuint);
static void slot_14d8(void *opaque, GLenum a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5336)) { return; }
    if (!p_slot_14d8) { sweet_missing(5336); return; }
    p_slot_14d8(a0, a1);
}
/* E §4 / offmap 0x14e0: glDeleteRenderbuffers */
static void (*p_slot_14e0)(GLsizei, const GLuint *);
static void slot_14e0(void *opaque, GLsizei a0, const GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5344)) { return; }
    if (!p_slot_14e0) { sweet_missing(5344); return; }
    p_slot_14e0(a0, a1);
}
/* E §4 / offmap 0x14e8: glGenRenderbuffers */
static void (*p_slot_14e8)(GLsizei, GLuint *);
static void slot_14e8(void *opaque, GLsizei a0, GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5352)) { return; }
    if (!p_slot_14e8) { sweet_missing(5352); return; }
    p_slot_14e8(a0, a1);
}
/* E §4 / offmap 0x14f0: glRenderbufferStorage */
static void (*p_slot_14f0)(GLenum, GLenum, GLsizei, GLsizei);
static void slot_14f0(void *opaque, GLenum a0, GLenum a1, GLsizei a2, GLsizei a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5360)) { return; }
    if (!p_slot_14f0) { sweet_missing(5360); return; }
    p_slot_14f0(a0, a1, a2, a3);
}
/* E §4 / offmap 0x14f8: glGetRenderbufferParameteriv */
static void (*p_slot_14f8)(GLenum, GLenum, GLint *);
static void slot_14f8(void *opaque, GLenum a0, GLenum a1, GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5368)) { return; }
    if (!p_slot_14f8) { sweet_missing(5368); return; }
    p_slot_14f8(a0, a1, a2);
}
/* E §4 / offmap 0x1500: glIsFramebuffer */
static GLboolean (*p_slot_1500)(GLuint);
static GLboolean slot_1500(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5376)) { return 0; }
    if (!p_slot_1500) { sweet_missing(5376); return 0; }
    return p_slot_1500(a0);
}
/* E §4 / offmap 0x1508: glBindFramebuffer */
static void (*p_slot_1508)(GLenum, GLuint);
static void slot_1508(void *opaque, GLenum a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5384)) { return; }
    if (!p_slot_1508) { sweet_missing(5384); return; }
    p_slot_1508(a0, a1);
}
/* E §4 / offmap 0x1510: glDeleteFramebuffers */
static void (*p_slot_1510)(GLsizei, const GLuint *);
static void slot_1510(void *opaque, GLsizei a0, const GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5392)) { return; }
    if (!p_slot_1510) { sweet_missing(5392); return; }
    p_slot_1510(a0, a1);
}
/* E §4 / offmap 0x1518: glGenFramebuffers */
static void (*p_slot_1518)(GLsizei, GLuint *);
static void slot_1518(void *opaque, GLsizei a0, GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5400)) { return; }
    if (!p_slot_1518) { sweet_missing(5400); return; }
    p_slot_1518(a0, a1);
}
/* E §4 / offmap 0x1520: glCheckFramebufferStatus */
static GLenum (*p_slot_1520)(GLenum);
static GLenum slot_1520(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5408)) { return 0; }
    if (!p_slot_1520) { sweet_missing(5408); return 0; }
    return p_slot_1520(a0);
}
/* E §4 / offmap 0x1530: glFramebufferTexture2D */
static void (*p_slot_1530)(GLenum, GLenum, GLenum, GLuint, GLint);
static void slot_1530(void *opaque, GLenum a0, GLenum a1, GLenum a2, GLuint a3, GLint a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5424)) { return; }
    if (!p_slot_1530) { sweet_missing(5424); return; }
    p_slot_1530(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1540: glFramebufferRenderbuffer */
static void (*p_slot_1540)(GLenum, GLenum, GLenum, GLuint);
static void slot_1540(void *opaque, GLenum a0, GLenum a1, GLenum a2, GLuint a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5440)) { return; }
    if (!p_slot_1540) { sweet_missing(5440); return; }
    p_slot_1540(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1548: glGetFramebufferAttachmentParameteriv */
static void (*p_slot_1548)(GLenum, GLenum, GLenum, GLint *);
static void slot_1548(void *opaque, GLenum a0, GLenum a1, GLenum a2, GLint * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5448)) { return; }
    if (!p_slot_1548) { sweet_missing(5448); return; }
    p_slot_1548(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1550: glGenerateMipmap */
static void (*p_slot_1550)(GLenum);
static void slot_1550(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5456)) { return; }
    if (!p_slot_1550) { sweet_missing(5456); return; }
    p_slot_1550(a0);
}
/* E §4 / offmap 0x1590: glProgramParameteri */
static void (*p_slot_1590)(GLuint, GLenum, GLint);
static void slot_1590(void *opaque, GLuint a0, GLenum a1, GLint a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5520)) { return; }
    if (!p_slot_1590) { sweet_missing(5520); return; }
    p_slot_1590(a0, a1, a2);
}
/* E §4 / offmap 0x15a0: glFramebufferTextureLayer */
static void (*p_slot_15a0)(GLenum, GLenum, GLuint, GLint, GLint);
static void slot_15a0(void *opaque, GLenum a0, GLenum a1, GLuint a2, GLint a3, GLint a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5536)) { return; }
    if (!p_slot_15a0) { sweet_missing(5536); return; }
    p_slot_15a0(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x15b0: glBindBufferRange */
static void (*p_slot_15b0)(GLenum, GLuint, GLuint, GLintptr, GLsizeiptr);
static void slot_15b0(void *opaque, GLenum a0, GLuint a1, GLuint a2, GLintptr a3, GLsizeiptr a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5552)) { return; }
    if (!p_slot_15b0) { sweet_missing(5552); return; }
    p_slot_15b0(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x15c0: glBindBufferBase */
static void (*p_slot_15c0)(GLenum, GLuint, GLuint);
static void slot_15c0(void *opaque, GLenum a0, GLuint a1, GLuint a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5568)) { return; }
    if (!p_slot_15c0) { sweet_missing(5568); return; }
    p_slot_15c0(a0, a1, a2);
}
/* E §4 / offmap 0x15c8: glBeginTransformFeedback */
static void (*p_slot_15c8)(GLenum);
static void slot_15c8(void *opaque, GLenum a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5576)) { return; }
    if (!p_slot_15c8) { sweet_missing(5576); return; }
    p_slot_15c8(a0);
}
/* E §4 / offmap 0x15d0: glEndTransformFeedback */
static void (*p_slot_15d0)(void);
static void slot_15d0(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5584)) { return; }
    if (!p_slot_15d0) { sweet_missing(5584); return; }
    p_slot_15d0();
}
/* E §4 / offmap 0x15d8: glTransformFeedbackVaryings */
static void (*p_slot_15d8)(GLuint, GLsizei, const GLchar *const*, GLenum);
static void slot_15d8(void *opaque, GLuint a0, GLsizei a1, const GLchar *const* a2, GLenum a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5592)) { return; }
    if (!p_slot_15d8) { sweet_missing(5592); return; }
    p_slot_15d8(a0, a1, a2, a3);
}
/* E §4 / offmap 0x15e0: glGetTransformFeedbackVarying */
static void (*p_slot_15e0)(GLuint, GLuint, GLsizei, GLsizei *, GLsizei *, GLenum *, GLchar *);
static void slot_15e0(void *opaque, GLuint a0, GLuint a1, GLsizei a2, GLsizei * a3, GLsizei * a4, GLenum * a5, GLchar * a6) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5600)) { return; }
    if (!p_slot_15e0) { sweet_missing(5600); return; }
    p_slot_15e0(a0, a1, a2, a3, a4, a5, a6);
}
/* E §4 / offmap 0x15e8: glGetIntegeri_v */
static void (*p_slot_15e8)(GLenum, GLuint, GLint *);
static void slot_15e8(void *opaque, GLenum a0, GLuint a1, GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5608)) { return; }
    if (!p_slot_15e8) { sweet_missing(5608); return; }
    p_slot_15e8(a0, a1, a2);
}
/* E §4 / offmap 0x1658: glVertexAttribI4i */
static void (*p_slot_1658)(GLuint, GLint, GLint, GLint, GLint);
static void slot_1658(void *opaque, GLuint a0, GLint a1, GLint a2, GLint a3, GLint a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5720)) { return; }
    if (!p_slot_1658) { sweet_missing(5720); return; }
    p_slot_1658(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1678: glVertexAttribI4ui */
static void (*p_slot_1678)(GLuint, GLuint, GLuint, GLuint, GLuint);
static void slot_1678(void *opaque, GLuint a0, GLuint a1, GLuint a2, GLuint a3, GLuint a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5752)) { return; }
    if (!p_slot_1678) { sweet_missing(5752); return; }
    p_slot_1678(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1698: glVertexAttribI4iv */
static void (*p_slot_1698)(GLuint, const GLint *);
static void slot_1698(void *opaque, GLuint a0, const GLint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5784)) { return; }
    if (!p_slot_1698) { sweet_missing(5784); return; }
    p_slot_1698(a0, a1);
}
/* E §4 / offmap 0x16b8: glVertexAttribI4uiv */
static void (*p_slot_16b8)(GLuint, const GLuint *);
static void slot_16b8(void *opaque, GLuint a0, const GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5816)) { return; }
    if (!p_slot_16b8) { sweet_missing(5816); return; }
    p_slot_16b8(a0, a1);
}
/* E §4 / offmap 0x16e0: glVertexAttribIPointer */
static void (*p_slot_16e0)(GLuint, GLint, GLenum, GLsizei, const void *);
static void slot_16e0(void *opaque, GLuint a0, GLint a1, GLenum a2, GLsizei a3, const void * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5856)) { return; }
    if (!p_slot_16e0) { sweet_missing(5856); return; }
    p_slot_16e0(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x16e8: glGetVertexAttribIiv */
static void (*p_slot_16e8)(GLuint, GLenum, GLint *);
static void slot_16e8(void *opaque, GLuint a0, GLenum a1, GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5864)) { return; }
    if (!p_slot_16e8) { sweet_missing(5864); return; }
    p_slot_16e8(a0, a1, a2);
}
/* E §4 / offmap 0x16f0: glGetVertexAttribIuiv */
static void (*p_slot_16f0)(GLuint, GLenum, GLuint *);
static void slot_16f0(void *opaque, GLuint a0, GLenum a1, GLuint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5872)) { return; }
    if (!p_slot_16f0) { sweet_missing(5872); return; }
    p_slot_16f0(a0, a1, a2);
}
/* E §4 / offmap 0x16f8: glUniform1ui */
static void (*p_slot_16f8)(GLint, GLuint);
static void slot_16f8(void *opaque, GLint a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5880)) { return; }
    if (!p_slot_16f8) { sweet_missing(5880); return; }
    p_slot_16f8(a0, a1);
}
/* E §4 / offmap 0x1700: glUniform2ui */
static void (*p_slot_1700)(GLint, GLuint, GLuint);
static void slot_1700(void *opaque, GLint a0, GLuint a1, GLuint a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5888)) { return; }
    if (!p_slot_1700) { sweet_missing(5888); return; }
    p_slot_1700(a0, a1, a2);
}
/* E §4 / offmap 0x1708: glUniform3ui */
static void (*p_slot_1708)(GLint, GLuint, GLuint, GLuint);
static void slot_1708(void *opaque, GLint a0, GLuint a1, GLuint a2, GLuint a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5896)) { return; }
    if (!p_slot_1708) { sweet_missing(5896); return; }
    p_slot_1708(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1710: glUniform4ui */
static void (*p_slot_1710)(GLint, GLuint, GLuint, GLuint, GLuint);
static void slot_1710(void *opaque, GLint a0, GLuint a1, GLuint a2, GLuint a3, GLuint a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5904)) { return; }
    if (!p_slot_1710) { sweet_missing(5904); return; }
    p_slot_1710(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1718: glUniform1uiv */
static void (*p_slot_1718)(GLint, GLsizei, const GLuint *);
static void slot_1718(void *opaque, GLint a0, GLsizei a1, const GLuint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5912)) { return; }
    if (!p_slot_1718) { sweet_missing(5912); return; }
    p_slot_1718(a0, a1, a2);
}
/* E §4 / offmap 0x1720: glUniform2uiv */
static void (*p_slot_1720)(GLint, GLsizei, const GLuint *);
static void slot_1720(void *opaque, GLint a0, GLsizei a1, const GLuint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5920)) { return; }
    if (!p_slot_1720) { sweet_missing(5920); return; }
    p_slot_1720(a0, a1, a2);
}
/* E §4 / offmap 0x1728: glUniform3uiv */
static void (*p_slot_1728)(GLint, GLsizei, const GLuint *);
static void slot_1728(void *opaque, GLint a0, GLsizei a1, const GLuint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5928)) { return; }
    if (!p_slot_1728) { sweet_missing(5928); return; }
    p_slot_1728(a0, a1, a2);
}
/* E §4 / offmap 0x1730: glUniform4uiv */
static void (*p_slot_1730)(GLint, GLsizei, const GLuint *);
static void slot_1730(void *opaque, GLint a0, GLsizei a1, const GLuint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5936)) { return; }
    if (!p_slot_1730) { sweet_missing(5936); return; }
    p_slot_1730(a0, a1, a2);
}
/* E §4 / offmap 0x1738: glGetUniformuiv */
static void (*p_slot_1738)(GLuint, GLint, GLuint *);
static void slot_1738(void *opaque, GLuint a0, GLint a1, GLuint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5944)) { return; }
    if (!p_slot_1738) { sweet_missing(5944); return; }
    p_slot_1738(a0, a1, a2);
}
/* E §4 / offmap 0x1748: glGetFragDataLocation */
static GLint (*p_slot_1748)(GLuint, const GLchar *);
static GLint slot_1748(void *opaque, GLuint a0, const GLchar * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 5960)) { return 0; }
    if (!p_slot_1748) { sweet_missing(5960); return 0; }
    return p_slot_1748(a0, a1);
}
/* E §4 / offmap 0x1770: glUniformMatrix2x3fv */
static void (*p_slot_1770)(GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1770(void *opaque, GLint a0, GLsizei a1, GLboolean a2, const GLfloat * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6000)) { return; }
    if (!p_slot_1770) { sweet_missing(6000); return; }
    p_slot_1770(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1778: glUniformMatrix3x2fv */
static void (*p_slot_1778)(GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1778(void *opaque, GLint a0, GLsizei a1, GLboolean a2, const GLfloat * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6008)) { return; }
    if (!p_slot_1778) { sweet_missing(6008); return; }
    p_slot_1778(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1780: glUniformMatrix2x4fv */
static void (*p_slot_1780)(GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1780(void *opaque, GLint a0, GLsizei a1, GLboolean a2, const GLfloat * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6016)) { return; }
    if (!p_slot_1780) { sweet_missing(6016); return; }
    p_slot_1780(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1788: glUniformMatrix4x2fv */
static void (*p_slot_1788)(GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1788(void *opaque, GLint a0, GLsizei a1, GLboolean a2, const GLfloat * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6024)) { return; }
    if (!p_slot_1788) { sweet_missing(6024); return; }
    p_slot_1788(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1790: glUniformMatrix3x4fv */
static void (*p_slot_1790)(GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1790(void *opaque, GLint a0, GLsizei a1, GLboolean a2, const GLfloat * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6032)) { return; }
    if (!p_slot_1790) { sweet_missing(6032); return; }
    p_slot_1790(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1798: glUniformMatrix4x3fv */
static void (*p_slot_1798)(GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1798(void *opaque, GLint a0, GLsizei a1, GLboolean a2, const GLfloat * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6040)) { return; }
    if (!p_slot_1798) { sweet_missing(6040); return; }
    p_slot_1798(a0, a1, a2, a3);
}
/* E §4 / offmap 0x17a8: glRenderbufferStorageMultisample */
static void (*p_slot_17a8)(GLenum, GLsizei, GLenum, GLsizei, GLsizei);
static void slot_17a8(void *opaque, GLenum a0, GLsizei a1, GLenum a2, GLsizei a3, GLsizei a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6056)) { return; }
    if (!p_slot_17a8) { sweet_missing(6056); return; }
    p_slot_17a8(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x17c0: glGetAttachedShaders */
static void (*p_slot_17c0)(GLuint, GLsizei, GLsizei *, GLuint *);
static void slot_17c0(void *opaque, GLuint a0, GLsizei a1, GLsizei * a2, GLuint * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6080)) { return; }
    if (!p_slot_17c0) { sweet_missing(6080); return; }
    p_slot_17c0(a0, a1, a2, a3);
}
/* E §4 / offmap 0x17d0: glVertexAttribDivisor */
static void (*p_slot_17d0)(GLuint, GLuint);
static void slot_17d0(void *opaque, GLuint a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6096)) { return; }
    if (!p_slot_17d0) { sweet_missing(6096); return; }
    p_slot_17d0(a0, a1);
}
/* E §4 / offmap 0x17d8: glDrawArraysInstanced */
static void (*p_slot_17d8)(GLenum, GLint, GLsizei, GLsizei);
static void slot_17d8(void *opaque, GLenum a0, GLint a1, GLsizei a2, GLsizei a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6104)) { return; }
    if (!p_slot_17d8) { sweet_missing(6104); return; }
    sweet_before_draw(e);
    p_slot_17d8(a0, a1, a2, a3);
}
/* E §4 / offmap 0x17e0: glDrawElementsInstanced */
static void (*p_slot_17e0)(GLenum, GLsizei, GLenum, const void *, GLsizei);
static void slot_17e0(void *opaque, GLenum a0, GLsizei a1, GLenum a2, const void * a3, GLsizei a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6112)) { return; }
    if (!p_slot_17e0) { sweet_missing(6112); return; }
    sweet_before_draw(e);
    p_slot_17e0(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1808: glBindVertexArray */
static void (*p_slot_1808)(GLuint);
static void slot_1808(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6152)) { return; }
    if (!p_slot_1808) { sweet_missing(6152); return; }
    p_slot_1808(a0);
}
/* E §4 / offmap 0x1810: glDeleteVertexArrays */
static void (*p_slot_1810)(GLsizei, const GLuint *);
static void slot_1810(void *opaque, GLsizei a0, const GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6160)) { return; }
    if (!p_slot_1810) { sweet_missing(6160); return; }
    p_slot_1810(a0, a1);
}
/* E §4 / offmap 0x1818: glGenVertexArrays */
static void (*p_slot_1818)(GLsizei, GLuint *);
static void slot_1818(void *opaque, GLsizei a0, GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6168)) { return; }
    if (!p_slot_1818) { sweet_missing(6168); return; }
    p_slot_1818(a0, a1);
}
/* E §4 / offmap 0x1820: glIsVertexArray */
static GLboolean (*p_slot_1820)(GLuint);
static GLboolean slot_1820(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6176)) { return 0; }
    if (!p_slot_1820) { sweet_missing(6176); return 0; }
    return p_slot_1820(a0);
}
/* E §4 / offmap 0x1828: glPointSizePointerOES */
static void (*p_slot_1828)(GLenum, GLsizei, const void *);
static void slot_1828(void *opaque, GLenum a0, GLsizei a1, const void * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6184)) { return; }
    if (!p_slot_1828) { sweet_missing(6184); return; }
    p_slot_1828(a0, a1, a2);
}
/* E §4 / offmap 0x1838: glClearBufferiv */
static void (*p_slot_1838)(GLenum, GLint, const GLint *);
static void slot_1838(void *opaque, GLenum a0, GLint a1, const GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6200)) { return; }
    if (!p_slot_1838) { sweet_missing(6200); return; }
    sweet_before_draw(e);
    p_slot_1838(a0, a1, a2);
}
/* E §4 / offmap 0x1840: glClearBufferuiv */
static void (*p_slot_1840)(GLenum, GLint, const GLuint *);
static void slot_1840(void *opaque, GLenum a0, GLint a1, const GLuint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6208)) { return; }
    if (!p_slot_1840) { sweet_missing(6208); return; }
    sweet_before_draw(e);
    p_slot_1840(a0, a1, a2);
}
/* E §4 / offmap 0x1848: glClearBufferfv */
static void (*p_slot_1848)(GLenum, GLint, const GLfloat *);
static void slot_1848(void *opaque, GLenum a0, GLint a1, const GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6216)) { return; }
    if (!p_slot_1848) { sweet_missing(6216); return; }
    sweet_before_draw(e);
    p_slot_1848(a0, a1, a2);
}
/* E §4 / offmap 0x1850: glClearBufferfi */
static void (*p_slot_1850)(GLenum, GLint, GLfloat, GLint);
static void slot_1850(void *opaque, GLenum a0, GLint a1, GLfloat a2, GLint a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6224)) { return; }
    if (!p_slot_1850) { sweet_missing(6224); return; }
    sweet_before_draw(e);
    p_slot_1850(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1858: glGetStringi */
static const GLubyte * (*p_slot_1858)(GLenum, GLuint);
static const GLubyte * slot_1858(void *opaque, GLenum a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6232)) { return 0; }
    if (!p_slot_1858) { sweet_missing(6232); return 0; }
    return p_slot_1858(a0, a1);
}
/* E §4 / offmap 0x1860: glFenceSync */
static GLsync (*p_slot_1860)(GLenum, GLbitfield);
static GLsync slot_1860(void *opaque, GLenum a0, GLbitfield a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6240)) { return 0; }
    if (!p_slot_1860) { sweet_missing(6240); return 0; }
    return p_slot_1860(a0, a1);
    sweet_frame_mark(e, 6240);
}
/* E §4 / offmap 0x1868: glIsSync */
static GLboolean (*p_slot_1868)(GLsync);
static GLboolean slot_1868(void *opaque, GLsync a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6248)) { return 0; }
    if (!p_slot_1868) { sweet_missing(6248); return 0; }
    return p_slot_1868(a0);
}
/* E §4 / offmap 0x1870: glDeleteSync */
static void (*p_slot_1870)(GLsync);
static void slot_1870(void *opaque, GLsync a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6256)) { return; }
    if (!p_slot_1870) { sweet_missing(6256); return; }
    p_slot_1870(a0);
}
/* E §4 / offmap 0x1878: glClientWaitSync */
static GLenum (*p_slot_1878)(GLsync, GLbitfield, GLuint64);
static GLenum slot_1878(void *opaque, GLsync a0, GLbitfield a1, GLuint64 a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6264)) { return 0; }
    if (!p_slot_1878) { sweet_missing(6264); return 0; }
    return p_slot_1878(a0, a1, a2);
    sweet_frame_mark(e, 6264);
}
/* E §4 / offmap 0x1880: glWaitSync */
static void (*p_slot_1880)(GLsync, GLbitfield, GLuint64);
static void slot_1880(void *opaque, GLsync a0, GLbitfield a1, GLuint64 a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6272)) { return; }
    if (!p_slot_1880) { sweet_missing(6272); return; }
    p_slot_1880(a0, a1, a2);
}
/* E §4 / offmap 0x1888: glGetInteger64v */
static void (*p_slot_1888)(GLenum, GLint64 *);
static void slot_1888(void *opaque, GLenum a0, GLint64 * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6280)) { return; }
    if (!p_slot_1888) { sweet_missing(6280); return; }
    p_slot_1888(a0, a1);
}
/* E §4 / offmap 0x1890: glGetSynciv */
static void (*p_slot_1890)(GLsync, GLenum, GLsizei, GLsizei *, GLint *);
static void slot_1890(void *opaque, GLsync a0, GLenum a1, GLsizei a2, GLsizei * a3, GLint * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6288)) { return; }
    if (!p_slot_1890) { sweet_missing(6288); return; }
    p_slot_1890(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x18c0: glCopyBufferSubData */
static void (*p_slot_18c0)(GLenum, GLenum, GLintptr, GLintptr, GLsizeiptr);
static void slot_18c0(void *opaque, GLenum a0, GLenum a1, GLintptr a2, GLintptr a3, GLsizeiptr a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6336)) { return; }
    if (!p_slot_18c0) { sweet_missing(6336); return; }
    p_slot_18c0(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x18e0: glMapBufferRange */
static void * (*p_slot_18e0)(GLenum, GLintptr, GLsizeiptr, GLbitfield);
static void * slot_18e0(void *opaque, GLenum a0, GLintptr a1, GLsizeiptr a2, GLbitfield a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6368)) { return 0; }
    if (!p_slot_18e0) { sweet_missing(6368); return 0; }
    return p_slot_18e0(a0, a1, a2, a3);
}
/* E §4 / offmap 0x18e8: glFlushMappedBufferRange */
static void (*p_slot_18e8)(GLenum, GLintptr, GLsizeiptr);
static void slot_18e8(void *opaque, GLenum a0, GLintptr a1, GLsizeiptr a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6376)) { return; }
    if (!p_slot_18e8) { sweet_missing(6376); return; }
    p_slot_18e8(a0, a1, a2);
}
/* E §4 / offmap 0x18f8: glGetInteger64i_v */
static void (*p_slot_18f8)(GLenum, GLuint, GLint64 *);
static void slot_18f8(void *opaque, GLenum a0, GLuint a1, GLint64 * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6392)) { return; }
    if (!p_slot_18f8) { sweet_missing(6392); return; }
    p_slot_18f8(a0, a1, a2);
}
/* E §4 / offmap 0x1900: glGetBufferParameteri64v */
static void (*p_slot_1900)(GLenum, GLenum, GLint64 *);
static void slot_1900(void *opaque, GLenum a0, GLenum a1, GLint64 * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6400)) { return; }
    if (!p_slot_1900) { sweet_missing(6400); return; }
    p_slot_1900(a0, a1, a2);
}
/* E §4 / offmap 0x1908: glGenSamplers */
static void (*p_slot_1908)(GLsizei, GLuint *);
static void slot_1908(void *opaque, GLsizei a0, GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6408)) { return; }
    if (!p_slot_1908) { sweet_missing(6408); return; }
    p_slot_1908(a0, a1);
}
/* E §4 / offmap 0x1910: glDeleteSamplers */
static void (*p_slot_1910)(GLsizei, const GLuint *);
static void slot_1910(void *opaque, GLsizei a0, const GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6416)) { return; }
    if (!p_slot_1910) { sweet_missing(6416); return; }
    p_slot_1910(a0, a1);
}
/* E §4 / offmap 0x1918: glIsSampler */
static GLboolean (*p_slot_1918)(GLuint);
static GLboolean slot_1918(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6424)) { return 0; }
    if (!p_slot_1918) { sweet_missing(6424); return 0; }
    return p_slot_1918(a0);
}
/* E §4 / offmap 0x1920: glBindSampler */
static void (*p_slot_1920)(GLuint, GLuint);
static void slot_1920(void *opaque, GLuint a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6432)) { return; }
    if (!p_slot_1920) { sweet_missing(6432); return; }
    p_slot_1920(a0, a1);
}
/* E §4 / offmap 0x1928: glSamplerParameteri */
static void (*p_slot_1928)(GLuint, GLenum, GLint);
static void slot_1928(void *opaque, GLuint a0, GLenum a1, GLint a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6440)) { return; }
    if (!p_slot_1928) { sweet_missing(6440); return; }
    p_slot_1928(a0, a1, a2);
}
/* E §4 / offmap 0x1930: glSamplerParameteriv */
static void (*p_slot_1930)(GLuint, GLenum, const GLint *);
static void slot_1930(void *opaque, GLuint a0, GLenum a1, const GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6448)) { return; }
    if (!p_slot_1930) { sweet_missing(6448); return; }
    p_slot_1930(a0, a1, a2);
}
/* E §4 / offmap 0x1938: glSamplerParameterf */
static void (*p_slot_1938)(GLuint, GLenum, GLfloat);
static void slot_1938(void *opaque, GLuint a0, GLenum a1, GLfloat a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6456)) { return; }
    if (!p_slot_1938) { sweet_missing(6456); return; }
    p_slot_1938(a0, a1, a2);
}
/* E §4 / offmap 0x1940: glSamplerParameterfv */
static void (*p_slot_1940)(GLuint, GLenum, const GLfloat *);
static void slot_1940(void *opaque, GLuint a0, GLenum a1, const GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6464)) { return; }
    if (!p_slot_1940) { sweet_missing(6464); return; }
    p_slot_1940(a0, a1, a2);
}
/* E §4 / offmap 0x1958: glGetSamplerParameteriv */
static void (*p_slot_1958)(GLuint, GLenum, GLint *);
static void slot_1958(void *opaque, GLuint a0, GLenum a1, GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6488)) { return; }
    if (!p_slot_1958) { sweet_missing(6488); return; }
    p_slot_1958(a0, a1, a2);
}
/* E §4 / offmap 0x1960: glGetSamplerParameterfv */
static void (*p_slot_1960)(GLuint, GLenum, GLfloat *);
static void slot_1960(void *opaque, GLuint a0, GLenum a1, GLfloat * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6496)) { return; }
    if (!p_slot_1960) { sweet_missing(6496); return; }
    p_slot_1960(a0, a1, a2);
}
/* E §4 / offmap 0x1978: glLabelObjectEXT */
static void slot_1978(void *opaque, GLenum a0, GLuint a1, GLsizei a2, const GLchar * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6520)) { return; }
    (void)a0;
    (void)a1;
    (void)a2;
    (void)a3;
}
/* E §4 / offmap 0x1980: glGetObjectLabelEXT */
static void (*p_slot_1980)(GLenum, GLuint, GLsizei, GLsizei *, GLchar *);
static void slot_1980(void *opaque, GLenum a0, GLuint a1, GLsizei a2, GLsizei * a3, GLchar * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6528)) { return; }
    if (!p_slot_1980) { sweet_missing(6528); return; }
    p_slot_1980(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1988: glInsertEventMarkerEXT */
static void slot_1988(void *opaque, GLsizei a0, const GLchar * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6536)) { return; }
    (void)a0;
    (void)a1;
}
/* E §4 / offmap 0x1990: glPushGroupMarkerEXT */
static void slot_1990(void *opaque, GLsizei a0, const GLchar * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6544)) { return; }
    (void)a0;
    (void)a1;
}
/* E §4 / offmap 0x1998: glPopGroupMarkerEXT */
static void slot_1998(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6552)) { return; }
}
/* E §4 / offmap 0x19a0: glUseProgramStagesEXT */
static void (*p_slot_19a0)(GLuint, GLbitfield, GLuint);
static void slot_19a0(void *opaque, GLuint a0, GLbitfield a1, GLuint a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6560)) { return; }
    if (!p_slot_19a0) { sweet_missing(6560); return; }
    p_slot_19a0(a0, a1, a2);
}
/* E §4 / offmap 0x19a8: glActiveShaderProgramEXT */
static void (*p_slot_19a8)(GLuint, GLuint);
static void slot_19a8(void *opaque, GLuint a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6568)) { return; }
    if (!p_slot_19a8) { sweet_missing(6568); return; }
    p_slot_19a8(a0, a1);
}
/* E §4 / offmap 0x19b0: glCreateShaderProgramvEXT */
static GLuint (*p_slot_19b0)(GLenum, GLsizei, const GLchar *const*);
static GLuint slot_19b0(void *opaque, GLenum a0, GLsizei a1, const GLchar *const* a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6576)) { return 0; }
    if (!p_slot_19b0) { sweet_missing(6576); return 0; }
    return p_slot_19b0(a0, a1, a2);
}
/* E §4 / offmap 0x19b8: glBindProgramPipelineEXT */
static void (*p_slot_19b8)(GLuint);
static void slot_19b8(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6584)) { return; }
    if (!p_slot_19b8) { sweet_missing(6584); return; }
    p_slot_19b8(a0);
}
/* E §4 / offmap 0x19c0: glDeleteProgramPipelinesEXT */
static void (*p_slot_19c0)(GLsizei, const GLuint *);
static void slot_19c0(void *opaque, GLsizei a0, const GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6592)) { return; }
    if (!p_slot_19c0) { sweet_missing(6592); return; }
    p_slot_19c0(a0, a1);
}
/* E §4 / offmap 0x19c8: glGenProgramPipelinesEXT */
static void (*p_slot_19c8)(GLsizei, GLuint *);
static void slot_19c8(void *opaque, GLsizei a0, GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6600)) { return; }
    if (!p_slot_19c8) { sweet_missing(6600); return; }
    p_slot_19c8(a0, a1);
}
/* E §4 / offmap 0x19d0: glIsProgramPipelineEXT */
static GLboolean (*p_slot_19d0)(GLuint);
static GLboolean slot_19d0(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6608)) { return 0; }
    if (!p_slot_19d0) { sweet_missing(6608); return 0; }
    return p_slot_19d0(a0);
}
/* E §4 / offmap 0x19d8: glGetProgramPipelineivEXT */
static void (*p_slot_19d8)(GLuint, GLenum, GLint *);
static void slot_19d8(void *opaque, GLuint a0, GLenum a1, GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6616)) { return; }
    if (!p_slot_19d8) { sweet_missing(6616); return; }
    p_slot_19d8(a0, a1, a2);
}
/* E §4 / offmap 0x19e0: glValidateProgramPipelineEXT */
static void (*p_slot_19e0)(GLuint);
static void slot_19e0(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6624)) { return; }
    if (!p_slot_19e0) { sweet_missing(6624); return; }
    p_slot_19e0(a0);
}
/* E §4 / offmap 0x19e8: glGetProgramPipelineInfoLogEXT */
static void (*p_slot_19e8)(GLuint, GLsizei, GLsizei *, GLchar *);
static void slot_19e8(void *opaque, GLuint a0, GLsizei a1, GLsizei * a2, GLchar * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6632)) { return; }
    if (!p_slot_19e8) { sweet_missing(6632); return; }
    p_slot_19e8(a0, a1, a2, a3);
}
/* E §4 / offmap 0x19f0: glProgramUniform1iEXT */
static void (*p_slot_19f0)(GLuint, GLint, GLint);
static void slot_19f0(void *opaque, GLuint a0, GLint a1, GLint a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6640)) { return; }
    if (!p_slot_19f0) { sweet_missing(6640); return; }
    p_slot_19f0(a0, a1, a2);
}
/* E §4 / offmap 0x19f8: glProgramUniform2iEXT */
static void (*p_slot_19f8)(GLuint, GLint, GLint, GLint);
static void slot_19f8(void *opaque, GLuint a0, GLint a1, GLint a2, GLint a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6648)) { return; }
    if (!p_slot_19f8) { sweet_missing(6648); return; }
    p_slot_19f8(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1a00: glProgramUniform3iEXT */
static void (*p_slot_1a00)(GLuint, GLint, GLint, GLint, GLint);
static void slot_1a00(void *opaque, GLuint a0, GLint a1, GLint a2, GLint a3, GLint a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6656)) { return; }
    if (!p_slot_1a00) { sweet_missing(6656); return; }
    p_slot_1a00(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1a08: glProgramUniform4iEXT */
static void (*p_slot_1a08)(GLuint, GLint, GLint, GLint, GLint, GLint);
static void slot_1a08(void *opaque, GLuint a0, GLint a1, GLint a2, GLint a3, GLint a4, GLint a5) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6664)) { return; }
    if (!p_slot_1a08) { sweet_missing(6664); return; }
    p_slot_1a08(a0, a1, a2, a3, a4, a5);
}
/* E §4 / offmap 0x1a10: glProgramUniform1fEXT */
static void (*p_slot_1a10)(GLuint, GLint, GLfloat);
static void slot_1a10(void *opaque, GLuint a0, GLint a1, GLfloat a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6672)) { return; }
    if (!p_slot_1a10) { sweet_missing(6672); return; }
    p_slot_1a10(a0, a1, a2);
}
/* E §4 / offmap 0x1a18: glProgramUniform2fEXT */
static void (*p_slot_1a18)(GLuint, GLint, GLfloat, GLfloat);
static void slot_1a18(void *opaque, GLuint a0, GLint a1, GLfloat a2, GLfloat a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6680)) { return; }
    if (!p_slot_1a18) { sweet_missing(6680); return; }
    p_slot_1a18(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1a20: glProgramUniform3fEXT */
static void (*p_slot_1a20)(GLuint, GLint, GLfloat, GLfloat, GLfloat);
static void slot_1a20(void *opaque, GLuint a0, GLint a1, GLfloat a2, GLfloat a3, GLfloat a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6688)) { return; }
    if (!p_slot_1a20) { sweet_missing(6688); return; }
    p_slot_1a20(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1a28: glProgramUniform4fEXT */
static void (*p_slot_1a28)(GLuint, GLint, GLfloat, GLfloat, GLfloat, GLfloat);
static void slot_1a28(void *opaque, GLuint a0, GLint a1, GLfloat a2, GLfloat a3, GLfloat a4, GLfloat a5) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6696)) { return; }
    if (!p_slot_1a28) { sweet_missing(6696); return; }
    p_slot_1a28(a0, a1, a2, a3, a4, a5);
}
/* E §4 / offmap 0x1a30: glProgramUniform1ivEXT */
static void (*p_slot_1a30)(GLuint, GLint, GLsizei, const GLint *);
static void slot_1a30(void *opaque, GLuint a0, GLint a1, GLsizei a2, const GLint * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6704)) { return; }
    if (!p_slot_1a30) { sweet_missing(6704); return; }
    p_slot_1a30(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1a38: glProgramUniform2ivEXT */
static void (*p_slot_1a38)(GLuint, GLint, GLsizei, const GLint *);
static void slot_1a38(void *opaque, GLuint a0, GLint a1, GLsizei a2, const GLint * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6712)) { return; }
    if (!p_slot_1a38) { sweet_missing(6712); return; }
    p_slot_1a38(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1a40: glProgramUniform3ivEXT */
static void (*p_slot_1a40)(GLuint, GLint, GLsizei, const GLint *);
static void slot_1a40(void *opaque, GLuint a0, GLint a1, GLsizei a2, const GLint * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6720)) { return; }
    if (!p_slot_1a40) { sweet_missing(6720); return; }
    p_slot_1a40(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1a48: glProgramUniform4ivEXT */
static void (*p_slot_1a48)(GLuint, GLint, GLsizei, const GLint *);
static void slot_1a48(void *opaque, GLuint a0, GLint a1, GLsizei a2, const GLint * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6728)) { return; }
    if (!p_slot_1a48) { sweet_missing(6728); return; }
    p_slot_1a48(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1a50: glProgramUniform1fvEXT */
static void (*p_slot_1a50)(GLuint, GLint, GLsizei, const GLfloat *);
static void slot_1a50(void *opaque, GLuint a0, GLint a1, GLsizei a2, const GLfloat * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6736)) { return; }
    if (!p_slot_1a50) { sweet_missing(6736); return; }
    p_slot_1a50(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1a58: glProgramUniform2fvEXT */
static void (*p_slot_1a58)(GLuint, GLint, GLsizei, const GLfloat *);
static void slot_1a58(void *opaque, GLuint a0, GLint a1, GLsizei a2, const GLfloat * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6744)) { return; }
    if (!p_slot_1a58) { sweet_missing(6744); return; }
    p_slot_1a58(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1a60: glProgramUniform3fvEXT */
static void (*p_slot_1a60)(GLuint, GLint, GLsizei, const GLfloat *);
static void slot_1a60(void *opaque, GLuint a0, GLint a1, GLsizei a2, const GLfloat * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6752)) { return; }
    if (!p_slot_1a60) { sweet_missing(6752); return; }
    p_slot_1a60(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1a68: glProgramUniform4fvEXT */
static void (*p_slot_1a68)(GLuint, GLint, GLsizei, const GLfloat *);
static void slot_1a68(void *opaque, GLuint a0, GLint a1, GLsizei a2, const GLfloat * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6760)) { return; }
    if (!p_slot_1a68) { sweet_missing(6760); return; }
    p_slot_1a68(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1a70: glProgramUniformMatrix2fvEXT */
static void (*p_slot_1a70)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1a70(void *opaque, GLuint a0, GLint a1, GLsizei a2, GLboolean a3, const GLfloat * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6768)) { return; }
    if (!p_slot_1a70) { sweet_missing(6768); return; }
    p_slot_1a70(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1a78: glProgramUniformMatrix3fvEXT */
static void (*p_slot_1a78)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1a78(void *opaque, GLuint a0, GLint a1, GLsizei a2, GLboolean a3, const GLfloat * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6776)) { return; }
    if (!p_slot_1a78) { sweet_missing(6776); return; }
    p_slot_1a78(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1a80: glProgramUniformMatrix4fvEXT */
static void (*p_slot_1a80)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1a80(void *opaque, GLuint a0, GLint a1, GLsizei a2, GLboolean a3, const GLfloat * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6784)) { return; }
    if (!p_slot_1a80) { sweet_missing(6784); return; }
    p_slot_1a80(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1a88: glProgramUniform1uiEXT */
static void (*p_slot_1a88)(GLuint, GLint, GLuint);
static void slot_1a88(void *opaque, GLuint a0, GLint a1, GLuint a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6792)) { return; }
    if (!p_slot_1a88) { sweet_missing(6792); return; }
    p_slot_1a88(a0, a1, a2);
}
/* E §4 / offmap 0x1a90: glProgramUniform2uiEXT */
static void (*p_slot_1a90)(GLuint, GLint, GLuint, GLuint);
static void slot_1a90(void *opaque, GLuint a0, GLint a1, GLuint a2, GLuint a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6800)) { return; }
    if (!p_slot_1a90) { sweet_missing(6800); return; }
    p_slot_1a90(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1a98: glProgramUniform3uiEXT */
static void (*p_slot_1a98)(GLuint, GLint, GLuint, GLuint, GLuint);
static void slot_1a98(void *opaque, GLuint a0, GLint a1, GLuint a2, GLuint a3, GLuint a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6808)) { return; }
    if (!p_slot_1a98) { sweet_missing(6808); return; }
    p_slot_1a98(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1aa0: glProgramUniform4uiEXT */
static void (*p_slot_1aa0)(GLuint, GLint, GLuint, GLuint, GLuint, GLuint);
static void slot_1aa0(void *opaque, GLuint a0, GLint a1, GLuint a2, GLuint a3, GLuint a4, GLuint a5) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6816)) { return; }
    if (!p_slot_1aa0) { sweet_missing(6816); return; }
    p_slot_1aa0(a0, a1, a2, a3, a4, a5);
}
/* E §4 / offmap 0x1aa8: glProgramUniform1uivEXT */
static void (*p_slot_1aa8)(GLuint, GLint, GLsizei, const GLuint *);
static void slot_1aa8(void *opaque, GLuint a0, GLint a1, GLsizei a2, const GLuint * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6824)) { return; }
    if (!p_slot_1aa8) { sweet_missing(6824); return; }
    p_slot_1aa8(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1ab0: glProgramUniform2uivEXT */
static void (*p_slot_1ab0)(GLuint, GLint, GLsizei, const GLuint *);
static void slot_1ab0(void *opaque, GLuint a0, GLint a1, GLsizei a2, const GLuint * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6832)) { return; }
    if (!p_slot_1ab0) { sweet_missing(6832); return; }
    p_slot_1ab0(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1ab8: glProgramUniform3uivEXT */
static void (*p_slot_1ab8)(GLuint, GLint, GLsizei, const GLuint *);
static void slot_1ab8(void *opaque, GLuint a0, GLint a1, GLsizei a2, const GLuint * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6840)) { return; }
    if (!p_slot_1ab8) { sweet_missing(6840); return; }
    p_slot_1ab8(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1ac0: glProgramUniform4uivEXT */
static void (*p_slot_1ac0)(GLuint, GLint, GLsizei, const GLuint *);
static void slot_1ac0(void *opaque, GLuint a0, GLint a1, GLsizei a2, const GLuint * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6848)) { return; }
    if (!p_slot_1ac0) { sweet_missing(6848); return; }
    p_slot_1ac0(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1ac8: glProgramUniformMatrix2x3fvEXT */
static void (*p_slot_1ac8)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1ac8(void *opaque, GLuint a0, GLint a1, GLsizei a2, GLboolean a3, const GLfloat * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6856)) { return; }
    if (!p_slot_1ac8) { sweet_missing(6856); return; }
    p_slot_1ac8(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1ad0: glProgramUniformMatrix3x2fvEXT */
static void (*p_slot_1ad0)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1ad0(void *opaque, GLuint a0, GLint a1, GLsizei a2, GLboolean a3, const GLfloat * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6864)) { return; }
    if (!p_slot_1ad0) { sweet_missing(6864); return; }
    p_slot_1ad0(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1ad8: glProgramUniformMatrix2x4fvEXT */
static void (*p_slot_1ad8)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1ad8(void *opaque, GLuint a0, GLint a1, GLsizei a2, GLboolean a3, const GLfloat * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6872)) { return; }
    if (!p_slot_1ad8) { sweet_missing(6872); return; }
    p_slot_1ad8(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1ae0: glProgramUniformMatrix4x2fvEXT */
static void (*p_slot_1ae0)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1ae0(void *opaque, GLuint a0, GLint a1, GLsizei a2, GLboolean a3, const GLfloat * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6880)) { return; }
    if (!p_slot_1ae0) { sweet_missing(6880); return; }
    p_slot_1ae0(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1ae8: glProgramUniformMatrix3x4fvEXT */
static void (*p_slot_1ae8)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1ae8(void *opaque, GLuint a0, GLint a1, GLsizei a2, GLboolean a3, const GLfloat * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6888)) { return; }
    if (!p_slot_1ae8) { sweet_missing(6888); return; }
    p_slot_1ae8(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1af0: glProgramUniformMatrix4x3fvEXT */
static void (*p_slot_1af0)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *);
static void slot_1af0(void *opaque, GLuint a0, GLint a1, GLsizei a2, GLboolean a3, const GLfloat * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 6896)) { return; }
    if (!p_slot_1af0) { sweet_missing(6896); return; }
    p_slot_1af0(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1b58: glReleaseShaderCompiler */
static void (*p_slot_1b58)(void);
static void slot_1b58(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7000)) { return; }
    if (!p_slot_1b58) { sweet_missing(7000); return; }
    p_slot_1b58();
}
/* E §4 / offmap 0x1b60: glShaderBinary */
static void (*p_slot_1b60)(GLsizei, const GLuint *, GLenum, const void *, GLsizei);
static void slot_1b60(void *opaque, GLsizei a0, const GLuint * a1, GLenum a2, const void * a3, GLsizei a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7008)) { return; }
    if (!p_slot_1b60) { sweet_missing(7008); return; }
    p_slot_1b60(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1b68: glGetShaderPrecisionFormat */
static void (*p_slot_1b68)(GLenum, GLenum, GLint *, GLint *);
static void slot_1b68(void *opaque, GLenum a0, GLenum a1, GLint * a2, GLint * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7016)) { return; }
    if (!p_slot_1b68) { sweet_missing(7016); return; }
    p_slot_1b68(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1b70: glDepthRangef */
static void (*p_slot_1b70)(GLfloat, GLfloat);
static void slot_1b70(void *opaque, GLfloat a0, GLfloat a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7024)) { return; }
    if (!p_slot_1b70) { sweet_missing(7024); return; }
    p_slot_1b70(a0, a1);
}
/* E §4 / offmap 0x1b78: glClearDepthf */
static void (*p_slot_1b78)(GLfloat);
static void slot_1b78(void *opaque, GLfloat a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7032)) { return; }
    if (!p_slot_1b78) { sweet_missing(7032); return; }
    p_slot_1b78(a0);
}
/* E §4 / offmap 0x1bc0: glGetProgramBinary */
static void (*p_slot_1bc0)(GLuint, GLsizei, GLsizei *, GLenum *, void *);
static void slot_1bc0(void *opaque, GLuint a0, GLsizei a1, GLsizei * a2, GLenum * a3, void * a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7104)) { return; }
    if (!p_slot_1bc0) { sweet_missing(7104); return; }
    p_slot_1bc0(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1bc8: glProgramBinary */
static void (*p_slot_1bc8)(GLuint, GLenum, const void *, GLsizei);
static void slot_1bc8(void *opaque, GLuint a0, GLenum a1, const void * a2, GLsizei a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7112)) { return; }
    if (!p_slot_1bc8) { sweet_missing(7112); return; }
    p_slot_1bc8(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1c48: glBindTransformFeedback */
static void (*p_slot_1c48)(GLenum, GLuint);
static void slot_1c48(void *opaque, GLenum a0, GLuint a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7240)) { return; }
    if (!p_slot_1c48) { sweet_missing(7240); return; }
    p_slot_1c48(a0, a1);
}
/* E §4 / offmap 0x1c50: glGenTransformFeedbacks */
static void (*p_slot_1c50)(GLsizei, GLuint *);
static void slot_1c50(void *opaque, GLsizei a0, GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7248)) { return; }
    if (!p_slot_1c50) { sweet_missing(7248); return; }
    p_slot_1c50(a0, a1);
}
/* E §4 / offmap 0x1c58: glDeleteTransformFeedbacks */
static void (*p_slot_1c58)(GLsizei, const GLuint *);
static void slot_1c58(void *opaque, GLsizei a0, const GLuint * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7256)) { return; }
    if (!p_slot_1c58) { sweet_missing(7256); return; }
    p_slot_1c58(a0, a1);
}
/* E §4 / offmap 0x1c60: glPauseTransformFeedback */
static void (*p_slot_1c60)(void);
static void slot_1c60(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7264)) { return; }
    if (!p_slot_1c60) { sweet_missing(7264); return; }
    p_slot_1c60();
}
/* E §4 / offmap 0x1c68: glResumeTransformFeedback */
static void (*p_slot_1c68)(void);
static void slot_1c68(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7272)) { return; }
    if (!p_slot_1c68) { sweet_missing(7272); return; }
    p_slot_1c68();
}
/* E §4 / offmap 0x1c70: glIsTransformFeedback */
static GLboolean (*p_slot_1c70)(GLuint);
static GLboolean slot_1c70(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7280)) { return 0; }
    if (!p_slot_1c70) { sweet_missing(7280); return 0; }
    return p_slot_1c70(a0);
}
/* E §4 / offmap 0x1e48: glAlphaFuncx */
static void (*p_slot_1e48)(GLenum, GLfixed);
static void slot_1e48(void *opaque, GLenum a0, GLfixed a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7752)) { return; }
    if (!p_slot_1e48) { sweet_missing(7752); return; }
    p_slot_1e48(a0, a1);
}
/* E §4 / offmap 0x1e50: glClearColorx */
static void (*p_slot_1e50)(GLfixed, GLfixed, GLfixed, GLfixed);
static void slot_1e50(void *opaque, GLfixed a0, GLfixed a1, GLfixed a2, GLfixed a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7760)) { return; }
    if (!p_slot_1e50) { sweet_missing(7760); return; }
    p_slot_1e50(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1e58: glClearDepthx */
static void (*p_slot_1e58)(GLfixed);
static void slot_1e58(void *opaque, GLfixed a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7768)) { return; }
    if (!p_slot_1e58) { sweet_missing(7768); return; }
    p_slot_1e58(a0);
}
/* E §4 / offmap 0x1e60: glClipPlanef */
static void (*p_slot_1e60)(GLenum, const GLfloat *);
static void slot_1e60(void *opaque, GLenum a0, const GLfloat * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7776)) { return; }
    if (!p_slot_1e60) { sweet_missing(7776); return; }
    p_slot_1e60(a0, a1);
}
/* E §4 / offmap 0x1e68: glClipPlanex */
static void (*p_slot_1e68)(GLenum, const GLfixed *);
static void slot_1e68(void *opaque, GLenum a0, const GLfixed * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7784)) { return; }
    if (!p_slot_1e68) { sweet_missing(7784); return; }
    p_slot_1e68(a0, a1);
}
/* E §4 / offmap 0x1e70: glColor4x */
static void (*p_slot_1e70)(GLfixed, GLfixed, GLfixed, GLfixed);
static void slot_1e70(void *opaque, GLfixed a0, GLfixed a1, GLfixed a2, GLfixed a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7792)) { return; }
    if (!p_slot_1e70) { sweet_missing(7792); return; }
    p_slot_1e70(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1e78: glDepthRangex */
static void (*p_slot_1e78)(GLfixed, GLfixed);
static void slot_1e78(void *opaque, GLfixed a0, GLfixed a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7800)) { return; }
    if (!p_slot_1e78) { sweet_missing(7800); return; }
    p_slot_1e78(a0, a1);
}
/* E §4 / offmap 0x1e80: glFogx */
static void (*p_slot_1e80)(GLenum, GLfixed);
static void slot_1e80(void *opaque, GLenum a0, GLfixed a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7808)) { return; }
    if (!p_slot_1e80) { sweet_missing(7808); return; }
    p_slot_1e80(a0, a1);
}
/* E §4 / offmap 0x1e88: glFogxv */
static void (*p_slot_1e88)(GLenum, const GLfixed *);
static void slot_1e88(void *opaque, GLenum a0, const GLfixed * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7816)) { return; }
    if (!p_slot_1e88) { sweet_missing(7816); return; }
    p_slot_1e88(a0, a1);
}
/* E §4 / offmap 0x1e90: glFrustumf */
static void (*p_slot_1e90)(GLfloat, GLfloat, GLfloat, GLfloat, GLfloat, GLfloat);
static void slot_1e90(void *opaque, GLfloat a0, GLfloat a1, GLfloat a2, GLfloat a3, GLfloat a4, GLfloat a5) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7824)) { return; }
    if (!p_slot_1e90) { sweet_missing(7824); return; }
    p_slot_1e90(a0, a1, a2, a3, a4, a5);
}
/* E §4 / offmap 0x1e98: glFrustumx */
static void (*p_slot_1e98)(GLfixed, GLfixed, GLfixed, GLfixed, GLfixed, GLfixed);
static void slot_1e98(void *opaque, GLfixed a0, GLfixed a1, GLfixed a2, GLfixed a3, GLfixed a4, GLfixed a5) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7832)) { return; }
    if (!p_slot_1e98) { sweet_missing(7832); return; }
    p_slot_1e98(a0, a1, a2, a3, a4, a5);
}
/* E §4 / offmap 0x1ea0: glGetClipPlanef */
static void (*p_slot_1ea0)(GLenum, GLfloat *);
static void slot_1ea0(void *opaque, GLenum a0, GLfloat * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7840)) { return; }
    if (!p_slot_1ea0) { sweet_missing(7840); return; }
    p_slot_1ea0(a0, a1);
}
/* E §4 / offmap 0x1ea8: glGetClipPlanex */
static void (*p_slot_1ea8)(GLenum, GLfixed *);
static void slot_1ea8(void *opaque, GLenum a0, GLfixed * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7848)) { return; }
    if (!p_slot_1ea8) { sweet_missing(7848); return; }
    p_slot_1ea8(a0, a1);
}
/* E §4 / offmap 0x1eb0: glGetFixedv */
static void (*p_slot_1eb0)(GLenum, GLfixed *);
static void slot_1eb0(void *opaque, GLenum a0, GLfixed * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7856)) { return; }
    if (!p_slot_1eb0) { sweet_missing(7856); return; }
    p_slot_1eb0(a0, a1);
}
/* E §4 / offmap 0x1eb8: glGetLightxv */
static void (*p_slot_1eb8)(GLenum, GLenum, GLfixed *);
static void slot_1eb8(void *opaque, GLenum a0, GLenum a1, GLfixed * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7864)) { return; }
    if (!p_slot_1eb8) { sweet_missing(7864); return; }
    p_slot_1eb8(a0, a1, a2);
}
/* E §4 / offmap 0x1ec0: glGetMaterialxv */
static void (*p_slot_1ec0)(GLenum, GLenum, GLfixed *);
static void slot_1ec0(void *opaque, GLenum a0, GLenum a1, GLfixed * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7872)) { return; }
    if (!p_slot_1ec0) { sweet_missing(7872); return; }
    p_slot_1ec0(a0, a1, a2);
}
/* E §4 / offmap 0x1ec8: glGetTexEnvxv */
static void (*p_slot_1ec8)(GLenum, GLenum, GLfixed *);
static void slot_1ec8(void *opaque, GLenum a0, GLenum a1, GLfixed * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7880)) { return; }
    if (!p_slot_1ec8) { sweet_missing(7880); return; }
    p_slot_1ec8(a0, a1, a2);
}
/* E §4 / offmap 0x1ed0: glGetTexParameterxv */
static void (*p_slot_1ed0)(GLenum, GLenum, GLfixed *);
static void slot_1ed0(void *opaque, GLenum a0, GLenum a1, GLfixed * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7888)) { return; }
    if (!p_slot_1ed0) { sweet_missing(7888); return; }
    p_slot_1ed0(a0, a1, a2);
}
/* E §4 / offmap 0x1ed8: glLightModelx */
static void (*p_slot_1ed8)(GLenum, GLfixed);
static void slot_1ed8(void *opaque, GLenum a0, GLfixed a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7896)) { return; }
    if (!p_slot_1ed8) { sweet_missing(7896); return; }
    p_slot_1ed8(a0, a1);
}
/* E §4 / offmap 0x1ee0: glLightModelxv */
static void (*p_slot_1ee0)(GLenum, const GLfixed *);
static void slot_1ee0(void *opaque, GLenum a0, const GLfixed * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7904)) { return; }
    if (!p_slot_1ee0) { sweet_missing(7904); return; }
    p_slot_1ee0(a0, a1);
}
/* E §4 / offmap 0x1ee8: glLightx */
static void (*p_slot_1ee8)(GLenum, GLenum, GLfixed);
static void slot_1ee8(void *opaque, GLenum a0, GLenum a1, GLfixed a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7912)) { return; }
    if (!p_slot_1ee8) { sweet_missing(7912); return; }
    p_slot_1ee8(a0, a1, a2);
}
/* E §4 / offmap 0x1ef0: glLightxv */
static void (*p_slot_1ef0)(GLenum, GLenum, const GLfixed *);
static void slot_1ef0(void *opaque, GLenum a0, GLenum a1, const GLfixed * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7920)) { return; }
    if (!p_slot_1ef0) { sweet_missing(7920); return; }
    p_slot_1ef0(a0, a1, a2);
}
/* E §4 / offmap 0x1ef8: glLineWidthx */
static void (*p_slot_1ef8)(GLfixed);
static void slot_1ef8(void *opaque, GLfixed a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7928)) { return; }
    if (!p_slot_1ef8) { sweet_missing(7928); return; }
    p_slot_1ef8(a0);
}
/* E §4 / offmap 0x1f00: glLoadMatrixx */
static void (*p_slot_1f00)(const GLfixed *);
static void slot_1f00(void *opaque, const GLfixed * a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7936)) { return; }
    if (!p_slot_1f00) { sweet_missing(7936); return; }
    p_slot_1f00(a0);
}
/* E §4 / offmap 0x1f08: glMaterialx */
static void (*p_slot_1f08)(GLenum, GLenum, GLfixed);
static void slot_1f08(void *opaque, GLenum a0, GLenum a1, GLfixed a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7944)) { return; }
    if (!p_slot_1f08) { sweet_missing(7944); return; }
    p_slot_1f08(a0, a1, a2);
}
/* E §4 / offmap 0x1f10: glMaterialxv */
static void (*p_slot_1f10)(GLenum, GLenum, const GLfixed *);
static void slot_1f10(void *opaque, GLenum a0, GLenum a1, const GLfixed * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7952)) { return; }
    if (!p_slot_1f10) { sweet_missing(7952); return; }
    p_slot_1f10(a0, a1, a2);
}
/* E §4 / offmap 0x1f18: glMultMatrixx */
static void (*p_slot_1f18)(const GLfixed *);
static void slot_1f18(void *opaque, const GLfixed * a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7960)) { return; }
    if (!p_slot_1f18) { sweet_missing(7960); return; }
    p_slot_1f18(a0);
}
/* E §4 / offmap 0x1f20: glNormal3x */
static void (*p_slot_1f20)(GLfixed, GLfixed, GLfixed);
static void slot_1f20(void *opaque, GLfixed a0, GLfixed a1, GLfixed a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7968)) { return; }
    if (!p_slot_1f20) { sweet_missing(7968); return; }
    p_slot_1f20(a0, a1, a2);
}
/* E §4 / offmap 0x1f28: glOrthof */
static void (*p_slot_1f28)(GLfloat, GLfloat, GLfloat, GLfloat, GLfloat, GLfloat);
static void slot_1f28(void *opaque, GLfloat a0, GLfloat a1, GLfloat a2, GLfloat a3, GLfloat a4, GLfloat a5) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7976)) { return; }
    if (!p_slot_1f28) { sweet_missing(7976); return; }
    p_slot_1f28(a0, a1, a2, a3, a4, a5);
}
/* E §4 / offmap 0x1f30: glOrthox */
static void (*p_slot_1f30)(GLfixed, GLfixed, GLfixed, GLfixed, GLfixed, GLfixed);
static void slot_1f30(void *opaque, GLfixed a0, GLfixed a1, GLfixed a2, GLfixed a3, GLfixed a4, GLfixed a5) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7984)) { return; }
    if (!p_slot_1f30) { sweet_missing(7984); return; }
    p_slot_1f30(a0, a1, a2, a3, a4, a5);
}
/* E §4 / offmap 0x1f38: glPointSizex */
static void (*p_slot_1f38)(GLfixed);
static void slot_1f38(void *opaque, GLfixed a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 7992)) { return; }
    if (!p_slot_1f38) { sweet_missing(7992); return; }
    p_slot_1f38(a0);
}
/* E §4 / offmap 0x1f40: glPolygonOffsetx */
static void (*p_slot_1f40)(GLfixed, GLfixed);
static void slot_1f40(void *opaque, GLfixed a0, GLfixed a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8000)) { return; }
    if (!p_slot_1f40) { sweet_missing(8000); return; }
    p_slot_1f40(a0, a1);
}
/* E §4 / offmap 0x1f48: glRotatex */
static void (*p_slot_1f48)(GLfixed, GLfixed, GLfixed, GLfixed);
static void slot_1f48(void *opaque, GLfixed a0, GLfixed a1, GLfixed a2, GLfixed a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8008)) { return; }
    if (!p_slot_1f48) { sweet_missing(8008); return; }
    p_slot_1f48(a0, a1, a2, a3);
}
/* E §4 / offmap 0x1f50: glScalex */
static void (*p_slot_1f50)(GLfixed, GLfixed, GLfixed);
static void slot_1f50(void *opaque, GLfixed a0, GLfixed a1, GLfixed a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8016)) { return; }
    if (!p_slot_1f50) { sweet_missing(8016); return; }
    p_slot_1f50(a0, a1, a2);
}
/* E §4 / offmap 0x1f58: glTexEnvx */
static void (*p_slot_1f58)(GLenum, GLenum, GLfixed);
static void slot_1f58(void *opaque, GLenum a0, GLenum a1, GLfixed a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8024)) { return; }
    if (!p_slot_1f58) { sweet_missing(8024); return; }
    p_slot_1f58(a0, a1, a2);
}
/* E §4 / offmap 0x1f60: glTexEnvxv */
static void (*p_slot_1f60)(GLenum, GLenum, const GLfixed *);
static void slot_1f60(void *opaque, GLenum a0, GLenum a1, const GLfixed * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8032)) { return; }
    if (!p_slot_1f60) { sweet_missing(8032); return; }
    p_slot_1f60(a0, a1, a2);
}
/* E §4 / offmap 0x1f68: glTexParameterx */
static void (*p_slot_1f68)(GLenum, GLenum, GLfixed);
static void slot_1f68(void *opaque, GLenum a0, GLenum a1, GLfixed a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8040)) { return; }
    if (!p_slot_1f68) { sweet_missing(8040); return; }
    p_slot_1f68(a0, a1, a2);
}
/* E §4 / offmap 0x1f70: glTexParameterxv */
static void (*p_slot_1f70)(GLenum, GLenum, const GLfixed *);
static void slot_1f70(void *opaque, GLenum a0, GLenum a1, const GLfixed * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8048)) { return; }
    if (!p_slot_1f70) { sweet_missing(8048); return; }
    p_slot_1f70(a0, a1, a2);
}
/* E §4 / offmap 0x1f78: glTranslatex */
static void (*p_slot_1f78)(GLfixed, GLfixed, GLfixed);
static void slot_1f78(void *opaque, GLfixed a0, GLfixed a1, GLfixed a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8056)) { return; }
    if (!p_slot_1f78) { sweet_missing(8056); return; }
    p_slot_1f78(a0, a1, a2);
}
/* E §4 / offmap 0x1f80: glMultiTexCoord4x */
static void (*p_slot_1f80)(GLenum, GLfixed, GLfixed, GLfixed, GLfixed);
static void slot_1f80(void *opaque, GLenum a0, GLfixed a1, GLfixed a2, GLfixed a3, GLfixed a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8064)) { return; }
    if (!p_slot_1f80) { sweet_missing(8064); return; }
    p_slot_1f80(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1f88: glSampleCoveragex */
static void (*p_slot_1f88)(GLclampx, GLboolean);
static void slot_1f88(void *opaque, GLclampx a0, GLboolean a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8072)) { return; }
    if (!p_slot_1f88) { sweet_missing(8072); return; }
    p_slot_1f88(a0, a1);
}
/* E §4 / offmap 0x1f90: glPointParameterx */
static void (*p_slot_1f90)(GLenum, GLfixed);
static void slot_1f90(void *opaque, GLenum a0, GLfixed a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8080)) { return; }
    if (!p_slot_1f90) { sweet_missing(8080); return; }
    p_slot_1f90(a0, a1);
}
/* E §4 / offmap 0x1f98: glPointParameterxv */
static void (*p_slot_1f98)(GLenum, const GLfixed *);
static void slot_1f98(void *opaque, GLenum a0, const GLfixed * a1) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8088)) { return; }
    if (!p_slot_1f98) { sweet_missing(8088); return; }
    p_slot_1f98(a0, a1);
}
/* E §4 / offmap 0x1fa0: glCurrentPaletteMatrixOES */
static void slot_1fa0(void *opaque, GLuint a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8096)) { return; }
    (void)a0;
    sweet_missing(8096); return;
}
/* E §4 / offmap 0x1fa8: glLoadPaletteFromModelViewMatrixOES */
static void slot_1fa8(void *opaque) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8104)) { return; }
    sweet_missing(8104); return;
}
/* E §4 / offmap 0x1fb0: glMatrixIndexPointerOES */
static void slot_1fb0(void *opaque, GLint a0, GLenum a1, GLsizei a2, const void * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8112)) { return; }
    (void)a0;
    (void)a1;
    (void)a2;
    (void)a3;
    sweet_missing(8112); return;
}
/* E §4 / offmap 0x1fb8: glWeightPointerOES */
static void slot_1fb8(void *opaque, GLint a0, GLenum a1, GLsizei a2, const void * a3) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8120)) { return; }
    (void)a0;
    (void)a1;
    (void)a2;
    (void)a3;
    sweet_missing(8120); return;
}
/* E §4 / offmap 0x1fc0: glDrawTexsOES */
static void (*p_slot_1fc0)(GLshort, GLshort, GLshort, GLshort, GLshort);
static void slot_1fc0(void *opaque, GLshort a0, GLshort a1, GLshort a2, GLshort a3, GLshort a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8128)) { return; }
    if (!p_slot_1fc0) { sweet_missing(8128); return; }
    sweet_before_draw(e);
    p_slot_1fc0(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1fc8: glDrawTexiOES */
static void (*p_slot_1fc8)(GLint, GLint, GLint, GLint, GLint);
static void slot_1fc8(void *opaque, GLint a0, GLint a1, GLint a2, GLint a3, GLint a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8136)) { return; }
    if (!p_slot_1fc8) { sweet_missing(8136); return; }
    sweet_before_draw(e);
    p_slot_1fc8(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1fd0: glDrawTexxOES */
static void (*p_slot_1fd0)(GLfixed, GLfixed, GLfixed, GLfixed, GLfixed);
static void slot_1fd0(void *opaque, GLfixed a0, GLfixed a1, GLfixed a2, GLfixed a3, GLfixed a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8144)) { return; }
    if (!p_slot_1fd0) { sweet_missing(8144); return; }
    sweet_before_draw(e);
    p_slot_1fd0(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1fd8: glDrawTexsvOES */
static void (*p_slot_1fd8)(const GLshort *);
static void slot_1fd8(void *opaque, const GLshort * a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8152)) { return; }
    if (!p_slot_1fd8) { sweet_missing(8152); return; }
    sweet_before_draw(e);
    p_slot_1fd8(a0);
}
/* E §4 / offmap 0x1fe0: glDrawTexivOES */
static void (*p_slot_1fe0)(const GLint *);
static void slot_1fe0(void *opaque, const GLint * a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8160)) { return; }
    if (!p_slot_1fe0) { sweet_missing(8160); return; }
    sweet_before_draw(e);
    p_slot_1fe0(a0);
}
/* E §4 / offmap 0x1fe8: glDrawTexxvOES */
static void (*p_slot_1fe8)(const GLfixed *);
static void slot_1fe8(void *opaque, const GLfixed * a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8168)) { return; }
    if (!p_slot_1fe8) { sweet_missing(8168); return; }
    sweet_before_draw(e);
    p_slot_1fe8(a0);
}
/* E §4 / offmap 0x1ff0: glDrawTexfOES */
static void (*p_slot_1ff0)(GLfloat, GLfloat, GLfloat, GLfloat, GLfloat);
static void slot_1ff0(void *opaque, GLfloat a0, GLfloat a1, GLfloat a2, GLfloat a3, GLfloat a4) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8176)) { return; }
    if (!p_slot_1ff0) { sweet_missing(8176); return; }
    sweet_before_draw(e);
    p_slot_1ff0(a0, a1, a2, a3, a4);
}
/* E §4 / offmap 0x1ff8: glDrawTexfvOES */
static void (*p_slot_1ff8)(const GLfloat *);
static void slot_1ff8(void *opaque, const GLfloat * a0) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8184)) { return; }
    if (!p_slot_1ff8) { sweet_missing(8184); return; }
    sweet_before_draw(e);
    p_slot_1ff8(a0);
}
/* E §4 / offmap 0x2008: glFramebufferParameteriAPPLE */
static void slot_2008(void *opaque, GLenum a0, GLenum a1, GLint * a2) {
    struct sweet_context *e = opaque;
    if (!sweet_enter(e, 8200)) { return; }
    (void)a0; if (a1 == 0x8A79 && a2) *a2 = 0; /* E §§4/10 */
}
const struct sweet_slot sweet_slots[] = {
    {0x0010, "glAlphaFunc", "wrap", 1, (void *)slot_0010},
    {0x0018, "glGetFramebufferParameteriAPPLE", "stub", 0, (void *)slot_0018},
    {0x0030, "glBindTexture", "wrap", 1, (void *)slot_0030},
    {0x0040, "glBlendFunc", "wrap", 1, (void *)slot_0040},
    {0x0058, "glClear", "wrap", 1, (void *)slot_0058},
    {0x0068, "glClearColor", "wrap", 1, (void *)slot_0068},
    {0x0080, "glClearStencil", "direct", 0, (void *)slot_0080},
    {0x00b8, "glGetFramebufferParameteriAPPLE", "stub", 0, (void *)slot_00b8},
    {0x00c0, "glGetFramebufferParameteriAPPLE", "stub", 0, (void *)slot_00c0},
    {0x0130, "glColor4f", "direct", 0, (void *)slot_0130},
    {0x0160, "glColor4ub", "direct", 0, (void *)slot_0160},
    {0x0190, "glColorMask", "direct", 0, (void *)slot_0190},
    {0x01a0, "glColorPointer", "direct", 0, (void *)slot_01a0},
    {0x01c8, "glCopyTexSubImage2D", "wrap", 1, (void *)slot_01c8},
    {0x01d0, "glCullFace", "direct", 0, (void *)slot_01d0},
    {0x01e0, "glDeleteTextures", "wrap", 1, (void *)slot_01e0},
    {0x01e8, "glDepthFunc", "direct", 0, (void *)slot_01e8},
    {0x01f0, "glDepthMask", "direct", 0, (void *)slot_01f0},
    {0x0200, "glDisable", "wrap", 1, (void *)slot_0200},
    {0x0208, "glDisableClientState", "direct", 0, (void *)slot_0208},
    {0x0210, "glDrawArrays", "wrap", 1, (void *)slot_0210},
    {0x0220, "glDrawElements", "wrap", 1, (void *)slot_0220},
    {0x0248, "glEnable", "wrap", 1, (void *)slot_0248},
    {0x0250, "glEnableClientState", "direct", 0, (void *)slot_0250},
    {0x02d0, "glFinish", "wrap", 1, (void *)slot_02d0},
    {0x02d8, "glFlush", "wrap", 1, (void *)slot_02d8},
    {0x02e0, "glFogf", "direct", 0, (void *)slot_02e0},
    {0x02e8, "glFogfv", "direct", 0, (void *)slot_02e8},
    {0x0300, "glFrontFace", "direct", 0, (void *)slot_0300},
    {0x0318, "glGenTextures", "wrap", 1, (void *)slot_0318},
    {0x0320, "glGetBooleanv", "direct", 0, (void *)slot_0320},
    {0x0338, "glGetError", "wrap", 1, (void *)slot_0338},
    {0x0340, "glGetFloatv", "direct", 0, (void *)slot_0340},
    {0x0348, "glGetIntegerv", "wrap", 1, (void *)slot_0348},
    {0x0350, "glGetLightfv", "direct", 0, (void *)slot_0350},
    {0x0378, "glGetMaterialfv", "direct", 0, (void *)slot_0378},
    {0x03a0, "glGetPointerv", "direct", 0, (void *)slot_03a0},
    {0x03b0, "glGetString", "wrap", 0, (void *)slot_03b0},
    {0x03b8, "glGetTexEnvfv", "direct", 0, (void *)slot_03b8},
    {0x03c0, "glGetTexEnviv", "direct", 0, (void *)slot_03c0},
    {0x03e0, "glGetTexImage", "direct", 0, (void *)slot_03e0},
    {0x03e8, "glGetTexLevelParameterfv", "direct", 0, (void *)slot_03e8},
    {0x03f0, "glGetTexLevelParameteriv", "direct", 0, (void *)slot_03f0},
    {0x03f8, "glGetTexParameterfv", "direct", 0, (void *)slot_03f8},
    {0x0400, "glGetTexParameteriv", "direct", 0, (void *)slot_0400},
    {0x0408, "glHint", "direct", 0, (void *)slot_0408},
    {0x0480, "glIsEnabled", "direct", 0, (void *)slot_0480},
    {0x0490, "glIsTexture", "direct", 0, (void *)slot_0490},
    {0x0498, "glLightModelf", "direct", 0, (void *)slot_0498},
    {0x04a0, "glLightModelfv", "direct", 0, (void *)slot_04a0},
    {0x04b8, "glLightf", "direct", 0, (void *)slot_04b8},
    {0x04c0, "glLightfv", "direct", 0, (void *)slot_04c0},
    {0x04e0, "glLineWidth", "direct", 0, (void *)slot_04e0},
    {0x04f0, "glLoadIdentity", "direct", 0, (void *)slot_04f0},
    {0x0500, "glLoadMatrixf", "direct", 0, (void *)slot_0500},
    {0x0510, "glLogicOp", "direct", 0, (void *)slot_0510},
    {0x0558, "glMaterialf", "direct", 0, (void *)slot_0558},
    {0x0560, "glMaterialfv", "direct", 0, (void *)slot_0560},
    {0x0578, "glMatrixMode", "direct", 0, (void *)slot_0578},
    {0x0588, "glMultMatrixf", "direct", 0, (void *)slot_0588},
    {0x05b8, "glNormal3f", "direct", 0, (void *)slot_05b8},
    {0x05e8, "glNormalPointer", "direct", 0, (void *)slot_05e8},
    {0x0620, "glPixelStorei", "wrap", 1, (void *)slot_0620},
    {0x0640, "glPointSize", "direct", 0, (void *)slot_0640},
    {0x0650, "glPolygonOffset", "direct", 0, (void *)slot_0650},
    {0x0660, "glGetFramebufferParameteriAPPLE", "stub", 0, (void *)slot_0660},
    {0x0668, "glGetFramebufferParameteriAPPLE", "stub", 0, (void *)slot_0668},
    {0x0670, "glPopMatrix", "direct", 0, (void *)slot_0670},
    {0x0678, "glGetFramebufferParameteriAPPLE", "stub", 0, (void *)slot_0678},
    {0x0688, "glGetFramebufferParameteriAPPLE", "stub", 0, (void *)slot_0688},
    {0x0690, "glGetFramebufferParameteriAPPLE", "stub", 0, (void *)slot_0690},
    {0x0698, "glPushMatrix", "direct", 0, (void *)slot_0698},
    {0x0768, "glReadBuffer", "direct", 0, (void *)slot_0768},
    {0x0770, "glReadPixels", "direct", 0, (void *)slot_0770},
    {0x07c8, "glRotatef", "direct", 0, (void *)slot_07c8},
    {0x07d8, "glScalef", "direct", 0, (void *)slot_07d8},
    {0x07e0, "glScissor", "wrap", 1, (void *)slot_07e0},
    {0x07f0, "glShadeModel", "direct", 0, (void *)slot_07f0},
    {0x07f8, "glStencilFunc", "wrap", 1, (void *)slot_07f8},
    {0x0800, "glStencilMask", "direct", 0, (void *)slot_0800},
    {0x0808, "glStencilOp", "direct", 0, (void *)slot_0808},
    {0x0910, "glTexCoordPointer", "direct", 0, (void *)slot_0910},
    {0x0918, "glTexEnvf", "direct", 0, (void *)slot_0918},
    {0x0920, "glTexEnvfv", "direct", 0, (void *)slot_0920},
    {0x0928, "glTexEnvi", "direct", 0, (void *)slot_0928},
    {0x0930, "glTexEnviv", "direct", 0, (void *)slot_0930},
    {0x0970, "glTexImage2D", "wrap", 1, (void *)slot_0970},
    {0x0978, "glTexParameterf", "wrap", 1, (void *)slot_0978},
    {0x0980, "glTexParameterfv", "direct", 0, (void *)slot_0980},
    {0x0988, "glTexParameteri", "wrap", 1, (void *)slot_0988},
    {0x0990, "glTexParameteriv", "direct", 0, (void *)slot_0990},
    {0x09a0, "glTexSubImage2D", "wrap", 1, (void *)slot_09a0},
    {0x09b0, "glTranslatef", "direct", 0, (void *)slot_09b0},
    {0x0a78, "glVertexPointer", "direct", 0, (void *)slot_0a78},
    {0x0a80, "glViewport", "wrap", 1, (void *)slot_0a80},
    {0x0a88, "glBlendFuncSeparate", "wrap", 1, (void *)slot_0a88},
    {0x0a90, "glBlendColor", "direct", 0, (void *)slot_0a90},
    {0x0a98, "glBlendEquation", "wrap", 1, (void *)slot_0a98},
    {0x0ab0, "glClientActiveTexture", "direct", 0, (void *)slot_0ab0},
    {0x0ab8, "glActiveTexture", "wrap", 1, (void *)slot_0ab8},
    {0x0b00, "glGetFramebufferParameteriAPPLE", "stub", 0, (void *)slot_0b00},
    {0x0b90, "glMultiTexCoord4f", "direct", 0, (void *)slot_0b90},
    {0x0be8, "glCompressedTexImage2D", "wrap", 1, (void *)slot_0be8},
    {0x0cb0, "glDrawRangeElements", "direct", 0, (void *)slot_0cb0},
    {0x0dd0, "glGetUniformIndices", "direct", 0, (void *)slot_0dd0},
    {0x0dd8, "glGetActiveUniformsiv", "direct", 0, (void *)slot_0dd8},
    {0x0de8, "glGetUniformBlockIndex", "direct", 0, (void *)slot_0de8},
    {0x0df0, "glGetActiveUniformBlockiv", "direct", 0, (void *)slot_0df0},
    {0x0df8, "glGetActiveUniformBlockName", "direct", 0, (void *)slot_0df8},
    {0x0e00, "glUniformBlockBinding", "direct", 0, (void *)slot_0e00},
    {0x0e58, "glBlendEquationSeparate", "direct", 0, (void *)slot_0e58},
    {0x0e60, "glSampleCoverage", "direct", 0, (void *)slot_0e60},
    {0x0e80, "glGenFencesAPPLE", "wrap", 0, (void *)slot_0e80},
    {0x0e88, "glDeleteFencesAPPLE", "wrap", 0, (void *)slot_0e88},
    {0x0e90, "glSetFenceAPPLE", "wrap", 0, (void *)slot_0e90},
    {0x0e98, "glIsFenceAPPLE", "wrap", 0, (void *)slot_0e98},
    {0x0ea0, "glTestFenceAPPLE", "wrap", 0, (void *)slot_0ea0},
    {0x0ea8, "glFinishFenceAPPLE", "wrap", 0, (void *)slot_0ea8},
    {0x0eb0, "glTestObjectAPPLE", "wrap", 0, (void *)slot_0eb0},
    {0x0eb8, "glFinishObjectAPPLE", "wrap", 1, (void *)slot_0eb8},
    {0x0ee8, "glVertexAttrib1f", "direct", 0, (void *)slot_0ee8},
    {0x0f00, "glVertexAttrib2f", "direct", 0, (void *)slot_0f00},
    {0x0f18, "glVertexAttrib3f", "direct", 0, (void *)slot_0f18},
    {0x0f30, "glVertexAttrib4f", "direct", 0, (void *)slot_0f30},
    {0x0f50, "glVertexAttrib1fv", "direct", 0, (void *)slot_0f50},
    {0x0f68, "glVertexAttrib2fv", "direct", 0, (void *)slot_0f68},
    {0x0f80, "glVertexAttrib3fv", "direct", 0, (void *)slot_0f80},
    {0x0fc0, "glVertexAttrib4fv", "direct", 0, (void *)slot_0fc0},
    {0x1000, "glVertexAttribPointer", "wrap", 1, (void *)slot_1000},
    {0x1008, "glEnableVertexAttribArray", "wrap", 1, (void *)slot_1008},
    {0x1010, "glDisableVertexAttribArray", "wrap", 1, (void *)slot_1010},
    {0x1020, "glGetVertexAttribfv", "direct", 0, (void *)slot_1020},
    {0x1028, "glGetVertexAttribiv", "direct", 0, (void *)slot_1028},
    {0x1030, "glGetVertexAttribPointerv", "direct", 0, (void *)slot_1030},
    {0x10e8, "glPointParameterf", "direct", 0, (void *)slot_10e8},
    {0x10f0, "glPointParameterfv", "direct", 0, (void *)slot_10f0},
    {0x1258, "glStencilOpSeparate", "direct", 0, (void *)slot_1258},
    {0x1280, "glDeleteProgram", "wrap", 1, (void *)slot_1280},
    {0x1290, "glDetachShader", "direct", 0, (void *)slot_1290},
    {0x1298, "glCreateShader", "wrap", 1, (void *)slot_1298},
    {0x12a0, "glShaderSource", "wrap", 1, (void *)slot_12a0},
    {0x12a8, "glCompileShader", "wrap", 1, (void *)slot_12a8},
    {0x12b0, "glCreateProgram", "direct", 0, (void *)slot_12b0},
    {0x12b8, "glAttachShader", "direct", 0, (void *)slot_12b8},
    {0x12c0, "glLinkProgram", "direct", 0, (void *)slot_12c0},
    {0x12c8, "glUseProgram", "wrap", 1, (void *)slot_12c8},
    {0x12d0, "glValidateProgram", "direct", 0, (void *)slot_12d0},
    {0x12d8, "glUniform1f", "wrap", 1, (void *)slot_12d8},
    {0x12e0, "glUniform2f", "direct", 0, (void *)slot_12e0},
    {0x12e8, "glUniform3f", "direct", 0, (void *)slot_12e8},
    {0x12f0, "glUniform4f", "wrap", 1, (void *)slot_12f0},
    {0x12f8, "glUniform1i", "wrap", 1, (void *)slot_12f8},
    {0x1300, "glUniform2i", "direct", 0, (void *)slot_1300},
    {0x1308, "glUniform3i", "direct", 0, (void *)slot_1308},
    {0x1310, "glUniform4i", "direct", 0, (void *)slot_1310},
    {0x1318, "glUniform1fv", "direct", 0, (void *)slot_1318},
    {0x1320, "glUniform2fv", "direct", 0, (void *)slot_1320},
    {0x1328, "glUniform3fv", "wrap", 1, (void *)slot_1328},
    {0x1330, "glUniform4fv", "wrap", 1, (void *)slot_1330},
    {0x1338, "glUniform1iv", "direct", 0, (void *)slot_1338},
    {0x1340, "glUniform2iv", "direct", 0, (void *)slot_1340},
    {0x1348, "glUniform3iv", "direct", 0, (void *)slot_1348},
    {0x1350, "glUniform4iv", "direct", 0, (void *)slot_1350},
    {0x1358, "glUniformMatrix2fv", "direct", 0, (void *)slot_1358},
    {0x1360, "glUniformMatrix3fv", "wrap", 1, (void *)slot_1360},
    {0x1368, "glUniformMatrix4fv", "wrap", 1, (void *)slot_1368},
    {0x1390, "glGetUniformLocation", "wrap", 1, (void *)slot_1390},
    {0x1398, "glGetActiveUniform", "direct", 0, (void *)slot_1398},
    {0x13a0, "glGetUniformfv", "direct", 0, (void *)slot_13a0},
    {0x13a8, "glGetUniformiv", "direct", 0, (void *)slot_13a8},
    {0x13b0, "glGetShaderSource", "direct", 0, (void *)slot_13b0},
    {0x13b8, "glBindAttribLocation", "direct", 0, (void *)slot_13b8},
    {0x13c0, "glGetActiveAttrib", "direct", 0, (void *)slot_13c0},
    {0x13c8, "glGetAttribLocation", "direct", 0, (void *)slot_13c8},
    {0x13d8, "glGenQueries", "direct", 0, (void *)slot_13d8},
    {0x13e0, "glDeleteQueries", "direct", 0, (void *)slot_13e0},
    {0x13e8, "glIsQuery", "direct", 0, (void *)slot_13e8},
    {0x13f0, "glBeginQuery", "direct", 0, (void *)slot_13f0},
    {0x13f8, "glEndQuery", "direct", 0, (void *)slot_13f8},
    {0x1400, "glGetQueryiv", "direct", 0, (void *)slot_1400},
    {0x1408, "glGetQueryObjectivEXT", "direct", 0, (void *)slot_1408},
    {0x1410, "glGetQueryObjectuiv", "direct", 0, (void *)slot_1410},
    {0x1418, "glBindBuffer", "direct", 0, (void *)slot_1418},
    {0x1420, "glDeleteBuffers", "direct", 0, (void *)slot_1420},
    {0x1428, "glGenBuffers", "direct", 0, (void *)slot_1428},
    {0x1430, "glIsBuffer", "direct", 0, (void *)slot_1430},
    {0x1438, "glBufferData", "direct", 0, (void *)slot_1438},
    {0x1440, "glBufferSubData", "direct", 0, (void *)slot_1440},
    {0x1450, "glMapBufferOES", "direct", 0, (void *)slot_1450},
    {0x1458, "glUnmapBuffer", "direct", 0, (void *)slot_1458},
    {0x1460, "glGetBufferParameteriv", "direct", 0, (void *)slot_1460},
    {0x1468, "glGetBufferPointerv", "direct", 0, (void *)slot_1468},
    {0x1478, "glDrawBuffers", "direct", 0, (void *)slot_1478},
    {0x1480, "glIsShader", "direct", 0, (void *)slot_1480},
    {0x1488, "glIsProgram", "direct", 0, (void *)slot_1488},
    {0x1490, "glGetShaderiv", "direct", 0, (void *)slot_1490},
    {0x1498, "glGetProgramiv", "direct", 0, (void *)slot_1498},
    {0x14a0, "glGetShaderInfoLog", "direct", 0, (void *)slot_14a0},
    {0x14a8, "glGetProgramInfoLog", "direct", 0, (void *)slot_14a8},
    {0x14b0, "glStencilFuncSeparate", "direct", 0, (void *)slot_14b0},
    {0x14b8, "glStencilMaskSeparate", "direct", 0, (void *)slot_14b8},
    {0x14d0, "glIsRenderbuffer", "direct", 0, (void *)slot_14d0},
    {0x14d8, "glBindRenderbuffer", "direct", 0, (void *)slot_14d8},
    {0x14e0, "glDeleteRenderbuffers", "direct", 0, (void *)slot_14e0},
    {0x14e8, "glGenRenderbuffers", "direct", 0, (void *)slot_14e8},
    {0x14f0, "glRenderbufferStorage", "direct", 0, (void *)slot_14f0},
    {0x14f8, "glGetRenderbufferParameteriv", "direct", 0, (void *)slot_14f8},
    {0x1500, "glIsFramebuffer", "direct", 0, (void *)slot_1500},
    {0x1508, "glBindFramebuffer", "wrap", 1, (void *)slot_1508},
    {0x1510, "glDeleteFramebuffers", "wrap", 1, (void *)slot_1510},
    {0x1518, "glGenFramebuffers", "wrap", 1, (void *)slot_1518},
    {0x1520, "glCheckFramebufferStatus", "direct", 0, (void *)slot_1520},
    {0x1530, "glFramebufferTexture2D", "wrap", 1, (void *)slot_1530},
    {0x1540, "glFramebufferRenderbuffer", "direct", 0, (void *)slot_1540},
    {0x1548, "glGetFramebufferAttachmentParameteriv", "direct", 0, (void *)slot_1548},
    {0x1550, "glGenerateMipmap", "wrap", 1, (void *)slot_1550},
    {0x1590, "glProgramParameteri", "direct", 0, (void *)slot_1590},
    {0x15a0, "glFramebufferTextureLayer", "direct", 0, (void *)slot_15a0},
    {0x15b0, "glBindBufferRange", "direct", 0, (void *)slot_15b0},
    {0x15c0, "glBindBufferBase", "direct", 0, (void *)slot_15c0},
    {0x15c8, "glBeginTransformFeedback", "direct", 0, (void *)slot_15c8},
    {0x15d0, "glEndTransformFeedback", "direct", 0, (void *)slot_15d0},
    {0x15d8, "glTransformFeedbackVaryings", "direct", 0, (void *)slot_15d8},
    {0x15e0, "glGetTransformFeedbackVarying", "direct", 0, (void *)slot_15e0},
    {0x15e8, "glGetIntegeri_v", "direct", 0, (void *)slot_15e8},
    {0x1658, "glVertexAttribI4i", "direct", 0, (void *)slot_1658},
    {0x1678, "glVertexAttribI4ui", "direct", 0, (void *)slot_1678},
    {0x1698, "glVertexAttribI4iv", "direct", 0, (void *)slot_1698},
    {0x16b8, "glVertexAttribI4uiv", "direct", 0, (void *)slot_16b8},
    {0x16e0, "glVertexAttribIPointer", "direct", 0, (void *)slot_16e0},
    {0x16e8, "glGetVertexAttribIiv", "direct", 0, (void *)slot_16e8},
    {0x16f0, "glGetVertexAttribIuiv", "direct", 0, (void *)slot_16f0},
    {0x16f8, "glUniform1ui", "direct", 0, (void *)slot_16f8},
    {0x1700, "glUniform2ui", "direct", 0, (void *)slot_1700},
    {0x1708, "glUniform3ui", "direct", 0, (void *)slot_1708},
    {0x1710, "glUniform4ui", "direct", 0, (void *)slot_1710},
    {0x1718, "glUniform1uiv", "direct", 0, (void *)slot_1718},
    {0x1720, "glUniform2uiv", "direct", 0, (void *)slot_1720},
    {0x1728, "glUniform3uiv", "direct", 0, (void *)slot_1728},
    {0x1730, "glUniform4uiv", "direct", 0, (void *)slot_1730},
    {0x1738, "glGetUniformuiv", "direct", 0, (void *)slot_1738},
    {0x1748, "glGetFragDataLocation", "direct", 0, (void *)slot_1748},
    {0x1770, "glUniformMatrix2x3fv", "direct", 0, (void *)slot_1770},
    {0x1778, "glUniformMatrix3x2fv", "direct", 0, (void *)slot_1778},
    {0x1780, "glUniformMatrix2x4fv", "direct", 0, (void *)slot_1780},
    {0x1788, "glUniformMatrix4x2fv", "direct", 0, (void *)slot_1788},
    {0x1790, "glUniformMatrix3x4fv", "direct", 0, (void *)slot_1790},
    {0x1798, "glUniformMatrix4x3fv", "direct", 0, (void *)slot_1798},
    {0x17a8, "glRenderbufferStorageMultisample", "direct", 0, (void *)slot_17a8},
    {0x17c0, "glGetAttachedShaders", "direct", 0, (void *)slot_17c0},
    {0x17d0, "glVertexAttribDivisor", "direct", 0, (void *)slot_17d0},
    {0x17d8, "glDrawArraysInstanced", "direct", 0, (void *)slot_17d8},
    {0x17e0, "glDrawElementsInstanced", "direct", 0, (void *)slot_17e0},
    {0x1808, "glBindVertexArray", "direct", 0, (void *)slot_1808},
    {0x1810, "glDeleteVertexArrays", "direct", 0, (void *)slot_1810},
    {0x1818, "glGenVertexArrays", "direct", 0, (void *)slot_1818},
    {0x1820, "glIsVertexArray", "direct", 0, (void *)slot_1820},
    {0x1828, "glPointSizePointerOES", "direct", 0, (void *)slot_1828},
    {0x1838, "glClearBufferiv", "direct", 0, (void *)slot_1838},
    {0x1840, "glClearBufferuiv", "direct", 0, (void *)slot_1840},
    {0x1848, "glClearBufferfv", "direct", 0, (void *)slot_1848},
    {0x1850, "glClearBufferfi", "direct", 0, (void *)slot_1850},
    {0x1858, "glGetStringi", "direct", 0, (void *)slot_1858},
    {0x1860, "glFenceSync", "wrap", 1, (void *)slot_1860},
    {0x1868, "glIsSync", "direct", 0, (void *)slot_1868},
    {0x1870, "glDeleteSync", "wrap", 1, (void *)slot_1870},
    {0x1878, "glClientWaitSync", "wrap", 1, (void *)slot_1878},
    {0x1880, "glWaitSync", "direct", 0, (void *)slot_1880},
    {0x1888, "glGetInteger64v", "direct", 0, (void *)slot_1888},
    {0x1890, "glGetSynciv", "direct", 0, (void *)slot_1890},
    {0x18c0, "glCopyBufferSubData", "direct", 0, (void *)slot_18c0},
    {0x18e0, "glMapBufferRange", "direct", 0, (void *)slot_18e0},
    {0x18e8, "glFlushMappedBufferRange", "direct", 0, (void *)slot_18e8},
    {0x18f8, "glGetInteger64i_v", "direct", 0, (void *)slot_18f8},
    {0x1900, "glGetBufferParameteri64v", "direct", 0, (void *)slot_1900},
    {0x1908, "glGenSamplers", "direct", 0, (void *)slot_1908},
    {0x1910, "glDeleteSamplers", "direct", 0, (void *)slot_1910},
    {0x1918, "glIsSampler", "direct", 0, (void *)slot_1918},
    {0x1920, "glBindSampler", "direct", 0, (void *)slot_1920},
    {0x1928, "glSamplerParameteri", "direct", 0, (void *)slot_1928},
    {0x1930, "glSamplerParameteriv", "direct", 0, (void *)slot_1930},
    {0x1938, "glSamplerParameterf", "direct", 0, (void *)slot_1938},
    {0x1940, "glSamplerParameterfv", "direct", 0, (void *)slot_1940},
    {0x1958, "glGetSamplerParameteriv", "direct", 0, (void *)slot_1958},
    {0x1960, "glGetSamplerParameterfv", "direct", 0, (void *)slot_1960},
    {0x1978, "glLabelObjectEXT", "wrap", 1, (void *)slot_1978},
    {0x1980, "glGetObjectLabelEXT", "direct", 0, (void *)slot_1980},
    {0x1988, "glInsertEventMarkerEXT", "wrap", 1, (void *)slot_1988},
    {0x1990, "glPushGroupMarkerEXT", "wrap", 1, (void *)slot_1990},
    {0x1998, "glPopGroupMarkerEXT", "wrap", 1, (void *)slot_1998},
    {0x19a0, "glUseProgramStagesEXT", "direct", 0, (void *)slot_19a0},
    {0x19a8, "glActiveShaderProgramEXT", "direct", 0, (void *)slot_19a8},
    {0x19b0, "glCreateShaderProgramvEXT", "direct", 0, (void *)slot_19b0},
    {0x19b8, "glBindProgramPipelineEXT", "direct", 0, (void *)slot_19b8},
    {0x19c0, "glDeleteProgramPipelinesEXT", "direct", 0, (void *)slot_19c0},
    {0x19c8, "glGenProgramPipelinesEXT", "direct", 0, (void *)slot_19c8},
    {0x19d0, "glIsProgramPipelineEXT", "direct", 0, (void *)slot_19d0},
    {0x19d8, "glGetProgramPipelineivEXT", "direct", 0, (void *)slot_19d8},
    {0x19e0, "glValidateProgramPipelineEXT", "direct", 0, (void *)slot_19e0},
    {0x19e8, "glGetProgramPipelineInfoLogEXT", "direct", 0, (void *)slot_19e8},
    {0x19f0, "glProgramUniform1iEXT", "direct", 0, (void *)slot_19f0},
    {0x19f8, "glProgramUniform2iEXT", "direct", 0, (void *)slot_19f8},
    {0x1a00, "glProgramUniform3iEXT", "direct", 0, (void *)slot_1a00},
    {0x1a08, "glProgramUniform4iEXT", "direct", 0, (void *)slot_1a08},
    {0x1a10, "glProgramUniform1fEXT", "direct", 0, (void *)slot_1a10},
    {0x1a18, "glProgramUniform2fEXT", "direct", 0, (void *)slot_1a18},
    {0x1a20, "glProgramUniform3fEXT", "direct", 0, (void *)slot_1a20},
    {0x1a28, "glProgramUniform4fEXT", "direct", 0, (void *)slot_1a28},
    {0x1a30, "glProgramUniform1ivEXT", "direct", 0, (void *)slot_1a30},
    {0x1a38, "glProgramUniform2ivEXT", "direct", 0, (void *)slot_1a38},
    {0x1a40, "glProgramUniform3ivEXT", "direct", 0, (void *)slot_1a40},
    {0x1a48, "glProgramUniform4ivEXT", "direct", 0, (void *)slot_1a48},
    {0x1a50, "glProgramUniform1fvEXT", "direct", 0, (void *)slot_1a50},
    {0x1a58, "glProgramUniform2fvEXT", "direct", 0, (void *)slot_1a58},
    {0x1a60, "glProgramUniform3fvEXT", "direct", 0, (void *)slot_1a60},
    {0x1a68, "glProgramUniform4fvEXT", "direct", 0, (void *)slot_1a68},
    {0x1a70, "glProgramUniformMatrix2fvEXT", "direct", 0, (void *)slot_1a70},
    {0x1a78, "glProgramUniformMatrix3fvEXT", "direct", 0, (void *)slot_1a78},
    {0x1a80, "glProgramUniformMatrix4fvEXT", "direct", 0, (void *)slot_1a80},
    {0x1a88, "glProgramUniform1uiEXT", "direct", 0, (void *)slot_1a88},
    {0x1a90, "glProgramUniform2uiEXT", "direct", 0, (void *)slot_1a90},
    {0x1a98, "glProgramUniform3uiEXT", "direct", 0, (void *)slot_1a98},
    {0x1aa0, "glProgramUniform4uiEXT", "direct", 0, (void *)slot_1aa0},
    {0x1aa8, "glProgramUniform1uivEXT", "direct", 0, (void *)slot_1aa8},
    {0x1ab0, "glProgramUniform2uivEXT", "direct", 0, (void *)slot_1ab0},
    {0x1ab8, "glProgramUniform3uivEXT", "direct", 0, (void *)slot_1ab8},
    {0x1ac0, "glProgramUniform4uivEXT", "direct", 0, (void *)slot_1ac0},
    {0x1ac8, "glProgramUniformMatrix2x3fvEXT", "direct", 0, (void *)slot_1ac8},
    {0x1ad0, "glProgramUniformMatrix3x2fvEXT", "direct", 0, (void *)slot_1ad0},
    {0x1ad8, "glProgramUniformMatrix2x4fvEXT", "direct", 0, (void *)slot_1ad8},
    {0x1ae0, "glProgramUniformMatrix4x2fvEXT", "direct", 0, (void *)slot_1ae0},
    {0x1ae8, "glProgramUniformMatrix3x4fvEXT", "direct", 0, (void *)slot_1ae8},
    {0x1af0, "glProgramUniformMatrix4x3fvEXT", "direct", 0, (void *)slot_1af0},
    {0x1b58, "glReleaseShaderCompiler", "direct", 0, (void *)slot_1b58},
    {0x1b60, "glShaderBinary", "direct", 0, (void *)slot_1b60},
    {0x1b68, "glGetShaderPrecisionFormat", "direct", 0, (void *)slot_1b68},
    {0x1b70, "glDepthRangef", "direct", 0, (void *)slot_1b70},
    {0x1b78, "glClearDepthf", "direct", 0, (void *)slot_1b78},
    {0x1bc0, "glGetProgramBinary", "direct", 0, (void *)slot_1bc0},
    {0x1bc8, "glProgramBinary", "direct", 0, (void *)slot_1bc8},
    {0x1c48, "glBindTransformFeedback", "direct", 0, (void *)slot_1c48},
    {0x1c50, "glGenTransformFeedbacks", "direct", 0, (void *)slot_1c50},
    {0x1c58, "glDeleteTransformFeedbacks", "direct", 0, (void *)slot_1c58},
    {0x1c60, "glPauseTransformFeedback", "direct", 0, (void *)slot_1c60},
    {0x1c68, "glResumeTransformFeedback", "direct", 0, (void *)slot_1c68},
    {0x1c70, "glIsTransformFeedback", "direct", 0, (void *)slot_1c70},
    {0x1e48, "glAlphaFuncx", "direct", 0, (void *)slot_1e48},
    {0x1e50, "glClearColorx", "direct", 0, (void *)slot_1e50},
    {0x1e58, "glClearDepthx", "direct", 0, (void *)slot_1e58},
    {0x1e60, "glClipPlanef", "direct", 0, (void *)slot_1e60},
    {0x1e68, "glClipPlanex", "direct", 0, (void *)slot_1e68},
    {0x1e70, "glColor4x", "direct", 0, (void *)slot_1e70},
    {0x1e78, "glDepthRangex", "direct", 0, (void *)slot_1e78},
    {0x1e80, "glFogx", "direct", 0, (void *)slot_1e80},
    {0x1e88, "glFogxv", "direct", 0, (void *)slot_1e88},
    {0x1e90, "glFrustumf", "direct", 0, (void *)slot_1e90},
    {0x1e98, "glFrustumx", "direct", 0, (void *)slot_1e98},
    {0x1ea0, "glGetClipPlanef", "direct", 0, (void *)slot_1ea0},
    {0x1ea8, "glGetClipPlanex", "direct", 0, (void *)slot_1ea8},
    {0x1eb0, "glGetFixedv", "direct", 0, (void *)slot_1eb0},
    {0x1eb8, "glGetLightxv", "direct", 0, (void *)slot_1eb8},
    {0x1ec0, "glGetMaterialxv", "direct", 0, (void *)slot_1ec0},
    {0x1ec8, "glGetTexEnvxv", "direct", 0, (void *)slot_1ec8},
    {0x1ed0, "glGetTexParameterxv", "direct", 0, (void *)slot_1ed0},
    {0x1ed8, "glLightModelx", "direct", 0, (void *)slot_1ed8},
    {0x1ee0, "glLightModelxv", "direct", 0, (void *)slot_1ee0},
    {0x1ee8, "glLightx", "direct", 0, (void *)slot_1ee8},
    {0x1ef0, "glLightxv", "direct", 0, (void *)slot_1ef0},
    {0x1ef8, "glLineWidthx", "direct", 0, (void *)slot_1ef8},
    {0x1f00, "glLoadMatrixx", "direct", 0, (void *)slot_1f00},
    {0x1f08, "glMaterialx", "direct", 0, (void *)slot_1f08},
    {0x1f10, "glMaterialxv", "direct", 0, (void *)slot_1f10},
    {0x1f18, "glMultMatrixx", "direct", 0, (void *)slot_1f18},
    {0x1f20, "glNormal3x", "direct", 0, (void *)slot_1f20},
    {0x1f28, "glOrthof", "direct", 0, (void *)slot_1f28},
    {0x1f30, "glOrthox", "direct", 0, (void *)slot_1f30},
    {0x1f38, "glPointSizex", "direct", 0, (void *)slot_1f38},
    {0x1f40, "glPolygonOffsetx", "direct", 0, (void *)slot_1f40},
    {0x1f48, "glRotatex", "direct", 0, (void *)slot_1f48},
    {0x1f50, "glScalex", "direct", 0, (void *)slot_1f50},
    {0x1f58, "glTexEnvx", "direct", 0, (void *)slot_1f58},
    {0x1f60, "glTexEnvxv", "direct", 0, (void *)slot_1f60},
    {0x1f68, "glTexParameterx", "direct", 0, (void *)slot_1f68},
    {0x1f70, "glTexParameterxv", "direct", 0, (void *)slot_1f70},
    {0x1f78, "glTranslatex", "direct", 0, (void *)slot_1f78},
    {0x1f80, "glMultiTexCoord4x", "direct", 0, (void *)slot_1f80},
    {0x1f88, "glSampleCoveragex", "direct", 0, (void *)slot_1f88},
    {0x1f90, "glPointParameterx", "direct", 0, (void *)slot_1f90},
    {0x1f98, "glPointParameterxv", "direct", 0, (void *)slot_1f98},
    {0x1fa0, "glCurrentPaletteMatrixOES", "stub", 0, (void *)slot_1fa0},
    {0x1fa8, "glLoadPaletteFromModelViewMatrixOES", "stub", 0, (void *)slot_1fa8},
    {0x1fb0, "glMatrixIndexPointerOES", "stub", 0, (void *)slot_1fb0},
    {0x1fb8, "glWeightPointerOES", "stub", 0, (void *)slot_1fb8},
    {0x1fc0, "glDrawTexsOES", "direct", 0, (void *)slot_1fc0},
    {0x1fc8, "glDrawTexiOES", "direct", 0, (void *)slot_1fc8},
    {0x1fd0, "glDrawTexxOES", "direct", 0, (void *)slot_1fd0},
    {0x1fd8, "glDrawTexsvOES", "direct", 0, (void *)slot_1fd8},
    {0x1fe0, "glDrawTexivOES", "direct", 0, (void *)slot_1fe0},
    {0x1fe8, "glDrawTexxvOES", "direct", 0, (void *)slot_1fe8},
    {0x1ff0, "glDrawTexfOES", "direct", 0, (void *)slot_1ff0},
    {0x1ff8, "glDrawTexfvOES", "direct", 0, (void *)slot_1ff8},
    {0x2008, "glFramebufferParameteriAPPLE", "wrap", 1, (void *)slot_2008},
};
const size_t sweet_slot_count = sizeof(sweet_slots) / sizeof(sweet_slots[0]);
int sweet_slots_init(void) {
    int good = 1;
    p_slot_0010 = (void (*)(GLenum, GLfloat))sweet_proc("glAlphaFunc");
    p_slot_0030 = (void (*)(GLenum, GLuint))sweet_proc("glBindTexture");
    if (!p_slot_0030) good = 0;
    p_slot_0040 = (void (*)(GLenum, GLenum))sweet_proc("glBlendFunc");
    if (!p_slot_0040) good = 0;
    p_slot_0058 = (void (*)(GLbitfield))sweet_proc("glClear");
    if (!p_slot_0058) good = 0;
    p_slot_0068 = (void (*)(GLfloat, GLfloat, GLfloat, GLfloat))sweet_proc("glClearColor");
    if (!p_slot_0068) good = 0;
    p_slot_0080 = (void (*)(GLint))sweet_proc("glClearStencil");
    p_slot_0130 = (void (*)(GLfloat, GLfloat, GLfloat, GLfloat))sweet_proc("glColor4f");
    p_slot_0160 = (void (*)(GLubyte, GLubyte, GLubyte, GLubyte))sweet_proc("glColor4ub");
    p_slot_0190 = (void (*)(GLboolean, GLboolean, GLboolean, GLboolean))sweet_proc("glColorMask");
    p_slot_01a0 = (void (*)(GLint, GLenum, GLsizei, const void *))sweet_proc("glColorPointer");
    p_slot_01c8 = (void (*)(GLenum, GLint, GLint, GLint, GLint, GLint, GLsizei, GLsizei))sweet_proc("glCopyTexSubImage2D");
    if (!p_slot_01c8) good = 0;
    p_slot_01d0 = (void (*)(GLenum))sweet_proc("glCullFace");
    p_slot_01e0 = (void (*)(GLsizei, const GLuint *))sweet_proc("glDeleteTextures");
    if (!p_slot_01e0) good = 0;
    p_slot_01e8 = (void (*)(GLenum))sweet_proc("glDepthFunc");
    p_slot_01f0 = (void (*)(GLboolean))sweet_proc("glDepthMask");
    p_slot_0200 = (void (*)(GLenum))sweet_proc("glDisable");
    if (!p_slot_0200) good = 0;
    p_slot_0208 = (void (*)(GLenum))sweet_proc("glDisableClientState");
    p_slot_0210 = (void (*)(GLenum, GLint, GLsizei))sweet_proc("glDrawArrays");
    if (!p_slot_0210) good = 0;
    p_slot_0220 = (void (*)(GLenum, GLsizei, GLenum, const void *))sweet_proc("glDrawElements");
    if (!p_slot_0220) good = 0;
    p_slot_0248 = (void (*)(GLenum))sweet_proc("glEnable");
    if (!p_slot_0248) good = 0;
    p_slot_0250 = (void (*)(GLenum))sweet_proc("glEnableClientState");
    p_slot_02d0 = (void (*)(void))sweet_proc("glFinish");
    if (!p_slot_02d0) good = 0;
    p_slot_02d8 = (void (*)(void))sweet_proc("glFlush");
    if (!p_slot_02d8) good = 0;
    p_slot_02e0 = (void (*)(GLenum, GLfloat))sweet_proc("glFogf");
    p_slot_02e8 = (void (*)(GLenum, const GLfloat *))sweet_proc("glFogfv");
    p_slot_0300 = (void (*)(GLenum))sweet_proc("glFrontFace");
    p_slot_0318 = (void (*)(GLsizei, GLuint *))sweet_proc("glGenTextures");
    if (!p_slot_0318) good = 0;
    p_slot_0320 = (void (*)(GLenum, GLboolean *))sweet_proc("glGetBooleanv");
    p_slot_0338 = (GLenum (*)(void))sweet_proc("glGetError");
    if (!p_slot_0338) good = 0;
    p_slot_0340 = (void (*)(GLenum, GLfloat *))sweet_proc("glGetFloatv");
    p_slot_0348 = (void (*)(GLenum, GLint *))sweet_proc("glGetIntegerv");
    if (!p_slot_0348) good = 0;
    p_slot_0350 = (void (*)(GLenum, GLenum, GLfloat *))sweet_proc("glGetLightfv");
    p_slot_0378 = (void (*)(GLenum, GLenum, GLfloat *))sweet_proc("glGetMaterialfv");
    p_slot_03a0 = (void (*)(GLenum, void **))sweet_proc("glGetPointerv");
    p_slot_03b8 = (void (*)(GLenum, GLenum, GLfloat *))sweet_proc("glGetTexEnvfv");
    p_slot_03c0 = (void (*)(GLenum, GLenum, GLint *))sweet_proc("glGetTexEnviv");
    p_slot_03e0 = (void (*)(GLenum, GLint, GLenum, GLenum, void *))sweet_proc("glGetTexImage");
    p_slot_03e8 = (void (*)(GLenum, GLint, GLenum, GLfloat *))sweet_proc("glGetTexLevelParameterfv");
    p_slot_03f0 = (void (*)(GLenum, GLint, GLenum, GLint *))sweet_proc("glGetTexLevelParameteriv");
    p_slot_03f8 = (void (*)(GLenum, GLenum, GLfloat *))sweet_proc("glGetTexParameterfv");
    p_slot_0400 = (void (*)(GLenum, GLenum, GLint *))sweet_proc("glGetTexParameteriv");
    p_slot_0408 = (void (*)(GLenum, GLenum))sweet_proc("glHint");
    p_slot_0480 = (GLboolean (*)(GLenum))sweet_proc("glIsEnabled");
    p_slot_0490 = (GLboolean (*)(GLuint))sweet_proc("glIsTexture");
    p_slot_0498 = (void (*)(GLenum, GLfloat))sweet_proc("glLightModelf");
    p_slot_04a0 = (void (*)(GLenum, const GLfloat *))sweet_proc("glLightModelfv");
    p_slot_04b8 = (void (*)(GLenum, GLenum, GLfloat))sweet_proc("glLightf");
    p_slot_04c0 = (void (*)(GLenum, GLenum, const GLfloat *))sweet_proc("glLightfv");
    p_slot_04e0 = (void (*)(GLfloat))sweet_proc("glLineWidth");
    p_slot_04f0 = (void (*)(void))sweet_proc("glLoadIdentity");
    p_slot_0500 = (void (*)(const GLfloat *))sweet_proc("glLoadMatrixf");
    p_slot_0510 = (void (*)(GLenum))sweet_proc("glLogicOp");
    p_slot_0558 = (void (*)(GLenum, GLenum, GLfloat))sweet_proc("glMaterialf");
    p_slot_0560 = (void (*)(GLenum, GLenum, const GLfloat *))sweet_proc("glMaterialfv");
    p_slot_0578 = (void (*)(GLenum))sweet_proc("glMatrixMode");
    p_slot_0588 = (void (*)(const GLfloat *))sweet_proc("glMultMatrixf");
    p_slot_05b8 = (void (*)(GLfloat, GLfloat, GLfloat))sweet_proc("glNormal3f");
    p_slot_05e8 = (void (*)(GLenum, GLsizei, const void *))sweet_proc("glNormalPointer");
    p_slot_0620 = (void (*)(GLenum, GLint))sweet_proc("glPixelStorei");
    if (!p_slot_0620) good = 0;
    p_slot_0640 = (void (*)(GLfloat))sweet_proc("glPointSize");
    p_slot_0650 = (void (*)(GLfloat, GLfloat))sweet_proc("glPolygonOffset");
    p_slot_0670 = (void (*)(void))sweet_proc("glPopMatrix");
    p_slot_0698 = (void (*)(void))sweet_proc("glPushMatrix");
    p_slot_0768 = (void (*)(GLenum))sweet_proc("glReadBuffer");
    p_slot_0770 = (void (*)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *))sweet_proc("glReadPixels");
    p_slot_07c8 = (void (*)(GLfloat, GLfloat, GLfloat, GLfloat))sweet_proc("glRotatef");
    p_slot_07d8 = (void (*)(GLfloat, GLfloat, GLfloat))sweet_proc("glScalef");
    p_slot_07e0 = (void (*)(GLint, GLint, GLsizei, GLsizei))sweet_proc("glScissor");
    if (!p_slot_07e0) good = 0;
    p_slot_07f0 = (void (*)(GLenum))sweet_proc("glShadeModel");
    p_slot_07f8 = (void (*)(GLenum, GLint, GLuint))sweet_proc("glStencilFunc");
    if (!p_slot_07f8) good = 0;
    p_slot_0800 = (void (*)(GLuint))sweet_proc("glStencilMask");
    p_slot_0808 = (void (*)(GLenum, GLenum, GLenum))sweet_proc("glStencilOp");
    p_slot_0910 = (void (*)(GLint, GLenum, GLsizei, const void *))sweet_proc("glTexCoordPointer");
    p_slot_0918 = (void (*)(GLenum, GLenum, GLfloat))sweet_proc("glTexEnvf");
    p_slot_0920 = (void (*)(GLenum, GLenum, const GLfloat *))sweet_proc("glTexEnvfv");
    p_slot_0928 = (void (*)(GLenum, GLenum, GLint))sweet_proc("glTexEnvi");
    p_slot_0930 = (void (*)(GLenum, GLenum, const GLint *))sweet_proc("glTexEnviv");
    p_slot_0970 = (void (*)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void *))sweet_proc("glTexImage2D");
    if (!p_slot_0970) good = 0;
    p_slot_0978 = (void (*)(GLenum, GLenum, GLfloat))sweet_proc("glTexParameterf");
    if (!p_slot_0978) good = 0;
    p_slot_0980 = (void (*)(GLenum, GLenum, const GLfloat *))sweet_proc("glTexParameterfv");
    p_slot_0988 = (void (*)(GLenum, GLenum, GLint))sweet_proc("glTexParameteri");
    if (!p_slot_0988) good = 0;
    p_slot_0990 = (void (*)(GLenum, GLenum, const GLint *))sweet_proc("glTexParameteriv");
    p_slot_09a0 = (void (*)(GLenum, GLint, GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, const void *))sweet_proc("glTexSubImage2D");
    if (!p_slot_09a0) good = 0;
    p_slot_09b0 = (void (*)(GLfloat, GLfloat, GLfloat))sweet_proc("glTranslatef");
    p_slot_0a78 = (void (*)(GLint, GLenum, GLsizei, const void *))sweet_proc("glVertexPointer");
    p_slot_0a80 = (void (*)(GLint, GLint, GLsizei, GLsizei))sweet_proc("glViewport");
    if (!p_slot_0a80) good = 0;
    p_slot_0a88 = (void (*)(GLenum, GLenum, GLenum, GLenum))sweet_proc("glBlendFuncSeparate");
    if (!p_slot_0a88) good = 0;
    p_slot_0a90 = (void (*)(GLfloat, GLfloat, GLfloat, GLfloat))sweet_proc("glBlendColor");
    p_slot_0a98 = (void (*)(GLenum))sweet_proc("glBlendEquation");
    if (!p_slot_0a98) good = 0;
    p_slot_0ab0 = (void (*)(GLenum))sweet_proc("glClientActiveTexture");
    p_slot_0ab8 = (void (*)(GLenum))sweet_proc("glActiveTexture");
    if (!p_slot_0ab8) good = 0;
    p_slot_0b90 = (void (*)(GLenum, GLfloat, GLfloat, GLfloat, GLfloat))sweet_proc("glMultiTexCoord4f");
    p_slot_0be8 = (void (*)(GLenum, GLint, GLenum, GLsizei, GLsizei, GLint, GLsizei, const void *))sweet_proc("glCompressedTexImage2D");
    if (!p_slot_0be8) good = 0;
    p_slot_0cb0 = (void (*)(GLenum, GLuint, GLuint, GLsizei, GLenum, const void *))sweet_proc("glDrawRangeElements");
    p_slot_0dd0 = (void (*)(GLuint, GLsizei, const GLchar *const*, GLuint *))sweet_proc("glGetUniformIndices");
    p_slot_0dd8 = (void (*)(GLuint, GLsizei, const GLuint *, GLenum, GLint *))sweet_proc("glGetActiveUniformsiv");
    p_slot_0de8 = (GLuint (*)(GLuint, const GLchar *))sweet_proc("glGetUniformBlockIndex");
    p_slot_0df0 = (void (*)(GLuint, GLuint, GLenum, GLint *))sweet_proc("glGetActiveUniformBlockiv");
    p_slot_0df8 = (void (*)(GLuint, GLuint, GLsizei, GLsizei *, GLchar *))sweet_proc("glGetActiveUniformBlockName");
    p_slot_0e00 = (void (*)(GLuint, GLuint, GLuint))sweet_proc("glUniformBlockBinding");
    p_slot_0e58 = (void (*)(GLenum, GLenum))sweet_proc("glBlendEquationSeparate");
    p_slot_0e60 = (void (*)(GLfloat, GLboolean))sweet_proc("glSampleCoverage");
    p_slot_0ee8 = (void (*)(GLuint, GLfloat))sweet_proc("glVertexAttrib1f");
    p_slot_0f00 = (void (*)(GLuint, GLfloat, GLfloat))sweet_proc("glVertexAttrib2f");
    p_slot_0f18 = (void (*)(GLuint, GLfloat, GLfloat, GLfloat))sweet_proc("glVertexAttrib3f");
    p_slot_0f30 = (void (*)(GLuint, GLfloat, GLfloat, GLfloat, GLfloat))sweet_proc("glVertexAttrib4f");
    p_slot_0f50 = (void (*)(GLuint, const GLfloat *))sweet_proc("glVertexAttrib1fv");
    p_slot_0f68 = (void (*)(GLuint, const GLfloat *))sweet_proc("glVertexAttrib2fv");
    p_slot_0f80 = (void (*)(GLuint, const GLfloat *))sweet_proc("glVertexAttrib3fv");
    p_slot_0fc0 = (void (*)(GLuint, const GLfloat *))sweet_proc("glVertexAttrib4fv");
    p_slot_1000 = (void (*)(GLuint, GLint, GLenum, GLboolean, GLsizei, const void *))sweet_proc("glVertexAttribPointer");
    if (!p_slot_1000) good = 0;
    p_slot_1008 = (void (*)(GLuint))sweet_proc("glEnableVertexAttribArray");
    if (!p_slot_1008) good = 0;
    p_slot_1010 = (void (*)(GLuint))sweet_proc("glDisableVertexAttribArray");
    if (!p_slot_1010) good = 0;
    p_slot_1020 = (void (*)(GLuint, GLenum, GLfloat *))sweet_proc("glGetVertexAttribfv");
    p_slot_1028 = (void (*)(GLuint, GLenum, GLint *))sweet_proc("glGetVertexAttribiv");
    p_slot_1030 = (void (*)(GLuint, GLenum, void **))sweet_proc("glGetVertexAttribPointerv");
    p_slot_10e8 = (void (*)(GLenum, GLfloat))sweet_proc("glPointParameterf");
    p_slot_10f0 = (void (*)(GLenum, const GLfloat *))sweet_proc("glPointParameterfv");
    p_slot_1258 = (void (*)(GLenum, GLenum, GLenum, GLenum))sweet_proc("glStencilOpSeparate");
    p_slot_1290 = (void (*)(GLuint, GLuint))sweet_proc("glDetachShader");
    p_slot_1298 = (GLuint (*)(GLenum))sweet_proc("glCreateShader");
    if (!p_slot_1298) good = 0;
    p_slot_12a0 = (void (*)(GLuint, GLsizei, const GLchar *const*, const GLint *))sweet_proc("glShaderSource");
    if (!p_slot_12a0) good = 0;
    p_slot_12a8 = (void (*)(GLuint))sweet_proc("glCompileShader");
    if (!p_slot_12a8) good = 0;
    p_slot_12b0 = (GLuint (*)(void))sweet_proc("glCreateProgram");
    p_slot_12b8 = (void (*)(GLuint, GLuint))sweet_proc("glAttachShader");
    p_slot_12c0 = (void (*)(GLuint))sweet_proc("glLinkProgram");
    p_slot_12c8 = (void (*)(GLuint))sweet_proc("glUseProgram");
    if (!p_slot_12c8) good = 0;
    p_slot_12d0 = (void (*)(GLuint))sweet_proc("glValidateProgram");
    p_slot_12d8 = (void (*)(GLint, GLfloat))sweet_proc("glUniform1f");
    if (!p_slot_12d8) good = 0;
    p_slot_12e0 = (void (*)(GLint, GLfloat, GLfloat))sweet_proc("glUniform2f");
    p_slot_12e8 = (void (*)(GLint, GLfloat, GLfloat, GLfloat))sweet_proc("glUniform3f");
    p_slot_12f0 = (void (*)(GLint, GLfloat, GLfloat, GLfloat, GLfloat))sweet_proc("glUniform4f");
    if (!p_slot_12f0) good = 0;
    p_slot_12f8 = (void (*)(GLint, GLint))sweet_proc("glUniform1i");
    if (!p_slot_12f8) good = 0;
    p_slot_1300 = (void (*)(GLint, GLint, GLint))sweet_proc("glUniform2i");
    p_slot_1308 = (void (*)(GLint, GLint, GLint, GLint))sweet_proc("glUniform3i");
    p_slot_1310 = (void (*)(GLint, GLint, GLint, GLint, GLint))sweet_proc("glUniform4i");
    p_slot_1318 = (void (*)(GLint, GLsizei, const GLfloat *))sweet_proc("glUniform1fv");
    p_slot_1320 = (void (*)(GLint, GLsizei, const GLfloat *))sweet_proc("glUniform2fv");
    p_slot_1328 = (void (*)(GLint, GLsizei, const GLfloat *))sweet_proc("glUniform3fv");
    if (!p_slot_1328) good = 0;
    p_slot_1330 = (void (*)(GLint, GLsizei, const GLfloat *))sweet_proc("glUniform4fv");
    if (!p_slot_1330) good = 0;
    p_slot_1338 = (void (*)(GLint, GLsizei, const GLint *))sweet_proc("glUniform1iv");
    p_slot_1340 = (void (*)(GLint, GLsizei, const GLint *))sweet_proc("glUniform2iv");
    p_slot_1348 = (void (*)(GLint, GLsizei, const GLint *))sweet_proc("glUniform3iv");
    p_slot_1350 = (void (*)(GLint, GLsizei, const GLint *))sweet_proc("glUniform4iv");
    p_slot_1358 = (void (*)(GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glUniformMatrix2fv");
    p_slot_1360 = (void (*)(GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glUniformMatrix3fv");
    if (!p_slot_1360) good = 0;
    p_slot_1368 = (void (*)(GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glUniformMatrix4fv");
    if (!p_slot_1368) good = 0;
    p_slot_1390 = (GLint (*)(GLuint, const GLchar *))sweet_proc("glGetUniformLocation");
    if (!p_slot_1390) good = 0;
    p_slot_1398 = (void (*)(GLuint, GLuint, GLsizei, GLsizei *, GLint *, GLenum *, GLchar *))sweet_proc("glGetActiveUniform");
    p_slot_13a0 = (void (*)(GLuint, GLint, GLfloat *))sweet_proc("glGetUniformfv");
    p_slot_13a8 = (void (*)(GLuint, GLint, GLint *))sweet_proc("glGetUniformiv");
    p_slot_13b0 = (void (*)(GLuint, GLsizei, GLsizei *, GLchar *))sweet_proc("glGetShaderSource");
    p_slot_13b8 = (void (*)(GLuint, GLuint, const GLchar *))sweet_proc("glBindAttribLocation");
    p_slot_13c0 = (void (*)(GLuint, GLuint, GLsizei, GLsizei *, GLint *, GLenum *, GLchar *))sweet_proc("glGetActiveAttrib");
    p_slot_13c8 = (GLint (*)(GLuint, const GLchar *))sweet_proc("glGetAttribLocation");
    p_slot_13d8 = (void (*)(GLsizei, GLuint *))sweet_proc("glGenQueries");
    p_slot_13e0 = (void (*)(GLsizei, const GLuint *))sweet_proc("glDeleteQueries");
    p_slot_13e8 = (GLboolean (*)(GLuint))sweet_proc("glIsQuery");
    p_slot_13f0 = (void (*)(GLenum, GLuint))sweet_proc("glBeginQuery");
    p_slot_13f8 = (void (*)(GLenum))sweet_proc("glEndQuery");
    p_slot_1400 = (void (*)(GLenum, GLenum, GLint *))sweet_proc("glGetQueryiv");
    p_slot_1408 = (void (*)(GLuint, GLenum, GLint *))sweet_proc("glGetQueryObjectivEXT");
    p_slot_1410 = (void (*)(GLuint, GLenum, GLuint *))sweet_proc("glGetQueryObjectuiv");
    p_slot_1418 = (void (*)(GLenum, GLuint))sweet_proc("glBindBuffer");
    p_slot_1420 = (void (*)(GLsizei, const GLuint *))sweet_proc("glDeleteBuffers");
    p_slot_1428 = (void (*)(GLsizei, GLuint *))sweet_proc("glGenBuffers");
    p_slot_1430 = (GLboolean (*)(GLuint))sweet_proc("glIsBuffer");
    p_slot_1438 = (void (*)(GLenum, GLsizeiptr, const void *, GLenum))sweet_proc("glBufferData");
    p_slot_1440 = (void (*)(GLenum, GLintptr, GLsizeiptr, const void *))sweet_proc("glBufferSubData");
    p_slot_1450 = (void * (*)(GLenum, GLenum))sweet_proc("glMapBufferOES");
    p_slot_1458 = (GLboolean (*)(GLenum))sweet_proc("glUnmapBuffer");
    p_slot_1460 = (void (*)(GLenum, GLenum, GLint *))sweet_proc("glGetBufferParameteriv");
    p_slot_1468 = (void (*)(GLenum, GLenum, void **))sweet_proc("glGetBufferPointerv");
    p_slot_1478 = (void (*)(GLsizei, const GLenum *))sweet_proc("glDrawBuffers");
    p_slot_1480 = (GLboolean (*)(GLuint))sweet_proc("glIsShader");
    p_slot_1488 = (GLboolean (*)(GLuint))sweet_proc("glIsProgram");
    p_slot_1490 = (void (*)(GLuint, GLenum, GLint *))sweet_proc("glGetShaderiv");
    p_slot_1498 = (void (*)(GLuint, GLenum, GLint *))sweet_proc("glGetProgramiv");
    p_slot_14a0 = (void (*)(GLuint, GLsizei, GLsizei *, GLchar *))sweet_proc("glGetShaderInfoLog");
    p_slot_14a8 = (void (*)(GLuint, GLsizei, GLsizei *, GLchar *))sweet_proc("glGetProgramInfoLog");
    p_slot_14b0 = (void (*)(GLenum, GLenum, GLint, GLuint))sweet_proc("glStencilFuncSeparate");
    p_slot_14b8 = (void (*)(GLenum, GLuint))sweet_proc("glStencilMaskSeparate");
    p_slot_14d0 = (GLboolean (*)(GLuint))sweet_proc("glIsRenderbuffer");
    p_slot_14d8 = (void (*)(GLenum, GLuint))sweet_proc("glBindRenderbuffer");
    p_slot_14e0 = (void (*)(GLsizei, const GLuint *))sweet_proc("glDeleteRenderbuffers");
    p_slot_14e8 = (void (*)(GLsizei, GLuint *))sweet_proc("glGenRenderbuffers");
    p_slot_14f0 = (void (*)(GLenum, GLenum, GLsizei, GLsizei))sweet_proc("glRenderbufferStorage");
    p_slot_14f8 = (void (*)(GLenum, GLenum, GLint *))sweet_proc("glGetRenderbufferParameteriv");
    p_slot_1500 = (GLboolean (*)(GLuint))sweet_proc("glIsFramebuffer");
    p_slot_1508 = (void (*)(GLenum, GLuint))sweet_proc("glBindFramebuffer");
    if (!p_slot_1508) good = 0;
    p_slot_1510 = (void (*)(GLsizei, const GLuint *))sweet_proc("glDeleteFramebuffers");
    if (!p_slot_1510) good = 0;
    p_slot_1518 = (void (*)(GLsizei, GLuint *))sweet_proc("glGenFramebuffers");
    if (!p_slot_1518) good = 0;
    p_slot_1520 = (GLenum (*)(GLenum))sweet_proc("glCheckFramebufferStatus");
    p_slot_1530 = (void (*)(GLenum, GLenum, GLenum, GLuint, GLint))sweet_proc("glFramebufferTexture2D");
    if (!p_slot_1530) good = 0;
    p_slot_1540 = (void (*)(GLenum, GLenum, GLenum, GLuint))sweet_proc("glFramebufferRenderbuffer");
    p_slot_1548 = (void (*)(GLenum, GLenum, GLenum, GLint *))sweet_proc("glGetFramebufferAttachmentParameteriv");
    p_slot_1550 = (void (*)(GLenum))sweet_proc("glGenerateMipmap");
    if (!p_slot_1550) good = 0;
    p_slot_1590 = (void (*)(GLuint, GLenum, GLint))sweet_proc("glProgramParameteri");
    p_slot_15a0 = (void (*)(GLenum, GLenum, GLuint, GLint, GLint))sweet_proc("glFramebufferTextureLayer");
    p_slot_15b0 = (void (*)(GLenum, GLuint, GLuint, GLintptr, GLsizeiptr))sweet_proc("glBindBufferRange");
    p_slot_15c0 = (void (*)(GLenum, GLuint, GLuint))sweet_proc("glBindBufferBase");
    p_slot_15c8 = (void (*)(GLenum))sweet_proc("glBeginTransformFeedback");
    p_slot_15d0 = (void (*)(void))sweet_proc("glEndTransformFeedback");
    p_slot_15d8 = (void (*)(GLuint, GLsizei, const GLchar *const*, GLenum))sweet_proc("glTransformFeedbackVaryings");
    p_slot_15e0 = (void (*)(GLuint, GLuint, GLsizei, GLsizei *, GLsizei *, GLenum *, GLchar *))sweet_proc("glGetTransformFeedbackVarying");
    p_slot_15e8 = (void (*)(GLenum, GLuint, GLint *))sweet_proc("glGetIntegeri_v");
    p_slot_1658 = (void (*)(GLuint, GLint, GLint, GLint, GLint))sweet_proc("glVertexAttribI4i");
    p_slot_1678 = (void (*)(GLuint, GLuint, GLuint, GLuint, GLuint))sweet_proc("glVertexAttribI4ui");
    p_slot_1698 = (void (*)(GLuint, const GLint *))sweet_proc("glVertexAttribI4iv");
    p_slot_16b8 = (void (*)(GLuint, const GLuint *))sweet_proc("glVertexAttribI4uiv");
    p_slot_16e0 = (void (*)(GLuint, GLint, GLenum, GLsizei, const void *))sweet_proc("glVertexAttribIPointer");
    p_slot_16e8 = (void (*)(GLuint, GLenum, GLint *))sweet_proc("glGetVertexAttribIiv");
    p_slot_16f0 = (void (*)(GLuint, GLenum, GLuint *))sweet_proc("glGetVertexAttribIuiv");
    p_slot_16f8 = (void (*)(GLint, GLuint))sweet_proc("glUniform1ui");
    p_slot_1700 = (void (*)(GLint, GLuint, GLuint))sweet_proc("glUniform2ui");
    p_slot_1708 = (void (*)(GLint, GLuint, GLuint, GLuint))sweet_proc("glUniform3ui");
    p_slot_1710 = (void (*)(GLint, GLuint, GLuint, GLuint, GLuint))sweet_proc("glUniform4ui");
    p_slot_1718 = (void (*)(GLint, GLsizei, const GLuint *))sweet_proc("glUniform1uiv");
    p_slot_1720 = (void (*)(GLint, GLsizei, const GLuint *))sweet_proc("glUniform2uiv");
    p_slot_1728 = (void (*)(GLint, GLsizei, const GLuint *))sweet_proc("glUniform3uiv");
    p_slot_1730 = (void (*)(GLint, GLsizei, const GLuint *))sweet_proc("glUniform4uiv");
    p_slot_1738 = (void (*)(GLuint, GLint, GLuint *))sweet_proc("glGetUniformuiv");
    p_slot_1748 = (GLint (*)(GLuint, const GLchar *))sweet_proc("glGetFragDataLocation");
    p_slot_1770 = (void (*)(GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glUniformMatrix2x3fv");
    p_slot_1778 = (void (*)(GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glUniformMatrix3x2fv");
    p_slot_1780 = (void (*)(GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glUniformMatrix2x4fv");
    p_slot_1788 = (void (*)(GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glUniformMatrix4x2fv");
    p_slot_1790 = (void (*)(GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glUniformMatrix3x4fv");
    p_slot_1798 = (void (*)(GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glUniformMatrix4x3fv");
    p_slot_17a8 = (void (*)(GLenum, GLsizei, GLenum, GLsizei, GLsizei))sweet_proc("glRenderbufferStorageMultisample");
    p_slot_17c0 = (void (*)(GLuint, GLsizei, GLsizei *, GLuint *))sweet_proc("glGetAttachedShaders");
    p_slot_17d0 = (void (*)(GLuint, GLuint))sweet_proc("glVertexAttribDivisor");
    p_slot_17d8 = (void (*)(GLenum, GLint, GLsizei, GLsizei))sweet_proc("glDrawArraysInstanced");
    p_slot_17e0 = (void (*)(GLenum, GLsizei, GLenum, const void *, GLsizei))sweet_proc("glDrawElementsInstanced");
    p_slot_1808 = (void (*)(GLuint))sweet_proc("glBindVertexArray");
    p_slot_1810 = (void (*)(GLsizei, const GLuint *))sweet_proc("glDeleteVertexArrays");
    p_slot_1818 = (void (*)(GLsizei, GLuint *))sweet_proc("glGenVertexArrays");
    p_slot_1820 = (GLboolean (*)(GLuint))sweet_proc("glIsVertexArray");
    p_slot_1828 = (void (*)(GLenum, GLsizei, const void *))sweet_proc("glPointSizePointerOES");
    p_slot_1838 = (void (*)(GLenum, GLint, const GLint *))sweet_proc("glClearBufferiv");
    p_slot_1840 = (void (*)(GLenum, GLint, const GLuint *))sweet_proc("glClearBufferuiv");
    p_slot_1848 = (void (*)(GLenum, GLint, const GLfloat *))sweet_proc("glClearBufferfv");
    p_slot_1850 = (void (*)(GLenum, GLint, GLfloat, GLint))sweet_proc("glClearBufferfi");
    p_slot_1858 = (const GLubyte * (*)(GLenum, GLuint))sweet_proc("glGetStringi");
    p_slot_1860 = (GLsync (*)(GLenum, GLbitfield))sweet_proc("glFenceSync");
    if (!p_slot_1860) good = 0;
    p_slot_1868 = (GLboolean (*)(GLsync))sweet_proc("glIsSync");
    p_slot_1870 = (void (*)(GLsync))sweet_proc("glDeleteSync");
    if (!p_slot_1870) good = 0;
    p_slot_1878 = (GLenum (*)(GLsync, GLbitfield, GLuint64))sweet_proc("glClientWaitSync");
    if (!p_slot_1878) good = 0;
    p_slot_1880 = (void (*)(GLsync, GLbitfield, GLuint64))sweet_proc("glWaitSync");
    p_slot_1888 = (void (*)(GLenum, GLint64 *))sweet_proc("glGetInteger64v");
    p_slot_1890 = (void (*)(GLsync, GLenum, GLsizei, GLsizei *, GLint *))sweet_proc("glGetSynciv");
    p_slot_18c0 = (void (*)(GLenum, GLenum, GLintptr, GLintptr, GLsizeiptr))sweet_proc("glCopyBufferSubData");
    p_slot_18e0 = (void * (*)(GLenum, GLintptr, GLsizeiptr, GLbitfield))sweet_proc("glMapBufferRange");
    p_slot_18e8 = (void (*)(GLenum, GLintptr, GLsizeiptr))sweet_proc("glFlushMappedBufferRange");
    p_slot_18f8 = (void (*)(GLenum, GLuint, GLint64 *))sweet_proc("glGetInteger64i_v");
    p_slot_1900 = (void (*)(GLenum, GLenum, GLint64 *))sweet_proc("glGetBufferParameteri64v");
    p_slot_1908 = (void (*)(GLsizei, GLuint *))sweet_proc("glGenSamplers");
    p_slot_1910 = (void (*)(GLsizei, const GLuint *))sweet_proc("glDeleteSamplers");
    p_slot_1918 = (GLboolean (*)(GLuint))sweet_proc("glIsSampler");
    p_slot_1920 = (void (*)(GLuint, GLuint))sweet_proc("glBindSampler");
    p_slot_1928 = (void (*)(GLuint, GLenum, GLint))sweet_proc("glSamplerParameteri");
    p_slot_1930 = (void (*)(GLuint, GLenum, const GLint *))sweet_proc("glSamplerParameteriv");
    p_slot_1938 = (void (*)(GLuint, GLenum, GLfloat))sweet_proc("glSamplerParameterf");
    p_slot_1940 = (void (*)(GLuint, GLenum, const GLfloat *))sweet_proc("glSamplerParameterfv");
    p_slot_1958 = (void (*)(GLuint, GLenum, GLint *))sweet_proc("glGetSamplerParameteriv");
    p_slot_1960 = (void (*)(GLuint, GLenum, GLfloat *))sweet_proc("glGetSamplerParameterfv");
    p_slot_1980 = (void (*)(GLenum, GLuint, GLsizei, GLsizei *, GLchar *))sweet_proc("glGetObjectLabelEXT");
    p_slot_19a0 = (void (*)(GLuint, GLbitfield, GLuint))sweet_proc("glUseProgramStagesEXT");
    p_slot_19a8 = (void (*)(GLuint, GLuint))sweet_proc("glActiveShaderProgramEXT");
    p_slot_19b0 = (GLuint (*)(GLenum, GLsizei, const GLchar *const*))sweet_proc("glCreateShaderProgramvEXT");
    p_slot_19b8 = (void (*)(GLuint))sweet_proc("glBindProgramPipelineEXT");
    p_slot_19c0 = (void (*)(GLsizei, const GLuint *))sweet_proc("glDeleteProgramPipelinesEXT");
    p_slot_19c8 = (void (*)(GLsizei, GLuint *))sweet_proc("glGenProgramPipelinesEXT");
    p_slot_19d0 = (GLboolean (*)(GLuint))sweet_proc("glIsProgramPipelineEXT");
    p_slot_19d8 = (void (*)(GLuint, GLenum, GLint *))sweet_proc("glGetProgramPipelineivEXT");
    p_slot_19e0 = (void (*)(GLuint))sweet_proc("glValidateProgramPipelineEXT");
    p_slot_19e8 = (void (*)(GLuint, GLsizei, GLsizei *, GLchar *))sweet_proc("glGetProgramPipelineInfoLogEXT");
    p_slot_19f0 = (void (*)(GLuint, GLint, GLint))sweet_proc("glProgramUniform1iEXT");
    p_slot_19f8 = (void (*)(GLuint, GLint, GLint, GLint))sweet_proc("glProgramUniform2iEXT");
    p_slot_1a00 = (void (*)(GLuint, GLint, GLint, GLint, GLint))sweet_proc("glProgramUniform3iEXT");
    p_slot_1a08 = (void (*)(GLuint, GLint, GLint, GLint, GLint, GLint))sweet_proc("glProgramUniform4iEXT");
    p_slot_1a10 = (void (*)(GLuint, GLint, GLfloat))sweet_proc("glProgramUniform1fEXT");
    p_slot_1a18 = (void (*)(GLuint, GLint, GLfloat, GLfloat))sweet_proc("glProgramUniform2fEXT");
    p_slot_1a20 = (void (*)(GLuint, GLint, GLfloat, GLfloat, GLfloat))sweet_proc("glProgramUniform3fEXT");
    p_slot_1a28 = (void (*)(GLuint, GLint, GLfloat, GLfloat, GLfloat, GLfloat))sweet_proc("glProgramUniform4fEXT");
    p_slot_1a30 = (void (*)(GLuint, GLint, GLsizei, const GLint *))sweet_proc("glProgramUniform1ivEXT");
    p_slot_1a38 = (void (*)(GLuint, GLint, GLsizei, const GLint *))sweet_proc("glProgramUniform2ivEXT");
    p_slot_1a40 = (void (*)(GLuint, GLint, GLsizei, const GLint *))sweet_proc("glProgramUniform3ivEXT");
    p_slot_1a48 = (void (*)(GLuint, GLint, GLsizei, const GLint *))sweet_proc("glProgramUniform4ivEXT");
    p_slot_1a50 = (void (*)(GLuint, GLint, GLsizei, const GLfloat *))sweet_proc("glProgramUniform1fvEXT");
    p_slot_1a58 = (void (*)(GLuint, GLint, GLsizei, const GLfloat *))sweet_proc("glProgramUniform2fvEXT");
    p_slot_1a60 = (void (*)(GLuint, GLint, GLsizei, const GLfloat *))sweet_proc("glProgramUniform3fvEXT");
    p_slot_1a68 = (void (*)(GLuint, GLint, GLsizei, const GLfloat *))sweet_proc("glProgramUniform4fvEXT");
    p_slot_1a70 = (void (*)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glProgramUniformMatrix2fvEXT");
    p_slot_1a78 = (void (*)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glProgramUniformMatrix3fvEXT");
    p_slot_1a80 = (void (*)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glProgramUniformMatrix4fvEXT");
    p_slot_1a88 = (void (*)(GLuint, GLint, GLuint))sweet_proc("glProgramUniform1uiEXT");
    p_slot_1a90 = (void (*)(GLuint, GLint, GLuint, GLuint))sweet_proc("glProgramUniform2uiEXT");
    p_slot_1a98 = (void (*)(GLuint, GLint, GLuint, GLuint, GLuint))sweet_proc("glProgramUniform3uiEXT");
    p_slot_1aa0 = (void (*)(GLuint, GLint, GLuint, GLuint, GLuint, GLuint))sweet_proc("glProgramUniform4uiEXT");
    p_slot_1aa8 = (void (*)(GLuint, GLint, GLsizei, const GLuint *))sweet_proc("glProgramUniform1uivEXT");
    p_slot_1ab0 = (void (*)(GLuint, GLint, GLsizei, const GLuint *))sweet_proc("glProgramUniform2uivEXT");
    p_slot_1ab8 = (void (*)(GLuint, GLint, GLsizei, const GLuint *))sweet_proc("glProgramUniform3uivEXT");
    p_slot_1ac0 = (void (*)(GLuint, GLint, GLsizei, const GLuint *))sweet_proc("glProgramUniform4uivEXT");
    p_slot_1ac8 = (void (*)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glProgramUniformMatrix2x3fvEXT");
    p_slot_1ad0 = (void (*)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glProgramUniformMatrix3x2fvEXT");
    p_slot_1ad8 = (void (*)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glProgramUniformMatrix2x4fvEXT");
    p_slot_1ae0 = (void (*)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glProgramUniformMatrix4x2fvEXT");
    p_slot_1ae8 = (void (*)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glProgramUniformMatrix3x4fvEXT");
    p_slot_1af0 = (void (*)(GLuint, GLint, GLsizei, GLboolean, const GLfloat *))sweet_proc("glProgramUniformMatrix4x3fvEXT");
    p_slot_1b58 = (void (*)(void))sweet_proc("glReleaseShaderCompiler");
    p_slot_1b60 = (void (*)(GLsizei, const GLuint *, GLenum, const void *, GLsizei))sweet_proc("glShaderBinary");
    p_slot_1b68 = (void (*)(GLenum, GLenum, GLint *, GLint *))sweet_proc("glGetShaderPrecisionFormat");
    p_slot_1b70 = (void (*)(GLfloat, GLfloat))sweet_proc("glDepthRangef");
    p_slot_1b78 = (void (*)(GLfloat))sweet_proc("glClearDepthf");
    p_slot_1bc0 = (void (*)(GLuint, GLsizei, GLsizei *, GLenum *, void *))sweet_proc("glGetProgramBinary");
    p_slot_1bc8 = (void (*)(GLuint, GLenum, const void *, GLsizei))sweet_proc("glProgramBinary");
    p_slot_1c48 = (void (*)(GLenum, GLuint))sweet_proc("glBindTransformFeedback");
    p_slot_1c50 = (void (*)(GLsizei, GLuint *))sweet_proc("glGenTransformFeedbacks");
    p_slot_1c58 = (void (*)(GLsizei, const GLuint *))sweet_proc("glDeleteTransformFeedbacks");
    p_slot_1c60 = (void (*)(void))sweet_proc("glPauseTransformFeedback");
    p_slot_1c68 = (void (*)(void))sweet_proc("glResumeTransformFeedback");
    p_slot_1c70 = (GLboolean (*)(GLuint))sweet_proc("glIsTransformFeedback");
    p_slot_1e48 = (void (*)(GLenum, GLfixed))sweet_proc("glAlphaFuncx");
    p_slot_1e50 = (void (*)(GLfixed, GLfixed, GLfixed, GLfixed))sweet_proc("glClearColorx");
    p_slot_1e58 = (void (*)(GLfixed))sweet_proc("glClearDepthx");
    p_slot_1e60 = (void (*)(GLenum, const GLfloat *))sweet_proc("glClipPlanef");
    p_slot_1e68 = (void (*)(GLenum, const GLfixed *))sweet_proc("glClipPlanex");
    p_slot_1e70 = (void (*)(GLfixed, GLfixed, GLfixed, GLfixed))sweet_proc("glColor4x");
    p_slot_1e78 = (void (*)(GLfixed, GLfixed))sweet_proc("glDepthRangex");
    p_slot_1e80 = (void (*)(GLenum, GLfixed))sweet_proc("glFogx");
    p_slot_1e88 = (void (*)(GLenum, const GLfixed *))sweet_proc("glFogxv");
    p_slot_1e90 = (void (*)(GLfloat, GLfloat, GLfloat, GLfloat, GLfloat, GLfloat))sweet_proc("glFrustumf");
    p_slot_1e98 = (void (*)(GLfixed, GLfixed, GLfixed, GLfixed, GLfixed, GLfixed))sweet_proc("glFrustumx");
    p_slot_1ea0 = (void (*)(GLenum, GLfloat *))sweet_proc("glGetClipPlanef");
    p_slot_1ea8 = (void (*)(GLenum, GLfixed *))sweet_proc("glGetClipPlanex");
    p_slot_1eb0 = (void (*)(GLenum, GLfixed *))sweet_proc("glGetFixedv");
    p_slot_1eb8 = (void (*)(GLenum, GLenum, GLfixed *))sweet_proc("glGetLightxv");
    p_slot_1ec0 = (void (*)(GLenum, GLenum, GLfixed *))sweet_proc("glGetMaterialxv");
    p_slot_1ec8 = (void (*)(GLenum, GLenum, GLfixed *))sweet_proc("glGetTexEnvxv");
    p_slot_1ed0 = (void (*)(GLenum, GLenum, GLfixed *))sweet_proc("glGetTexParameterxv");
    p_slot_1ed8 = (void (*)(GLenum, GLfixed))sweet_proc("glLightModelx");
    p_slot_1ee0 = (void (*)(GLenum, const GLfixed *))sweet_proc("glLightModelxv");
    p_slot_1ee8 = (void (*)(GLenum, GLenum, GLfixed))sweet_proc("glLightx");
    p_slot_1ef0 = (void (*)(GLenum, GLenum, const GLfixed *))sweet_proc("glLightxv");
    p_slot_1ef8 = (void (*)(GLfixed))sweet_proc("glLineWidthx");
    p_slot_1f00 = (void (*)(const GLfixed *))sweet_proc("glLoadMatrixx");
    p_slot_1f08 = (void (*)(GLenum, GLenum, GLfixed))sweet_proc("glMaterialx");
    p_slot_1f10 = (void (*)(GLenum, GLenum, const GLfixed *))sweet_proc("glMaterialxv");
    p_slot_1f18 = (void (*)(const GLfixed *))sweet_proc("glMultMatrixx");
    p_slot_1f20 = (void (*)(GLfixed, GLfixed, GLfixed))sweet_proc("glNormal3x");
    p_slot_1f28 = (void (*)(GLfloat, GLfloat, GLfloat, GLfloat, GLfloat, GLfloat))sweet_proc("glOrthof");
    p_slot_1f30 = (void (*)(GLfixed, GLfixed, GLfixed, GLfixed, GLfixed, GLfixed))sweet_proc("glOrthox");
    p_slot_1f38 = (void (*)(GLfixed))sweet_proc("glPointSizex");
    p_slot_1f40 = (void (*)(GLfixed, GLfixed))sweet_proc("glPolygonOffsetx");
    p_slot_1f48 = (void (*)(GLfixed, GLfixed, GLfixed, GLfixed))sweet_proc("glRotatex");
    p_slot_1f50 = (void (*)(GLfixed, GLfixed, GLfixed))sweet_proc("glScalex");
    p_slot_1f58 = (void (*)(GLenum, GLenum, GLfixed))sweet_proc("glTexEnvx");
    p_slot_1f60 = (void (*)(GLenum, GLenum, const GLfixed *))sweet_proc("glTexEnvxv");
    p_slot_1f68 = (void (*)(GLenum, GLenum, GLfixed))sweet_proc("glTexParameterx");
    p_slot_1f70 = (void (*)(GLenum, GLenum, const GLfixed *))sweet_proc("glTexParameterxv");
    p_slot_1f78 = (void (*)(GLfixed, GLfixed, GLfixed))sweet_proc("glTranslatex");
    p_slot_1f80 = (void (*)(GLenum, GLfixed, GLfixed, GLfixed, GLfixed))sweet_proc("glMultiTexCoord4x");
    p_slot_1f88 = (void (*)(GLclampx, GLboolean))sweet_proc("glSampleCoveragex");
    p_slot_1f90 = (void (*)(GLenum, GLfixed))sweet_proc("glPointParameterx");
    p_slot_1f98 = (void (*)(GLenum, const GLfixed *))sweet_proc("glPointParameterxv");
    p_slot_1fc0 = (void (*)(GLshort, GLshort, GLshort, GLshort, GLshort))sweet_proc("glDrawTexsOES");
    p_slot_1fc8 = (void (*)(GLint, GLint, GLint, GLint, GLint))sweet_proc("glDrawTexiOES");
    p_slot_1fd0 = (void (*)(GLfixed, GLfixed, GLfixed, GLfixed, GLfixed))sweet_proc("glDrawTexxOES");
    p_slot_1fd8 = (void (*)(const GLshort *))sweet_proc("glDrawTexsvOES");
    p_slot_1fe0 = (void (*)(const GLint *))sweet_proc("glDrawTexivOES");
    p_slot_1fe8 = (void (*)(const GLfixed *))sweet_proc("glDrawTexxvOES");
    p_slot_1ff0 = (void (*)(GLfloat, GLfloat, GLfloat, GLfloat, GLfloat))sweet_proc("glDrawTexfOES");
    p_slot_1ff8 = (void (*)(const GLfloat *))sweet_proc("glDrawTexfvOES");
    return good;
}
static uintptr_t unknown_slot(void *ctx) { (void)ctx; sweet_missing(0); return 0; }
void sweet_slots_fill(void **table) {
    for (size_t i = 2; i < SWEET_TABLE_SIZE / sizeof(void *); ++i)
        table[i] = (void *)unknown_slot;
    for (size_t i = 0; i < sweet_slot_count; ++i)
        table[sweet_slots[i].offset / sizeof(void *)] = sweet_slots[i].entry;
}
