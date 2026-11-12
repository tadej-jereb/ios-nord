#pragma once
#include <stdint.h>

/* Read a u32/u64 (cell-size agnostic) property of /chosen. Returns 0 if absent. */
int fdt_chosen_u64(uintptr_t fdt, const char *prop, uint64_t *out);

/*
 * Walk every reg property in the tree, whatever its depth. The callback gets
 * the parent node's name ("" for a top-level node) and the node's own name,
 * plus one base/size pair per reg entry, decoded with the root
 * #address-cells/#size-cells. Return 0 to stop the walk, 1 to continue.
 *
 * Bounded by the tree's totalsize, so a truncated or wrong tree ends the walk
 * instead of running off into unreserved memory. Returns the number of reg
 * entries seen, or -1 if the tree is not a valid FDT.
 */
typedef int (*fdt_reg_cb)(void *ctx, const char *parent, const char *name,
			  uint64_t base, uint64_t size);
int fdt_reg_walk(uintptr_t fdt, fdt_reg_cb cb, void *ctx);
