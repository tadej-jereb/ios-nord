#!/bin/bash
# 74-kernel-loop.sh — one command from a CI kernel build to an SSH prompt on the phone.
#
#   tooling/74-kernel-loop.sh RUN_ID NAME [--preset usb] [--extra "boot-args"]
#   tooling/74-kernel-loop.sh 43695990000 0115
#
# The steps that were typed by hand for every kernel on 2026-11-14/15:
#   1. wait for CI run RUN_ID (gh run watch), download its xnu-kernel-sweet
#      artifact to avicii/shim/out/kernel-NAME and check SHA256SUMS
#   2. tooling/71-phone-image.sh --preset PRESET --kernel ... --boot
#      (phone in recovery with adb, fastbootd or the bootloader; nothing flashed)
#   3. wait for the phone's USB Ethernet, give the host 192.168.7.1, record the
#      live kernel log (UDP 5140) to logs/phone/live-<stamp>-NAME.txt
#   4. wait for sshd on 192.168.7.2:22 and print the ssh command
# The log recorder keeps running in the background; its PID is printed.
# Host address: if a NetworkManager profile gives the phone link 192.168.7.1
# (one-time, see docs/STATUS.md), no sudo is needed; otherwise sudo is asked
# first, while there is a terminal, and used for the address only.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
REPO=${REPO:-tadej-jereb/ios-nord}
KEY=${KEY:-$HOME/.ssh/ios_nord_ed25519}
KH=$HOME/.ssh/known_hosts_ios_nord
MAC=02:00:5e:77:ee:01

run=${1:?usage: $0 RUN_ID NAME [--preset P] [--extra ARGS]}
name=${2:?usage: $0 RUN_ID NAME [--preset P] [--extra ARGS]}
shift 2
preset=usb extra=""
while [ $# -gt 0 ]; do
	case $1 in
	--preset) preset=${2:?}; shift 2 ;;
	--extra) extra=${2:?}; shift 2 ;;
	*) echo "error: unknown argument $1" >&2; exit 2 ;;
	esac
done
[ "$preset" = usb ] || echo "note: preset $preset has no USB Ethernet; stopping after the boot" >&2
nm_profile=0
nmcli -t -f NAME con show 2>/dev/null | grep -qx ios-nord && nm_profile=1
[ "$nm_profile" = 1 ] || sudo -v
t0=$(date +%s)
say() { printf '[%4ss] %s\n' $(( $(date +%s) - t0 )) "$*"; }

dir=avicii/shim/out/kernel-$name
if [ -f "$dir/kernel.development.sweet" ]; then
	say "kernel-$name already downloaded"
else
	say "waiting for CI run $run"
	gh run watch "$run" -R "$REPO" --exit-status >/dev/null || { gh run view "$run" -R "$REPO" | tail -5; exit 1; }
	gh run download "$run" -R "$REPO" -n xnu-kernel-sweet -D "$dir"
fi
(cd "$dir" && sha256sum -c --quiet SHA256SUMS)
say "kernel-$name verified"

./tooling/71-phone-image.sh --preset "$preset" --kernel "$dir" --name "$preset-kernel-$name" ${extra:+--extra "$extra"} --boot | tail -4
[ "$preset" = usb ] || exit 0

say "waiting for the phone's USB Ethernet"
for _ in $(seq 1 120); do ip -o link | grep -qi "$MAC" && break; sleep 1; done
ifname=$(ip -o link | grep -i "$MAC" | awk -F': ' '{print $2}' | cut -d@ -f1)
[ -n "$ifname" ] || { say "no USB Ethernet after 120 s (kernel stuck before USB?)"; exit 1; }
if [ "$nm_profile" = 1 ]; then
	for _ in $(seq 1 15); do ip -o addr show "$ifname" | grep -q 'inet 192.168.7.1/' && break; sleep 1; done
fi
if ! ip -o addr show "$ifname" | grep -q 'inet 192.168.7.1/'; then
	nmcli dev set "$ifname" managed no 2>/dev/null || true
	sudo ip addr replace 192.168.7.1/24 dev "$ifname"
	sudo ip link set "$ifname" up
fi
log=logs/phone/live-$(date -u +%Y%m%d-%H%M%S)-$name.txt
nohup python3 -I -u -c '
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", 5140))
with open(sys.argv[1], "ab") as f:
    while True:
        d, _ = s.recvfrom(65536); f.write(d); f.flush()
' "$log" >/dev/null 2>&1 &
say "$ifname up; live log -> $log (recorder pid $!)"

say "waiting for sshd"
for _ in $(seq 1 360); do
	timeout 3 bash -c 'echo > /dev/tcp/192.168.7.2/22' 2>/dev/null && break
	sleep 5
done
timeout 3 bash -c 'echo > /dev/tcp/192.168.7.2/22' 2>/dev/null || { say "sshd not up after 30 min"; exit 1; }
say "ssh ready:"
echo "  ssh -i $KEY -o UserKnownHostsFile=$KH root@192.168.7.2"
