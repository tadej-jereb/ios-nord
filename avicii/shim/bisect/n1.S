/*
 * Bisect rung 1: the absolute cheapest thing ABL can be asked to run.
 *
 * ARM64 Image header, then one branch, then an endless wfe. No stack, no
 * vectors, no BSS, no C, MMU off. If this does not park, the fault is in the
 * handoff itself (header geometry, entry address, EL/MMU state, or the DTB
 * ABL writes at tags_addr 0x100 running over the head of the image) - none of
 * the shim's own prologue is involved.
 *
 * Rung 1b is this same image packed with a 64 KiB DTB tail instead of the
 * 337 KiB board tree: it separates "an FDT tail at 0x100 overwrites the image
 * head" from "the tail's size does".
 */
	.section .text.head, "ax"
	.globl _head
_head:
	b	_start			/* code0 */
	.long	0			/* code1 */
	.quad	0			/* text_offset */
	.quad	_end			/* image_size (linked at 0) */
	.quad	0xa			/* flags: LE, 4K pages, place anywhere */
	.quad	0			/* res2 */
	.quad	0			/* res3 */
	.quad	0			/* res4 */
	.ascii	"ARM\x64"		/* magic */
	.long	0			/* res5 (PE offset) */

	.text
	.globl _start
_start:
	wfe
	b	_start
