/*
 * Rungs 2..5 link no C: the vector handler and the PSCI secondary entry only
 * have to exist to satisfy start.S, and both park. An exception that parks is
 * still a pass for the rung's own layer (the layer after it adds the real
 * handler), and it keeps the panel out of the picture.
 */
	.text
	.globl exc_handler
exc_handler:
	wfe
	b	exc_handler

	.globl secondary_main
secondary_main:
	wfe
	b	secondary_main
