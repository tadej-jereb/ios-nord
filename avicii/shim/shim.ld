ENTRY(_head)
SECTIONS
{
	. = 0;
	/* ABL enters at the image start, so the header stub lives at 0 and branches to
	 * the body, which stock-shape places 0x80000 in (text_offset). */
	.text.head : { *(.text.head) }
	. = 0x80000;
	.text : { *(.text*) }
	.rodata : { *(.rodata*) }
	.data : { *(.data*) }
	. = ALIGN(16);
	_bss_start = .;
	.bss : { *(.bss*) *(COMMON) }
	. = ALIGN(16);
	_bss_end = .;
	. += 0x8000;
	. = ALIGN(16);
	_stack_top = .;
	. = ALIGN(4096);
	_sec_stacks = .;
	. += 8 * 0x1000;
	_end = .;
	/DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
