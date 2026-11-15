/*
 * drmtest: the MSM DRM render node (/dev/dri/renderD128, xnu patch 0126) driven from an iOS
 * process, the way Mesa's freedreno will: VERSION, GET_PARAM, GEM_NEW, GEM_INFO (GET_IOVA, the
 * private IOS_MMAP 0x80), GEM_SUBMIT of a command buffer written through the user mapping,
 * WAIT_FENCE, and the GPU's write read back through the user mapping. Then N submissions timed.
 *
 * No SDK: no headers, only the libSystem functions listed in libSystem.tbd beside this file.
 * Built by build.sh (clang -target arm64-apple-ios16.0, ld64.lld, ad-hoc signed).
 *
 *   drmtest [STEPS [N]]   stop after step STEPS (1 open, 2 version, 3 params+queue, 4 GEM_NEW+IOVA,
 *                         5 IOS_MMAP, 6 submit+wait, 7 the timed loop; default 7); N timed submissions
 *                         (default 1000). Run it on a terminal (ssh -t): every line is out before the next step.
 *
 * ioctl encoding: XNU's _IOWR (IOC_INOUT 0xc0000000 | size << 16 | 'd' << 8 | nr) for every
 * request, including those Linux encodes _IOW (WAIT_FENCE): XNU copies a request in only when
 * IOC_IN is set (see the 0126 banner).
 */
typedef unsigned char uint8_t;
typedef unsigned int uint32_t;
typedef int int32_t;
typedef unsigned long long uint64_t;
typedef long long int64_t;
typedef unsigned long size_t;

extern int open(const char *, int, ...);
extern int close(int);
extern int ioctl(int, unsigned long, ...);
extern int printf(const char *, ...);
extern void exit(int) __attribute__((noreturn));
extern uint64_t mach_absolute_time(void);
struct mach_timebase_info { uint32_t numer, denom; };
extern int mach_timebase_info(struct mach_timebase_info *);

#define O_RDWR 2
#define IOWR(nr, size) (0xc0000000ul | ((unsigned long)(size) & 0x1fffu) << 16 | 0x64u << 8 | (nr))

struct drm_version {
	int major, minor, patch;
	int pad;
	uint64_t name_len, name, date_len, date, desc_len, desc;
};
struct drm_msm_param { uint32_t pipe, param; uint64_t value; uint32_t len, pad; };
struct drm_msm_gem_new { uint64_t size; uint32_t flags, handle; };
struct drm_msm_gem_info { uint32_t handle, info; uint64_t value; uint32_t len, pad; };
struct drm_msm_timespec { int64_t sec, nsec; };
struct drm_msm_gem_submit_bo { uint32_t flags, handle; uint64_t presumed; };
struct drm_msm_gem_submit_cmd { uint32_t type, submit_idx, submit_offset, size, pad, nr_relocs; uint64_t relocs; };
struct drm_msm_gem_submit {
	uint32_t flags, fence, nr_bos, nr_cmds;
	uint64_t bos, cmds;
	int32_t fence_fd;
	uint32_t queueid;
	uint64_t in_syncobjs, out_syncobjs;
	uint32_t nr_in_syncobjs, nr_out_syncobjs, syncobj_stride, pad;
};
struct drm_msm_wait_fence { uint32_t fence, flags; struct drm_msm_timespec timeout; uint32_t queueid, pad; };
struct drm_msm_submitqueue { uint32_t flags, prio, id; };

#define NR_VERSION       0x00u
#define NR_GET_PARAM     0x40u
#define NR_GEM_NEW       0x42u
#define NR_GEM_INFO      0x43u
#define NR_GEM_SUBMIT    0x46u
#define NR_WAIT_FENCE    0x47u
#define NR_GEM_CPU_PREP  0x44u
#define NR_SUBMITQUEUE   0x4au
#define MSM_BO_WC        0x20000u
#define INFO_GET_IOVA    0x01u
#define INFO_IOS_MMAP    0x80u
#define SUBMIT_CMD_BUF   0x01u
#define BO_READ          0x01u
#define BO_WRITE         0x02u

static int fails;

static void
check(const char *what, int ok)
{
	printf("%-44s %s\n", what, ok ? "ok" : "FAIL");
	fails += !ok;
}

/* a6xx type-7 packet header: the parity bits make each field's popcount odd */
static uint32_t
parity(uint32_t v)
{
	v ^= v >> 16; v ^= v >> 8; v ^= v >> 4; v ^= v >> 2; v ^= v >> 1;
	return ~v & 1u;
}
static uint32_t
pkt7(uint32_t op, uint32_t cnt)
{
	return 0x70000000u | cnt | parity(cnt) << 15 | (op & 0x7fu) << 16 | parity(op) << 23;
}

