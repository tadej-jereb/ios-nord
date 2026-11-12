#!/usr/bin/python3
"""Build the avicii XNU patch series from the two read-only reference trees.

Sources (never modified):
  refs/dipa-studio-ios-sweet/xnu/patches   - the base series (SM7150, Kryo 470)
  refs/edi194-ios-fajita/xnu/patches       - OnePlus 6T additions the port proved

Everything SoC-generic is copied byte-exact. Only the patches carrying sweet
numbers are rewritten, and every rewrite is listed in ADAPT with the number of
occurrences it must hit, so a silent miss is a hard error instead of a patch
that applies and boots the wrong panel.

Hunk headers are recounted after rewriting (git apply trusts the declared
counts and silently drops trailing body lines when a count is short).

Usage:  xnu-avicii/tools/make-series.py [--check]
        --check  fail instead of writing when the working tree already differs
"""

import hashlib
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SWEET = ROOT / "refs/dipa-studio-ios-sweet/xnu/patches"
FAJITA = ROOT / "refs/edi194-ios-fajita/xnu/patches"
OUT = ROOT / "xnu-avicii/patches"

# (basename, source tree, class)
#   V = verbatim copy (SoC-generic or proven board-independent by the fajita port)
#   A = adapted (numbers carry the SM7150/sweet hardware)
#   F = fajita-only addition carried because it is SoC-generic
MANIFEST = [
    ("0001-new-clang-drop-removed-auto-var-init-flag.patch", "sweet", "V"),
    ("0002-new-clang-backport-UIO_STACKBUF.patch", "sweet", "V"),
    ("0003-sweet-framebuffer-serial-console.patch", "sweet", "V"),
    ("0004-sweet-machine-config.patch", "sweet", "A"),
    ("0005-non-pac-build-fixes.patch", "sweet", "V"),
    ("0006-sweet-master-config-open-source-asm-pmap.patch", "sweet", "V"),
    ("0007-sweet-stub-apple-internal-headers.patch", "sweet", "V"),
    ("0008-sweet-fill-closed-lib-gaps-kpc-stub.patch", "sweet", "V"),
    ("0009-sweet-drop-apple-soc-only-exports.patch", "sweet", "V"),
    ("0010-sweet-early-framebuffer-debug.patch", "sweet", "A"),
    ("0011-sweet-physmap-alignment-padding.patch", "sweet", "V"),
    ("0012-sweet-keep-debug-console-after-ttbr0.patch", "sweet", "A"),
    ("0013-sweet-kmem-rng-without-corecrypto.patch", "sweet", "V"),
    ("0014-sweet-kernel-hmac-prng.patch", "sweet", "V"),
    ("0015-sweet-unavailable-trust-cache-runtime.patch", "sweet", "V"),
    ("0016-sweet-device-tree-platform-expert.patch", "sweet", "V"),
    ("0017-sweet-device-tree-virtual-timer-irq.patch", "sweet", "V"),
    ("0018-sweet-boot-cpu-driver.patch", "sweet", "A"),
    ("0019-stage-libpthread.sh", "sweet", "V"),
    ("0019-sweet-builtin-pthread.patch", "sweet", "V"),
    ("0020-stage-bearssl.sh", "sweet", "V"),
    ("0020-sweet-portable-aes-cbc.patch", "sweet", "V"),
    ("0021-sweet-mockfs-ramdisk-root.patch", "sweet", "V"),
    ("0022-sweet-ramdisk-root-without-iomedia.patch", "sweet", "V"),
    ("0023-sweet-builtin-sha256-for-libkern.patch", "sweet", "V"),
    ("0024-sweet-mockfs-virtual-ramdisk-io.patch", "sweet", "V"),
    ("0025-sweet-builtin-amfi-no-entitlements.patch", "sweet", "V"),
    ("0026-stage-hfs.sh", "sweet", "V"),
    ("0026-sweet-builtin-hfs.patch", "sweet", "V"),
    ("0027-sweet-bearssl-md5.patch", "sweet", "V"),
    ("0028-sweet-ufs-root-device.patch", "sweet", "V"),
    ("0029-sweet-unsealed-root-volume.patch", "sweet", "V"),
    ("0030-sweet-ufs-writes.patch", "sweet", "V"),
    ("0031-sweet-read-write-root.patch", "sweet", "V"),
    ("0032-sweet-bearssl-sha1.patch", "sweet", "V"),
    ("0033-sweet-bearssl-sha384-sha512.patch", "sweet", "V"),
    ("0034-sweet-ufs-dma-above-4g.patch", "sweet", "V"),
    ("0035-sweet-amfi-entitlements-platform-binaries.patch", "sweet", "V"),
    ("0036-sweet-amfi-cs-signed.patch", "sweet", "V"),
    ("0037-sweet-config-bindfs.patch", "sweet", "V"),
    ("0038-sweet-applekeystore.patch", "sweet", "A"),
    ("0039-sweet-coredump-default-off.patch", "sweet", "V"),
    ("0040-sweet-iowatchdog.patch", "sweet", "V"),
    ("0041-sweet-hfs-link-notes.patch", "sweet", "V"),
    ("0042-sweet-short-exec-log.patch", "sweet", "V"),
    ("0043-sweet-console-crash-log.patch", "sweet", "V"),
    ("0044-sweet-crash-log-reason.patch", "sweet", "V"),
    ("0045-sweet-iowatchdog-pmu-primary.patch", "sweet", "V"),
    ("0046-sweet-iosurface-iomfb.patch", "sweet", "V"),
    ("0047-sweet-persistent-console-log.patch", "sweet", "V"),
    ("0048-sweet-devnull-tee.patch", "sweet", "V"),
    ("0049-sweet-iokit-trace.patch", "sweet", "V"),
    ("0050-sweet-sandbox-policy.patch", "sweet", "V"),
    ("0051-sweet-crash-heap-strings.patch", "sweet", "V"),
    ("0052-sweet-hfs-rename-swap.patch", "sweet", "V"),
    ("0053-sweet-crash-scan-springboard.patch", "sweet", "V"),
    ("0054-sweet-process-sampler.patch", "sweet", "V"),
    ("0055-sweet-aks-ext-state-sampler-depth.patch", "sweet", "V"),
    ("0056-sweet-fb-throttled-present.patch", "sweet", "V"),
    ("0057-sweet-no-ext-resolver.patch", "sweet", "V"),
    ("0058-sweet-hid-event-services.patch", "sweet", "V"),
    ("0059-sweet-iphone-identity.patch", "sweet", "V"),
    ("0060-sweet-keys-touch-drivers.patch", "sweet", "A"),
    ("0061-sweet-iphone-x-display-size.patch", "sweet", "V"),
    ("0062-sweet-touch-power-battery.patch", "sweet", "A"),
    ("0063-sweet-goodix-geni-packing.patch", "sweet", "A"),
    ("0064-sweet-priv-work-interval.patch", "sweet", "V"),
    ("0065-sweet-smp-psci.patch", "sweet", "V"),
    ("0066-sweet-crash-fault-region.patch", "sweet", "V"),
    ("0067-sweet-console-mute.patch", "sweet", "V"),
    ("0068-sweet-surface-lookup-cached.patch", "sweet", "V"),
    ("0069-sweet-ufs-faster.patch", "sweet", "V"),
    ("0070-sweet-pid-hibernate.patch", "sweet", "V"),
    ("0071-sweet-touch-edge.patch", "sweet", "V"),
    ("0072-sweet-usb-probe.patch", "sweet", "V"),
    ("0073-sweet-usb-device-ep0.patch", "sweet", "V"),
    ("0074-sweet-usb-vbus-override.patch", "sweet", "V"),
    ("0075-sweet-usb-ecm.patch", "sweet", "V"),
    ("0076-sweet-usb-rx-mbuf.patch", "sweet", "V"),
    ("0077-sweet-usb-live-log.patch", "sweet", "V"),
    ("0078-sweet-smp-8-cores.patch", "sweet", "V"),
    ("0079-sweet-display-power.patch", "sweet", "V"),
    ("0080-sweet-net-trace.patch", "sweet", "V"),
    ("0081-sweet-usb-link-state.patch", "sweet", "V"),
    # --- fajita additions carried: generic, and the fajita port proved each one ---
    ("0083-fajita-console-only.patch", "fajita", "F"),
    ("0084-fajita-panel-console.patch", "fajita", "A"),
    ("0085-fajita-sync-console.patch", "fajita", "F"),
    ("0086-fajita-cpu-match.patch", "fajita", "A"),
    ("0094-fajita-panic-log.patch", "fajita", "F"),
]

