#!/bin/sh
# install_mad.sh — run ON THE DEVICE as root over USB SSH
# Swaps in the patched mobileactivationd. Push the patched binary to
# /tmp/mobileactivationd first (see README for where to get it / its MD5).
set -x

mount -o rw,union,update /

launchctl unload /System/Library/LaunchDaemons/com.apple.mobileactivationd.plist
rm -f /usr/libexec/mobileactivationd
cp /tmp/mobileactivationd /usr/libexec/mobileactivationd
chmod 755 /usr/libexec/mobileactivationd
chown root:wheel /usr/libexec/mobileactivationd
launchctl load /System/Library/LaunchDaemons/com.apple.mobileactivationd.plist

# confirm it is running
ps aux | grep mobileactivationd | grep -v grep