static int fd;
static uint32_t steps = 7;
#define STEP(k, what) do { printf("-- step %d: %s\n", (k), (what)); if ((k) > steps) { printf("drmtest: stopped before step %d\n", (k)); exit(fails ? 1 : 0); } } while (0)

static int
gem_new(uint64_t size, uint32_t *handle, uint64_t *iova, volatile uint32_t **map, int with_map)
{
	struct drm_msm_gem_new gn = { size, MSM_BO_WC, 0 };
	struct drm_msm_gem_info gi;
	if (ioctl(fd, IOWR(NR_GEM_NEW, sizeof(gn)), &gn) != 0) {
		return -1;
	}
	*handle = gn.handle;
	gi = (struct drm_msm_gem_info){ gn.handle, INFO_GET_IOVA, 0, 0, 0 };
	if (ioctl(fd, IOWR(NR_GEM_INFO, sizeof(gi)), &gi) != 0) {
		return -2;
	}
	*iova = gi.value;
	if (!with_map) {
		return 0;
	}
	gi = (struct drm_msm_gem_info){ gn.handle, INFO_IOS_MMAP, 0, 0, 0 };
	if (ioctl(fd, IOWR(NR_GEM_INFO, sizeof(gi)), &gi) != 0 || gi.value == 0) {
		return -3;
	}
	*map = (volatile uint32_t *)(unsigned long)gi.value;
	return 0;
}

static int
submit(uint32_t queue, uint32_t ib, uint32_t dst, uint32_t ib_bytes, uint32_t *fence)
{
	struct drm_msm_gem_submit_bo bos[2] = { { BO_READ, ib, 0 }, { BO_WRITE, dst, 0 } };
	struct drm_msm_gem_submit_cmd cmd = { SUBMIT_CMD_BUF, 0, 0, ib_bytes, 0, 0, 0 };
	struct drm_msm_gem_submit s = { 0 };
	s.nr_bos = 2;
	s.nr_cmds = 1;
	s.bos = (uint64_t)(unsigned long)bos;
	s.cmds = (uint64_t)(unsigned long)&cmd;
	s.fence_fd = -1;
	s.queueid = queue;
	if (ioctl(fd, IOWR(NR_GEM_SUBMIT, sizeof(s)), &s) != 0) {
		return -1;
	}
	*fence = s.fence;
	return 0;
}

/* GEM_CPU_PREP: wait for the GPU to be done with the buffer; the kernel then takes its stale cache lines back */
struct drm_msm_gem_cpu_prep { uint32_t handle, op; struct drm_msm_timespec timeout; };
static int
cpu_prep(uint32_t handle)
{
	struct drm_msm_gem_cpu_prep cp = { handle, 0x01u /* MSM_PREP_READ */, { 0, 0 } };
	return ioctl(fd, IOWR(NR_GEM_CPU_PREP, sizeof(cp)), &cp);
}

static int
wait_fence(uint32_t queue, uint32_t fence)
{
	/* zero timeout = the kernel's default patience (0126 drm_ioctl_locked) */
	struct drm_msm_wait_fence wf = { fence, 0, { 0, 0 }, queue, 0 };
	return ioctl(fd, IOWR(NR_WAIT_FENCE, sizeof(wf)), &wf);
}

