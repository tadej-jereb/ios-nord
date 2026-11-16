# Perf lane F — battery gauge and charger

Read `perf-shared.md` first. **Owns:** `docs/perf-research/F-battery-gauge.md`.

**Question:** `SweetBattery.cpp` (in the series; see patch `0062` and later) reports a battery to
iOS. What does it read, how accurate is it, and what would a real fuel gauge, charge status and
charge-current reading take on the PM7250B?

Determine:
1. Today: what `SweetBattery.cpp` reads (SPMI addresses via `sweet_spmi.c`), what it publishes on
   `IOPMPowerSource` / `AppleSmartBattery`-style properties, and what iOS shows.
2. Vendor: the PM7250B QPNP QG (qgauge) and charger (`qcom,qpnp-smb5`) nodes in the live dts
   (SPMI base addresses, IRQs, `qcom,battery-data` profile for this phone's battery), and the vendor
   `drivers/power/supply/qcom/qpnp-qg.c`, `qg-*.c`, `qpnp-smb5.c`, `smb5-lib.c`: which registers give
   voltage, current, SoC, temperature, charge state, and USB input current limit.
3. Which of those are plain SPMI register reads our kernel can do safely, and which need the QG's
   algorithm (OCV tables, ESR) — propose a simple, honest estimate (e.g. voltage-based SoC with the
   battery profile's OCV table) if the full QG is too much.
4. What iOS's `powerd` / battery UI needs (property names, update cadence, notifications) — cite
   our existing patch or open-source IOKit headers, not Apple binaries.
5. Plan + measurement: compare the reported % with Android's on the same charge level; read
   current to measure idle drain (lanes B and G depend on this number — give them a sysctl).
