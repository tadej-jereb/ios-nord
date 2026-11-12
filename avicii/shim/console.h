#pragma once
#include <stdint.h>

#define FB_BASE		0xa0000000UL	/* avicii cont_splash_region (35 MiB) */
#define FB_W		1080
#define FB_H		2400
/* a8r8g8b8, one row is exactly the visible width: nothing pads an ABL splash
 * row (1080*4 = 4320 is already 32 B aligned), exactly as in every other port
 * of this tree. 4800 ("1200 px padded") shears every scanline by 120 px. */
#define FB_STRIDE	(FB_W * 4)

#define RED	0xffff0000U
#define BLUE	0xff0000a0U
#define WHITE	0xffffffffU
#define YELLOW	0xffffff00U
#define GREEN	0xff00ff00U
#define MAGENTA	0xffff00ffU

extern volatile uint32_t *con_fb;

void con_clear(uint32_t bg);
void con_skip(void);
void con_str(const char *label, const char *s);
void con_hex(const char *label, uint64_t v);
/* label, then "a=xxxxxxxx b=xxxxxxxx" style pairs of 32-bit values */
void con_hex2(const char *label, const char *a, uint32_t va, const char *b, uint32_t vb);

/* ufs.c partition-name compare (see console.c); clang calls this */
int strcmp(const char *a, const char *b);