int
main(int argc, char **argv)
{
	char name[8] = { 0 };
	struct drm_version v = { 0 };
	struct drm_msm_param p;
	struct drm_msm_submitqueue q = { 0, 0, 0 };
	uint32_t ib, dst, fence = 0, n = 1000;
	uint64_t ib_iova, dst_iova, t0, t1, ns;
	volatile uint32_t *ibm, *dstm;
	struct mach_timebase_info tb;

	for (int a = 1; a < argc && a <= 2; a++) {
		uint32_t x = 0;
		for (const char *c = argv[a]; *c >= '0' && *c <= '9'; c++) {
			x = x * 10u + (uint32_t)(*c - '0');
		}
		if (a == 1) {
			steps = x;
		} else {
			n = x;
		}
	}
	STEP(1, "open");
	fd = open("/dev/dri/renderD128", O_RDWR);
	check("open /dev/dri/renderD128", fd >= 0);
	if (fd < 0) {
		exit(1);
	}
	STEP(2, "DRM_VERSION");
	v.name_len = sizeof(name) - 1;
	v.name = (uint64_t)(unsigned long)name;
	check("DRM_VERSION", ioctl(fd, IOWR(NR_VERSION, sizeof(v)), &v) == 0);
	printf("  driver \"%s\" %d.%d\n", name, v.major, v.minor);
	check("  name is msm", name[0] == 'm' && name[1] == 's' && name[2] == 'm');

	STEP(3, "GET_PARAM, SUBMITQUEUE_NEW");
	p = (struct drm_msm_param){ 0, 0x03u, 0, 0, 0 };   /* CHIP_ID */
	check("GET_PARAM CHIP_ID", ioctl(fd, IOWR(NR_GET_PARAM, sizeof(p)), &p) == 0 && p.value == 0x06020000ull);
	printf("  chip_id %#llx\n", p.value);
	p = (struct drm_msm_param){ 0, 0x02u, 0, 0, 0 };   /* GMEM_SIZE */
	check("GET_PARAM GMEM_SIZE", ioctl(fd, IOWR(NR_GET_PARAM, sizeof(p)), &p) == 0 && p.value == 0x80000ull);
	check("SUBMITQUEUE_NEW", ioctl(fd, IOWR(NR_SUBMITQUEUE, sizeof(q)), &q) == 0 && q.id != 0);

	STEP(4, "GEM_NEW + GET_IOVA");
	check("GEM_NEW + GET_IOVA (command buffer)", gem_new(4096, &ib, &ib_iova, &ibm, 0) == 0);
	check("GEM_NEW + GET_IOVA (target)", gem_new(4096, &dst, &dst_iova, &dstm, 0) == 0);
	printf("  ib handle %u iova %#llx; dst handle %u iova %#llx\n", ib, ib_iova, dst, dst_iova);
	STEP(5, "GEM_INFO IOS_MMAP");
	{
		struct drm_msm_gem_info gi = { ib, INFO_IOS_MMAP, 0, 0, 0 };
		check("IOS_MMAP (command buffer)", ioctl(fd, IOWR(NR_GEM_INFO, sizeof(gi)), &gi) == 0 && gi.value != 0);
		ibm = (volatile uint32_t *)(unsigned long)gi.value;
		gi = (struct drm_msm_gem_info){ dst, INFO_IOS_MMAP, 0, 0, 0 };
		check("IOS_MMAP (target)", ioctl(fd, IOWR(NR_GEM_INFO, sizeof(gi)), &gi) == 0 && gi.value != 0);
		dstm = (volatile uint32_t *)(unsigned long)gi.value;
	}
	if (fails) {
		exit(1);
	}
	printf("  maps: ib %p dst %p; dst reads %#x\n", (void *)ibm, (void *)dstm, dstm[0]);
	STEP(6, "GEM_SUBMIT + WAIT_FENCE");

	/* CP_MEM_WRITE (0x3d): the GPU writes 0x600dcafe into dst */
	dstm[0] = 0;
	ibm[0] = pkt7(0x3du, 3u);
	ibm[1] = (uint32_t)dst_iova;
	ibm[2] = (uint32_t)(dst_iova >> 32);
	ibm[3] = 0x600dcafeu;
	__asm__ volatile ("dsb sy" ::: "memory");
	check("GEM_SUBMIT", submit(q.id, ib, dst, 16u, &fence) == 0 && fence != 0);
	check("WAIT_FENCE", wait_fence(q.id, fence) == 0);
	check("GEM_CPU_PREP (target)", cpu_prep(dst) == 0);
	printf("  fence %u, dst reads %#x\n", fence, dstm[0]);
	check("THE GPU WROTE A USER BUFFER ON A USER'S COMMAND", dstm[0] == 0x600dcafeu);

	STEP(7, "timed submissions");
	/* N submissions back to back, each its own value, waited for at the end */
	mach_timebase_info(&tb);
	t0 = mach_absolute_time();
	for (uint32_t i = 1; i <= n; i++) {
		ibm[3] = 0x10000000u + i;
		__asm__ volatile ("dsb sy" ::: "memory");
		if (submit(q.id, ib, dst, 16u, &fence) != 0) {
			check("timed GEM_SUBMIT", 0);
			break;
		}
		if (wait_fence(q.id, fence) != 0) {   /* the IB is rewritten next round: wait for each */
			check("timed WAIT_FENCE", 0);
			break;
		}
	}
	t1 = mach_absolute_time();
	(void)cpu_prep(dst);
	ns = (t1 - t0) * tb.numer / tb.denom;
	printf("  %u submit+wait round trips in %llu us: %llu us each; last value %#x (want %#x)\n", n, ns / 1000,
	    n ? ns / 1000 / n : 0, dstm[0], 0x10000000u + n);
	check("timed submissions all landed", n == 0 || dstm[0] == 0x10000000u + n);

	close(fd);
	printf("%s\n", fails ? "drmtest: FAILED" : "drmtest: ALL OK");
	exit(fails ? 1 : 0);
}
