#!/bin/sh
# finish_setup.sh — run ON THE DEVICE as root (ssh root@<device> via usbmux relay)
# Kills Setup, flushes the prefs cache, installs the completed-state plist, resprings.
#
# Prereq: tools/com.apple.purplebuddy.plist already pushed to /tmp/pb.plist on device.
set -x

# Setup must die first — it rewrites the plist on every launch
killall -9 Setup 2>/dev/null

# cfprefsd holds com.apple.purplebuddy in memory and would write the old
# state back over our file — kill it so the next reader gets the file
killall -9 cfprefsd 2>/dev/null
sleep 2

cp /tmp/pb.plist /private/var/mobile/Library/Preferences/com.apple.purplebuddy.plist
chown mobile:mobile /private/var/mobile/Library/Preferences/com.apple.purplebuddy.plist

# respring — SpringBoard re-checks BYSetupAssistantNeedsToRun
killall -9 backboardd
