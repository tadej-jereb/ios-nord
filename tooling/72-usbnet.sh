#!/bin/sh
# 72-usbnet.sh — host side of the phone's USB Ethernet (kernel sweetusb=2,
# patches 0075-0077 + 0112; image: tooling/71-phone-image.sh --preset usb).
#
#   tooling/72-usbnet.sh [LOGFILE]
#
# Waits for the phone's CDC-ECM interface (host-side MAC 02:00:5e:77:ee:01,
# set by sweet_usb.c), takes it away from NetworkManager, gives it
# 192.168.7.1/24 (the phone is 192.168.7.2), then prints the live kernel console
# the phone streams to UDP port 5140, appending to LOGFILE when given
# (default logs/phone/live-<stamp>.txt). Needs sudo for the address only.
# Adapted from refs/edi194-ios-fajita/tools/sweet-usbnet.sh.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
mac=02:00:5e:77:ee:01
log=${1:-$repo/logs/phone/live-$(date -u +%Y%m%d-%H%M%S).txt}
mkdir -p "$(dirname "$log")"
# Ask for the sudo password now, while there is a terminal: by the time the
# phone's interface shows up the script may be running unattended.
sudo -v
echo "waiting for the phone's USB Ethernet ($mac)..." >&2
until ip -o link | grep -qi "$mac"; do sleep 1; done
ifname=$(ip -o link | grep -i "$mac" | awk -F': ' '{print $2}' | cut -d@ -f1)
nmcli dev set "$ifname" managed no 2>/dev/null || true
sudo ip addr replace 192.168.7.1/24 dev "$ifname"
sudo ip link set "$ifname" up
echo "$ifname up: 192.168.7.1 <-> phone 192.168.7.2; live log on udp/5140 -> $log" >&2
python3 -I -u -c '
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("192.168.7.1", 5140))
with open(sys.argv[1], "ab") as f:
    while True:
        d, _ = s.recvfrom(65536)
        f.write(d); f.flush()
        sys.stdout.buffer.write(d); sys.stdout.flush()
' "$log"
