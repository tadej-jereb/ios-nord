# ios-avicii

Bring-up tree for running Apple's open-source XNU (xnu-8796, iOS 16 generation) plus the
unmodified iOS 16.7.16 iPhone X userland on a OnePlus Nord (`avicii`, SM7250).

Derived from `dipa-studio/ios-sweet` (Redmi Note 10 Pro, SM7150) — same ARMv8.2 A76/A55
4KB-16K-granule platform class. `docs/fajita-PORTING.md` is the completed OnePlus 6T
(SDM845) port of the same tree and the reference for OnePlus bootloader behaviour.

Status: **host preparation**. Bootloader unlock 2026-11-12, no device work before that.

Start at `AGENTS.md`, then `docs/STATUS.md`.

Experimental, security-off bring-up. `userdata` is destroyed. Widevine drops to L3.
