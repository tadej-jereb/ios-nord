/* Minimal own declarations copied from sweeteagl/abi.h (project code).
 * Binary evidence and slot addresses: README.md. No Apple headers or code. */
#ifndef SWEET_BUNDLETEST_ABI_H
#define SWEET_BUNDLETEST_ABI_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <GL/gl.h>
#include <GL/glext.h>
typedef void *id;
typedef void *Class;
typedef void *SEL;
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
extern const unsigned char kCFTypeDictionaryKeyCallBacks[];
extern const unsigned char kCFTypeDictionaryValueCallBacks[];
extern const void *kCFBooleanTrue;
extern IOSurfaceRef IOSurfaceCreate(CFDictionaryRef);
extern size_t IOSurfaceGetBytesPerRow(IOSurfaceRef);
extern void *IOSurfaceGetBaseAddress(IOSurfaceRef);
extern int IOSurfaceLock(IOSurfaceRef, uint32_t, uint32_t *);
extern int IOSurfaceUnlock(IOSurfaceRef, uint32_t, uint32_t *);
extern CFStringRef kIOSurfaceWidth, kIOSurfaceHeight, kIOSurfaceBytesPerElement;
extern CFStringRef kIOSurfaceBytesPerRow, kIOSurfacePixelFormat;
#define SWEET_BGRA 0x42475241u /* E §5 'BGRA' */
#define SWEET_SURFACE_READONLY 1u /* E §9 kIOSurfaceLockReadOnly */
#endif
