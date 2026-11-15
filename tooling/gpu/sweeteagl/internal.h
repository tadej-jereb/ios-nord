#ifndef SWEET_INTERNAL_H
#define SWEET_INTERNAL_H
#include "abi.h"
struct image;
struct apple_fence;
struct sweet_context {
    OSMesaContext mesa;
    unsigned char colour[4 * 16 * 16];
    unsigned long api;
    void *priv;
    char *extensions;
    struct image *images;
    struct apple_fence *fences;
    GLuint next_fence;
};
void *sweet_proc(const char *);
int sweet_enter(struct sweet_context *, unsigned);
void sweet_missing(unsigned);
void sweet_before_draw(struct sweet_context *);
void sweet_writeback(struct sweet_context *);
void sweet_delete_textures(struct sweet_context *, GLsizei, const GLuint *);
const GLubyte *sweet_string(struct sweet_context *, GLenum);
void sweet_finish(struct sweet_context *);
void sweet_delete_program(GLuint);
void sweet_glGenFencesAPPLE(struct sweet_context *, GLsizei, GLuint *);
void sweet_glDeleteFencesAPPLE(struct sweet_context *, GLsizei, const GLuint *);
void sweet_glSetFenceAPPLE(struct sweet_context *, GLuint);
GLboolean sweet_glIsFenceAPPLE(struct sweet_context *, GLuint);
GLboolean sweet_glTestFenceAPPLE(struct sweet_context *, GLuint);
void sweet_glFinishFenceAPPLE(struct sweet_context *, GLuint);
GLboolean sweet_glTestObjectAPPLE(struct sweet_context *, GLenum, GLuint);
#endif