# basename -> [(old, new, expected_occurrences), ...]
ADAPT = {
    "0004-sweet-machine-config.patch": [
        ('* Board config for the Redmi Note 10 Pro ("sweet", Qualcomm SM7150 /',
         '* Board config for the OnePlus Nord ("avicii", Qualcomm SM7250 /', 1),
        ('* Snapdragon 732G): Kryo 470 = Cortex-A76 + Cortex-A55, ARMv8.2, no PAC.',
         '* lito): Kryo 475 = Cortex-A76 + Cortex-A55, ARMv8.2, no PAC.', 1),
        ('Qualcomm Kryo 470: Cortex-A76', 'Qualcomm Kryo 475: Cortex-A76', 1),
        ("# sweet's Cortex-A76/A55 have no pointer authentication: stay plain arm64",
         "# Kryo 475 (A76/A55) has no pointer authentication: stay plain arm64", 1),
    ],
    # 0x9c000000 -> 0xa0000000 is the whole avicii splash delta. The FB block is
    # 35 MiB at a fresh 32 MiB-aligned base (CONSTANTS §6); the 20 MiB offset and
    # fajita's 0x9d400000 arithmetic do not carry over. Stride 4800 is the ADT
    # value the shim publishes (UNVERIFIED on the panel, see CONSTANTS §6).
    "0010-sweet-early-framebuffer-debug.patch": [
        ('0x9c000000', '0xa0000000', 3),
        ('2368 * 4320', '2368 * 4800', 1),
        ('#define EARLY_STRIDE (4320u / 4)', '#define EARLY_STRIDE (4800u / 4)', 1),
        ('Redmi Note 10 Pro bootstrap console', 'avicii bootstrap console', 1),
    ],
    "0012-sweet-keep-debug-console-after-ttbr0.patch": [
        ('0x9c000000', '0xa0000000', 3),
        # 0012 quotes 0010's file header; it must match the adapted 0010.
        ('Redmi Note 10 Pro bootstrap console', 'avicii bootstrap console', 1),
        ('#define EARLY_STRIDE (4320u / 4)', '#define EARLY_STRIDE (4800u / 4)', 1),
    ],
    "0018-sweet-boot-cpu-driver.patch": [
        ('qcom,kryo470', 'qcom,kryo475', 1),
    ],
    "0038-sweet-applekeystore.patch": [
        ('qcom,kryo470', 'qcom,kryo475', 1),
    ],
    # Touch: same protocol, different silicon. GT9886 has no Yellowstone quirks,
    # so the chip-id compare and the SE/clock numbers change; the reset/IRQ pins
    # (TLMM 8/9) and the 0x5d address are already right for avicii.
    "0060-sweet-keys-touch-drivers.patch": [
        (' * SWEET SE7 FIFO I2C / GT9896 Yellowstone / Focaltech 54:52 bring-up.',
         ' * SWEET SE7 FIFO I2C / GT9886 (GT885) / Focaltech 54:52 bring-up.', 1),
        (" * zero to GT9896's event status after reading a report. See hw-report.md.",
         " * zero to GT9886's event status after reading a report. See hw-report.md.", 1),
        ('#define TOUCH_SE_PA      0x00a84000u',
         '#define TOUCH_SE_PA      0x00984000u /* lito qupv3_se7 = i2c4 */', 1),
        ('#define TOUCH_NORTH_PA   0x03900000u /* DT TLMM + NORTH (0x500000) */',
         '#define TOUCH_NORTH_PA   0x0f000000u /* lito TLMM: one flat window */', 1),
        ('#define TOUCH_GCC_VOTE   0x5200cu',
         '#define TOUCH_GCC_VOTE   0x52008u /* wrap1 S1 branch enable */', 1),
        ('#define TOUCH_RCG       0x18148u    /* wrapper1 LOCAL S1 = global SE7 */',
         '#define TOUCH_RCG       0x18140u    /* wrapper1 LOCAL S1 = global SE7 */', 1),
        ("bool goodix = !ge && gid[0] == '9' && gid[1] == '8' && gid[2] == '9' && gid[3] == '6';",
         "bool goodix = !ge && gid[0] == '9' && gid[1] == '8' && gid[2] == '8' && gid[3] == '6';", 1),
        ('    goodix ? "GT9896 Yellowstone" : "Focaltech 54:52", st.irq_hint);',
         '    goodix ? "GT9886" : "Focaltech 54:52", st.irq_hint);', 1),
    ],
    # RPMh: lito keeps the DRV at 0x18200000 (not sweet's 0x18220000) and has no
    # PM6150L: the touch 1.8 V is pm8150_l13 and the cmd-db lives in the live
    # reserved region at 0x80860000 (CONSTANTS §4, live FDT qcom,cmd-db node).
    "0062-sweet-touch-power-battery.patch": [
        ('#define RH_RSC_PA       0x18220000u', '#define RH_RSC_PA       0x18200000u', 1),
        ('#define RH_TCS_PA       0x18220d00u', '#define RH_TCS_PA       0x18200d00u', 1),
        ('#define RH_DICT_PA      0x0c3f000c',
         '#define RH_DICT_PA      0x80860000u /* live FDT qcom,cmd-db */', 1),
        ('sweet_rpmh_vreg_enable("ldoc11", 3200)', 'sweet_rpmh_vreg_enable("ldo13", 3008)', 1),
        ('Requires ABL-loaded GENI I2C firmware; votes L11C through sweet_rpmh.c.',
         'Requires ABL-loaded GENI I2C firmware; votes L13 through sweet_rpmh.c.', 1),
        ('voting L11C through RPMh', 'voting L13 through RPMh', 1),
        ('L11C RPMh enable failed', 'L13 RPMh enable failed', 1),
        ('SWEET PM6150L L11C bring-up', 'SWEET PM8150 L13 bring-up', 1),
        # context lines quoting 0060's file header, which 0060's rules changed
        (' * SWEET SE7 FIFO I2C / GT9896 Yellowstone / Focaltech 54:52 bring-up.',
         ' * SWEET SE7 FIFO I2C / GT9886 (GT885) / Focaltech 54:52 bring-up.', 1),
        (" * zero to GT9896's event status after reading a report. See hw-report.md.",
         " * zero to GT9886's event status after reading a report. See hw-report.md.", 1),
        ('Vendor GT9896 dev_confirm', 'Vendor GT9886 dev_confirm', 1),
    ],
    "0063-sweet-goodix-geni-packing.patch": [
        # context quoting 0062's output
        (' * Requires ABL-loaded GENI I2C firmware; votes L11C through sweet_rpmh.c.',
         ' * Requires ABL-loaded GENI I2C firmware; votes L13 through sweet_rpmh.c.', 1),
        ("- * zero to GT9896's event status after reading a report. See hw-report.md.",
         "- * zero to GT9886's event status after reading a report. See hw-report.md.", 1),
        ("+ * zero to GT9896's event status after reading a report. See touch2/report.md.",
         "+ * zero to GT9886's event status after reading a report. See touch2/report.md.", 1),
        ('+/* GT9896 is Yellowstone in Xiaomi sweet-r-oss, not the Berlin protocol. */',
         '+/* GT9886 shares the 0x5d Goodix protocol; no Yellowstone quirks. */', 1),
        (' * not a second accepted GT9896 identity.', ' * not a second accepted GT9886 identity.', 1),
        ("\tbool goodix = !ge && gid[0] == '9' && gid[1] == '8' && gid[2] == '9' && gid[3] == '6'",
         "\tbool goodix = !ge && gid[0] == '9' && gid[1] == '8' && gid[2] == '8' && gid[3] == '6'", 1),
    ],
    "0084-fajita-panel-console.patch": [
        ('0x9d400000', '0xa0000000', 1),
    ],
    "0086-fajita-cpu-match.patch": [
        # 0018/0038 already set the match string; both sides of this hunk agree.
        ("'IONameMatch'     = 'qcom,kryo470';", "'IONameMatch'     = 'qcom,kryo475';", 1),
        ("'IONameMatch'     = 'qcom,kryo385';", "'IONameMatch'     = 'qcom,kryo475';", 1),
        ('/* FAJITA: the ADT says the truth (SDM845 = Kryo 385); matching the sweet',
         '/* AVICII: the ADT says the truth (SM7250 = Kryo 475); matching the sweet', 1),
    ],
}

