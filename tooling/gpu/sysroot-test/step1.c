/*
 * step-1 test: does the sysroot's C surface compile for arm64-ios16?
 *
 * Provenance: written for ios-avicii (not Apple code). Compile-only test --
 * it is never linked or run. It touches every header family that the GPU
 * userland needs so that a broken/partial sysroot fails here first.
 *
 * No paths are baked in: the sysroot arrives via -isysroot from run.sh.
 */
#include <TargetConditionals.h>
#include <Availability.h>
#include <AvailabilityMacros.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <pthread.h>
#include <dlfcn.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/host_info.h>
#include <mach/vm_page_size.h>

#if !TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#error "TargetConditionals did not report an iOS device"
#endif

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;

int step1(int argc, char **argv)
{
	int e = ETIME;                      /* errno.h: the define meson.build:971 wants */
	struct stat st;
	mach_timebase_info_data_t tb;
	void *h = dlopen("libz.1.dylib", RTLD_LAZY);
	char buf[64];

	pthread_mutex_lock(&lock);
	pthread_mutex_unlock(&lock);
	mach_timebase_info(&tb);
	snprintf(buf, sizeof buf, "%d %d", e, (int)tb.denom);
	if (stat(argv[0], &st) != 0)
		return errno;
	if (h)
		dlclose(h);
	return (int)strlen(buf) + argc;
}
