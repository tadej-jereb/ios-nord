#!/bin/bash
# sysroot-fixups.sh — gaps found by the Mesa build, applied on top of mksysroot.sh output.
#   tooling/gpu/sysroot-fixups.sh SYSROOT OSS_SRC_DIR
# OSS_SRC_DIR holds the unpacked apple-oss-distributions tarballs mksysroot.sh pins
# (libplatform-375.120.2, dyld-1042.1). Idempotent. Nothing here is Apple binary code:
# two headers are copied from APSL-2.0 trees, two declaration-only stubs are written.
set -euo pipefail
sr=$1; oss=$2
inc=$sr/usr/include

# 1. libSystem.B.tbd: gen_tbd.py drops 20 plain libc names (_strlen, _memcmp, ...) and keeps
#    their __platform_ twins, so no C++ dylib links. Add the partner of every __platform_ name.
python3 -I - "$sr/usr/lib/libSystem.B.tbd" <<'EOF'
import re, sys
p = sys.argv[1]; s = open(p).read()
m = re.search(r'symbols: \[(.*?)\]', s, re.S)
syms = {x.strip() for x in m.group(1).split(',') if x.strip()}
n0 = len(syms)
syms |= {'_' + n[len('__platform_'):] for n in syms if n.startswith('__platform_')}
syms.add('_memcpy')   # arm64 memcpy is memmove's alias in libsystem_platform; no __platform_ twin
open(p, 'w').write(s[:m.start(1)] + ", ".join(sorted(syms)) + s[m.end(1):])
print(f"libSystem.B.tbd: {n0} -> {len(syms)} symbols")
EOF

# 2. setjmp.h (libplatform ships it; arm64 _JBLEN is defined inline).
install -m 644 "$oss"/libplatform-libplatform-375.120.2/include/setjmp.h "$inc/setjmp.h"

# 3. mach-o/dyld.h (+ its utils header) from dyld.
install -m 644 "$oss"/dyld-dyld-1042.1/include/mach-o/dyld.h "$inc/mach-o/dyld.h"
for h in dyld_images.h utils.h; do
	[ -f "$oss/dyld-dyld-1042.1/include/mach-o/$h" ] && install -m 644 "$oss/dyld-dyld-1042.1/include/mach-o/$h" "$inc/mach-o/$h"
done

# 4. mach/mach_vm.h: MIG output in the SDK; no MIG on this host, so declare the routines
#    (signatures from xnu osfmk/mach/mach_vm.defs; all exported by libSystem.B.tbd).
cat >"$inc/mach/mach_vm.h" <<'EOF'
/* mach/mach_vm.h -- synthesized declaration-only stub (sysroot-fixups.sh).
 * Signatures follow xnu osfmk/mach/mach_vm.defs; no MIG was available on the build host. */
#ifndef _mach_vm_user_
#define _mach_vm_user_
#include <mach/mach_types.h>
#include <mach/vm_types.h>
#include <mach/vm_prot.h>
#include <mach/vm_inherit.h>
__BEGIN_DECLS
kern_return_t mach_vm_allocate(vm_map_t target, mach_vm_address_t *address, mach_vm_size_t size, int flags);
kern_return_t mach_vm_deallocate(vm_map_t target, mach_vm_address_t address, mach_vm_size_t size);
kern_return_t mach_vm_protect(vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size,
    boolean_t set_maximum, vm_prot_t new_protection);
kern_return_t mach_vm_map(vm_map_t target_task, mach_vm_address_t *address, mach_vm_size_t size,
    mach_vm_offset_t mask, int flags, mem_entry_name_port_t object, memory_object_offset_t offset,
    boolean_t copy, vm_prot_t cur_protection, vm_prot_t max_protection, vm_inherit_t inheritance);
kern_return_t mach_make_memory_entry_64(vm_map_t target_task, memory_object_size_t *size,
    memory_object_offset_t offset, vm_prot_t permission, mach_port_t *object_handle,
    mem_entry_name_port_t parent_entry);
__END_DECLS
#endif
EOF

# 5. mach/mach_host.h stub lacks host_statistics64 (Mesa util/os_misc.c).
if ! grep -q host_statistics64 "$inc/mach/mach_host.h"; then
	sed -i 's|^__END_DECLS|kern_return_t host_statistics64(host_t host_priv, host_flavor_t flavor,\n    host_info64_t host_info64_out, mach_msg_type_number_t *host_info64_outCnt);\n&|' "$inc/mach/mach_host.h"
fi
# 6. mach_host_self() (mach_init.h): SDK users of mach_host.h get it transitively.
grep -q 'mach/mach_init.h' "$inc/mach/mach_host.h" ||
	sed -i 's|^#include <mach/clock_types.h>|&\n#include <mach/mach_init.h>|' "$inc/mach/mach_host.h"

# 7. netinet/ and netinet6/in6.h (arpa/inet.h needs netinet/in.h), straight from xnu bsd/.
mkdir -p "$inc/netinet" "$inc/netinet6"
install -m 644 "$oss"/xnu-xnu-8796.141.3/bsd/netinet/*.h "$inc/netinet/"
install -m 644 "$oss"/xnu-xnu-8796.141.3/bsd/netinet6/in6.h "$inc/netinet6/"
mkdir -p "$inc/net"
install -m 644 "$oss"/xnu-xnu-8796.141.3/bsd/net/net_kev.h "$inc/net/"

# 8. libc++.1.dylib re-exports libc++abi.dylib (operator new, __cxa_*); the generated stub lost
#    that, so a plain clang++ -shared link (implicit -lc++) left them undefined.
grep -q reexported-libraries "$sr/usr/lib/libc++.1.tbd" ||
	sed -i "s|^exports:|reexported-libraries:\n  - targets:         [ arm64-ios ]\n    libraries:       [ '/usr/lib/libc++abi.dylib' ]\n&|" "$sr/usr/lib/libc++.1.tbd"

echo "sysroot fixups applied to $sr"
