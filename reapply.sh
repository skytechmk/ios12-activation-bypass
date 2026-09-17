#!/bin/bash
# reapply.sh — one-shot re-bypass after a reboot/power-off.
# Run on the macOS host AFTER the device has been re-jailbroken with checkra1n
# and is booted at the setup screen.
#
#   ./reapply.sh [path/to/patched/mobileactivationd]
#
# Defaults: patched daemon expected at ./mobileactivationd
# (MD5 31c27098c867e4444007f625ac0f6d12 for the iOS 12.x arm64 build).
set -e
cd "$(dirname "$0")"

MAD="${1:-./mobileactivationd}"
[ -f "$MAD" ] || { echo "patched mobileactivationd not found at $MAD"; exit 1; }

# 1. usbmux relay (device port 44 -> local 2222)
if ! nc -z 127.0.0.1 2222 2>/dev/null; then
    if command -v iproxy >/dev/null 2>&1; then
        iproxy 2222 44 >/dev/null 2>&1 &
    else
        python3 tools/usbmux_relay.py 2222 44 >/dev/null 2>&1 &
    fi
    sleep 2
fi

# 2. SSH helper (macOS ships expect; password is checkra1n's default)
dossh() {
expect - "$@" <<'EXP'
set timeout 30
log_user 1
eval spawn ssh -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-rsa \
    -o PubkeyAcceptedKeyTypes=+ssh-rsa -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no -p 2222 root@127.0.0.1 $argv
expect { -re "assword:" { send "alpine\r" } timeout { exit 1 } }
expect eof
EXP
}
doscp() {
expect - "$@" <<'EXP'
set timeout 60
log_user 0
eval spawn scp -o StrictHostKeyChecking=no -o HostKeyAlgorithms=+ssh-rsa \
    -o PubkeyAcceptedKeyTypes=+ssh-rsa -P 2222 $argv
expect { -re "assword:" { send "alpine\r" } timeout { exit 1 } }
expect eof
EXP
}

echo "[*] pushing patched mobileactivationd + plist..."
doscp "$MAD" root@127.0.0.1:/tmp/mobileactivationd
doscp tools/com.apple.purplebuddy.plist root@127.0.0.1:/tmp/pb.plist
doscp tools/install_mad.sh root@127.0.0.1:/tmp/install_mad.sh

echo "[*] installing patched daemon on device..."
dossh "sh /tmp/install_mad.sh"

echo "[*] activation state:"
ideviceactivation activate 2>/dev/null || true
ideviceactivation state 2>/dev/null || true

echo "[*] writing purplebuddy setup-done keys to lockdownd..."
if [ ! -x ./setupdone ]; then
    clang -o setupdone tools/setupdone.c \
        -limobiledevice-1.0 -lplist-2.0 -lusbmuxd-2.0 2>/dev/null || \
    clang -o setupdone tools/setupdone.c "$(pkg-config --variable=libdir libimobiledevice-1.0 2>/dev/null || echo /usr/local/lib)/libimobiledevice-1.0.dylib" 2>/dev/null || {
        echo "    could not build setupdone — link against your libimobiledevice dylib manually"; }
fi
[ -x ./setupdone ] && ./setupdone "${BUILD:-16H81}" "${HWMODEL:-J86AP}"

echo "[*] finishing setup + respring..."
doscp tools/finish_setup.sh root@127.0.0.1:/tmp/finish_setup.sh
dossh "sh /tmp/finish_setup.sh"

echo "[+] done — device should respring to the home screen"
