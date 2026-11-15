/* Own declarations of the small Darwin interface used here; no Apple headers.
 * ObjC selectors/layout/encodings are from E §§2–3; CF/IOSurface use E §9.
 * GL declarations are Khronos headers shipped with our Mesa source. */
#ifndef SWEET_ABI_H
#define SWEET_ABI_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <GL/gl.h>
#include <GL/glext.h>
#include <GL/osmesa.h>
typedef int GLclampx; /* Khronos registry fixed-point clamp type */
typedef void *id;
typedef void *Class;
typedef void *SEL;
typedef void *Ivar;
typedef void *Method;
typedef void (*IMP)(void);
typedef bool BOOL;
typedef const void *CFTypeRef;
typedef const void *CFStringRef;
typedef const void *CFDictionaryRef;
typedef void *CFMutableDictionaryRef;
typedef const void *CFNumberRef;
typedef struct __IOSurface *IOSurfaceRef;
extern CFMutableDictionaryRef CFDictionaryCreateMutable(const void *, long, const void *, const void *);
extern void CFDictionarySetValue(CFMutableDictionaryRef, const void *, const void *);
extern CFNumberRef CFNumberCreate(const void *, int, const void *);
extern void CFRelease(CFTypeRef);
extern CFTypeRef CFRetain(CFTypeRef);
extern const unsigned char kCFTypeDictionaryKeyCallBacks[];
extern const unsigned char kCFTypeDictionaryValueCallBacks[];
extern const void *kCFBooleanTrue;
extern IOSurfaceRef IOSurfaceCreate(CFDictionaryRef);
extern uint32_t IOSurfaceGetID(IOSurfaceRef);
extern uint32_t IOSurfaceGetPixelFormat(IOSurfaceRef);
extern size_t IOSurfaceGetWidth(IOSurfaceRef);
extern size_t IOSurfaceGetHeight(IOSurfaceRef);
extern size_t IOSurfaceGetBytesPerRow(IOSurfaceRef);
extern size_t IOSurfaceGetBytesPerElement(IOSurfaceRef);
extern size_t IOSurfaceGetPlaneCount(IOSurfaceRef);
extern void *IOSurfaceGetBaseAddress(IOSurfaceRef);
extern int IOSurfaceLock(IOSurfaceRef, uint32_t, uint32_t *);
extern int IOSurfaceUnlock(IOSurfaceRef, uint32_t, uint32_t *);
extern CFStringRef kIOSurfaceWidth, kIOSurfaceHeight, kIOSurfaceBytesPerElement;
extern CFStringRef kIOSurfaceBytesPerRow, kIOSurfacePixelFormat;
#define SWEET_BGRA 0x42475241u /* E §5 'BGRA' */
#define SWEET_SURFACE_READONLY 1u /* E §9 kIOSurfaceLockReadOnly */
/* E §2 allocation and table offset; type is also usable by the host checker. */
#define SWEET_PRIVATE_SIZE 0x2088
#define SWEET_TABLE_OFFSET 0x20
#define SWEET_TABLE_SIZE (SWEET_PRIVATE_SIZE - SWEET_TABLE_OFFSET)
struct objc_api {
    Class (*getClass)(const char *);
    SEL (*selector)(const char *);
    const char *(*selectorName)(SEL);
    IMP (*replace)(Class, SEL, IMP, const char *);
    Ivar (*ivar)(Class, const char *);
    void (*setIvar)(id, Ivar, id);
    id (*getIvar)(id, Ivar);
    Class (*superclass)(Class);
    Method (*method)(Class, SEL);
    IMP (*implementation)(Method);
    void (*send)(void);
};
int sweet_objc_load(struct objc_api *);
#endif