# Keys: sweet polls one PM6150L GPIO block for both volume keys. avicii has the
# volume-up on PM8150L GPIO5 and volume-down on PM7250B GPIO3, so the register
# offsets and the PPIDs fork. Both PPIDs are UNVERIFIED (no PMIC datasheet
# access); the driver prints the resolved APIDs so one boot settles them.
KEYS_ADAPT = [
    ("""#define KEYS_GPIO_RT     0xc110u""",
     """\
#define KEYS_VOLUP_RT    0xc510u   /* PM8150L SID 4 gpio5 rt status */
#define KEYS_VOLDN_RT    0xc310u   /* PM7250B SID 2 gpio3 rt status */"""),
    ("""static uint16_t keys_pon_apid = KEYS_NO_APID, keys_gpio_apid = KEYS_NO_APID;""",
     """\
static uint16_t keys_pon_apid = KEYS_NO_APID, keys_volup_apid = KEYS_NO_APID,
    keys_voldn_apid = KEYS_NO_APID;"""),
    ("""\t\tuint8_t pon = 0, gpio = 0;
\t\tbool pok = keys_read(keys_pon_apid, KEYS_PON_RT, &pon);
\t\tbool gok = keys_read(keys_gpio_apid, KEYS_GPIO_RT, &gpio);
\t\tint now[3] = {!!(pon & 1u), !(gpio & 1u), !!(pon & 2u)};""",
     """\
\t\tuint8_t pon = 0, up = 0, dn = 0;
\t\tbool pok = keys_read(keys_pon_apid, KEYS_PON_RT, &pon);
\t\tbool uok = keys_read(keys_volup_apid, KEYS_VOLUP_RT, &up);
\t\tbool dok = keys_read(keys_voldn_apid, KEYS_VOLDN_RT, &dn);
\t\tbool gok = uok && dok;
\t\tint now[3] = {!!(pon & 1u), !(up & 1u), !(dn & 1u)};"""),
    ("""\t\t\t\tprintf("SWEET KEYS: key=%d down=%d pon=%#x gpio4:c110=%#x\\n",
\t\t\t\t    k, state[k], pon, gpio);""",
     """\
\t\t\t\tprintf("SWEET KEYS: key=%d down=%d pon=%#x up=%#x dn=%#x\\n",
\t\t\t\t    k, state[k], pon, up, dn);"""),
    ("""\tkeys_pon_apid = keys_find_apid(0x008, count);
\tkeys_gpio_apid = keys_find_apid(0x4c1, count);
\tuint8_t pon = 0, gpio = 0, mode = 0, en = 0, subtype = 0;
\tbool pok = keys_read(keys_pon_apid, KEYS_PON_RT, &pon);
\tbool gok = keys_read(keys_gpio_apid, KEYS_GPIO_RT, &gpio);
\tbool mok = keys_read(keys_gpio_apid, 0xc140, &mode);
\tbool eok = keys_read(keys_gpio_apid, 0xc146, &en);
\tbool sok = keys_read(keys_gpio_apid, 0xc105, &subtype);
\tprintf("SWEET KEYS: arb=%#x apids=%u pon-apid=%u gpio4-apid=%u pon=%#x/%d gpio=%#x/%d mode=%#x/%d en=%#x/%d subtype=%#x/%d\\n",
\t    keys_version, count, keys_pon_apid, keys_gpio_apid,
\t    pon, pok, gpio, gok, mode, mok, en, eok, subtype, sok);""",
     """\
\tkeys_pon_apid = keys_find_apid(0x008, count);
\t/* UNVERIFIED PPIDs: PM8150L / PM7250B GPIO, derived from the PM6150L map. */
\tkeys_volup_apid = keys_find_apid(0x4c1, count);
\tkeys_voldn_apid = keys_find_apid(0x4b1, count);
\tuint8_t pon = 0, up = 0, dn = 0, mode = 0, en = 0, subtype = 0;
\tbool pok = keys_read(keys_pon_apid, KEYS_PON_RT, &pon);
\tbool uok = keys_read(keys_volup_apid, KEYS_VOLUP_RT, &up);
\tbool dok = keys_read(keys_voldn_apid, KEYS_VOLDN_RT, &dn);
\tbool gok = uok && dok;
\tbool mok = keys_read(keys_volup_apid, 0xc540, &mode);
\tbool eok = keys_read(keys_volup_apid, 0xc546, &en);
\tbool sok = keys_read(keys_volup_apid, 0xc505, &subtype);
\tprintf("SWEET KEYS: arb=%#x apids=%u pon-apid=%u up-apid=%u dn-apid=%u pon=%#x/%d up=%#x/%d dn=%#x/%d mode=%#x/%d en=%#x/%d subtype=%#x/%d\\n",
\t    keys_version, count, keys_pon_apid, keys_volup_apid, keys_voldn_apid,
\t    pon, pok, up, uok, dn, dok, mode, mok, en, eok, subtype, sok);"""),
    ("""\t\tprintf("SWEET KEYS: GPIO2 not confirmed enabled as input; volume-up withheld, PMIC unchanged\\n");
\t\tkeys_gpio_apid = KEYS_NO_APID;""",
     """\
\t\tprintf("SWEET KEYS: vol-up GPIO not confirmed enabled as input; withheld, PMIC unchanged\\n");
\t\tkeys_volup_apid = KEYS_NO_APID;"""),
]

HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(.*)$")


def recount(text):
    """Rewrite every hunk header count from its body (git trusts the header)."""
    # splitlines() drops the phantom element a trailing newline would add, which
    # is exactly what git counts: only real lines belong to a hunk body.
    lines = text.splitlines()
    out = []
    i = 0
    while i < len(lines):
        line = lines[i]
        m = HUNK.match(line)
        if not m:
            out.append(line)
            i += 1
            continue
        old_n = new_n = 0
        j = i + 1
        while j < len(lines):
            b = lines[j]
            if HUNK.match(b) or b.startswith("--- ") or b.startswith("diff --git "):
                break
            if b.startswith("\\"):
                pass
            elif b.startswith("+"):
                new_n += 1
            elif b.startswith("-"):
                old_n += 1
            elif b.startswith(" ") or b == "":
                old_n += 1
                new_n += 1
            else:
                break
            j += 1
        tail = m.group(5)
        header = "@@ -%s +%s @@%s" % (
            m.group(1) if old_n == 1 else "%s,%d" % (m.group(1), old_n),
            m.group(3) if new_n == 1 else "%s,%d" % (m.group(3), new_n),
            tail,
        )
        out.append(header)
        out.extend(lines[i + 1:j])
        i = j
    return "\n".join(out) + ("\n" if text.endswith("\n") else "")


