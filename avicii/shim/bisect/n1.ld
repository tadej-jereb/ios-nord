/* Rung 1 only: header + branch + park. Nothing to place but .text. */
ENTRY(_head)
SECTIONS
{
	. = 0;
	.text : { *(.text.head) *(.text*) }
	. = ALIGN(64);
	_end = .;
	/DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
