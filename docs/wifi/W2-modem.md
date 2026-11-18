# W2 modem firmware check

The W1 phone run found an empty apps-to-MPSS SMEM partition. The modem needs to
boot before the GLINK and QRTR checks in the WLAN ladder can run. This branch
inserts a read-only firmware check at `sweetwifi=2`. The expected phone log is
`SWEET WIFI: step W2 PASS`.

The check locates `modem_a` through the UFS GPTs, opens its FAT volume, and checks
the MDT and matching segment files. The modem carve-out is documented in
[board constants](../../avicii/CONSTANTS.md#8-wlan--ipa). The later PAS and modem
protocol steps still need hardware bring-up.

## Host result

The kernel FAT and MDT code parsed the saved `modem_a` partition image with
UFS reads backed by a read-only host file. It found FAT16, 35 ELF program
headers, and 33 loadable segments with no size or lookup failures. The
relocatable address range `0x8c000000..0x9b800000` fits the recorded modem
carve-out. It found `image/wlanmdsp.mbn` (4,097,376 bytes). A full read of
`modem.b27` matched `mcopy` byte for byte.

The full patch series applies and the touched XNU sources pass the local
syntax check. Phone verification still needs a RAM boot and a W2 pass in the
kernel log.
