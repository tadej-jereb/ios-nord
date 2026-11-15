/*
 * step-2 test: printf + pthread_create + dlopen must link against the .tbd stubs.
 *
 * Provenance: written for ios-avicii (not Apple code). Linked into a dylib
 * with -lz so the result must carry LC_LOAD_DYLIB entries for both
 * /usr/lib/libSystem.B.dylib and /usr/lib/libz.1.dylib. Those two entries are
 * the proof that the text-based stubs -- not a host library -- satisfied the
 * link.
 *
 * No paths are baked in: the sysroot arrives via -isysroot from run.sh.
 */
#include <stdio.h>
#include <pthread.h>
#include <dlfcn.h>
#include <unistd.h>

static void *thr(void *a) { printf("thread %p\n", a); return 0; }

void *step2(void)
{
	pthread_t t;
	void *h = dlopen("libz.1.dylib", RTLD_LAZY);
	pthread_create(&t, 0, thr, (void *)1);
	pthread_join(t, 0);
	printf("zlib handle %p, pid %d\n", h, getpid());
	return h;
}
