#pragma once

/*
 * Persistent one-line log for the diag ladder.
 *
 * Every rung writes its marker line here *before* it touches the block it is
 * about to probe, so a hang names its own last step even when the screen is
 * gone. The record is a plain text line in a byte ring; the ring lives in the
 * last 1024 blocks of the userdata partition and carries the SWEETLOG header
 * the upstream ios-sweet tooling already understands, so
 * `tooling/42-log-pull.sh` reads it unchanged:
 *
 *   block N-1024 : header  "SWEETLOG", u32 ver, u32 ring_bytes, u64 total, u64 seq
 *   block N-1023 : ring, byte n of the log at ring offset n % ring_bytes
 *
 * A line is flushed with WRITE(10) + SYNCHRONIZE CACHE and the header is
 * updated, so the newest bytes survive a warm reset. Nothing outside the
 * userdata partition is ever written.
 */
int dlog_init(void);		/* 0 = logging on; else a code (see diaglog.c) */
int dlog_warn(void);		/* non-fatal code from the last dlog_init(): 4 = hdr write/sync lied, 5 = hdr read-back mismatched */
int dlog_on(void);
void dlog_line(char kind, const char *text);
void dlog_off(const char *why);
