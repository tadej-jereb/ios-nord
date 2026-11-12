#pragma once
#include <stdint.h>

/* Read a u32/u64 (cell-size agnostic) property of /chosen. Returns 0 if absent. */
int fdt_chosen_u64(uintptr_t fdt, const char *prop, uint64_t *out);

/*
 * Visit the reg property of every node exactly two levels down (i.e. every
 * device under a top-level bus, every child of /reserved-memory). The callback
 * gets the parent name, the node name and one base/size pair per reg entry,
 * already decoded with the root #address-cells/#size-cells. Return 0 to stop
 * the walk, 1 to continue.
 *
 * Bounded by the tree's totalsize, so a truncated or wrong tree ends the walk
 * instead of running off into unreserved memory. Returns the number of reg
 * entries seen, or -1 if the tree is not a valid FDT.
 */
typedef int (*fdt_reg_cb)(void *ctx, const char *parent, const char *name,
			  uint64_t base, uint64_t size);
int fdt_reg_walk(uintptr_t fdt, fdt_reg_cb cb, void *ctx);
