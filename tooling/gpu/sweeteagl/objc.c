#include "abi.h"
#include <dlfcn.h>
int sweet_objc_load(struct objc_api *o)
{
    void *h = dlopen("/usr/lib/libobjc.A.dylib", RTLD_NOW | RTLD_LOCAL);
    if (!h) return 0;
#define LOAD(field, name) do { *(void **)(&o->field) = dlsym(h, name); if (!o->field) return 0; } while (0)
    LOAD(getClass, "objc_getClass");
    LOAD(selector, "sel_registerName");
    LOAD(selectorName, "sel_getName");
    LOAD(replace, "class_replaceMethod");
    LOAD(ivar, "class_getInstanceVariable");
    LOAD(setIvar, "object_setIvar");
    LOAD(getIvar, "object_getIvar");
    LOAD(superclass, "class_getSuperclass");
    LOAD(method, "class_getInstanceMethod");
    LOAD(implementation, "method_getImplementation");
    LOAD(send, "objc_msgSend");
#undef LOAD
    return 1;
}
