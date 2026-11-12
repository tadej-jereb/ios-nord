#pragma once
#include <stdint.h>

/* Milestone 5 probe: register dump + read-only GPT/partition walk. */
void test_ufs(void);

/* Shared host access. Every one of these returns 0 on success. */
uint32_t ufs_takeover(void);		/* 10 no host, 11 busy, 12 list not taken, 13 TUR */
uint32_t ufs_read(uint32_t lba, uint32_t count, void *buf);		/* READ(10), 4K blocks */
uint32_t ufs_write(uint32_t lba, uint32_t count, const void *buf);	/* WRITE(10) */
uint32_t ufs_sync(void);		/* SYNCHRONIZE CACHE(10) */
uint32_t ufs_part_find(const char *name, uint64_t *first, uint64_t *last);	/* 20/21/22 */