def main():
    check = "--check" in sys.argv
    OUT.mkdir(parents=True, exist_ok=True)
    written = []
    failed = []

    for name, tree, cls in MANIFEST:
        src = (SWEET if tree == "sweet" else FAJITA) / name
        if not src.exists():
            failed.append("%s: missing in %s" % (name, tree))
            continue
        text = src.read_text(encoding="utf-8", errors="surrogateescape")
        if cls == "A":
            for old, new, want in ADAPT.get(name, []):
                got = text.count(old)
                if got != want:
                    failed.append("%s: %r occurs %d times, expected %d"
                                  % (name, old[:48], got, want))
                text = text.replace(old, new)
            if name == "0060-sweet-keys-touch-drivers.patch":
                # Every line of the two new files in this patch is an added
                # line, so the blocks are written as plain code and prefixed.
                def as_patch(block):
                    return "\n".join("+" + ln for ln in block.split("\n"))
                for old_b, new_b in KEYS_ADAPT:
                    old_p, new_p = as_patch(old_b), as_patch(new_b)
                    if old_p not in text:
                        failed.append("%s: keys block not found: %r" % (name, old_b[:48]))
                    text = text.replace(old_p, new_p, 1)
            text = recount(text)
        elif name in ADAPT:
            text = recount(text)
        if not name.endswith(".sh"):
            text = recount(text) if cls in ("A", "F") else text
        dest = OUT / name
        if dest.exists() and check and dest.read_text(encoding='utf-8', errors='surrogateescape') != text:
            failed.append("%s: on disk differs from what the builder produces" % name)
        dest.write_text(text, encoding='utf-8', errors='surrogateescape')
        written.append((name, hashlib.sha256(dest.read_bytes()).hexdigest()[:16], cls))

    if failed:
        print("FAILED:")
        for f in failed:
            print("  " + f)
        return 1

    series = ["# avicii XNU series - order matters; generated by tools/make-series.py",
              "# apply <file>  git apply into the xnu-8796 tree",
              "# copy  <file>  stage helper for blacktop build.sh (not a patch)"]
    for name, _sha, _cls in written:
        series.append(("copy  " if name.endswith(".sh") else "apply ") + name)
    (ROOT / "xnu-avicii/series").write_text("\n".join(series) + "\n")

    classes = {}
    for _n, _s, c in written:
        classes[c] = classes.get(c, 0) + 1
    print("%d files: %s" % (len(written), classes))
    return 0


if __name__ == "__main__":
    sys.exit(main())
