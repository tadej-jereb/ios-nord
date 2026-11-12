#pragma once
#include <stdint.h>

/*
 * The diag ladder. Rungs are compiled in cumulatively by DIAG_STAGE; the
 * default build (DIAG_STAGE=5) carries all five.
 *
 * Each rung prints its marker line to the panel and to the UFS ring *before*
 * it touches the block it probes, so a hang always names its own last rung.
 *
 * diag_run() returns 0 when no rung was compiled in (DIAG_STAGE=0), else it
 * parks and never returns.
 */
int diag_run(uintptr_t fdt);

/* Non-NULL while a rung is executing: current rung, for the panic screen. */
const char *diag_stage_name(void);

/* Called from secondary_entry (start.S) on the core that just came up. */
int diag_active(void);
void diag_secondary(uint64_t idx);
