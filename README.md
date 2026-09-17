# iOS 12 Activation Bypass (checkm8 devices)

Step-by-step activation/setup bypass for checkm8-vulnerable devices on iOS 12.x —
developed and verified on an **iPad mini 2 (iPad4,5, A7) running iOS 12.5.7 (16H81)**
that was stuck on the *Connect to iTunes* screen despite reporting `FactoryActivated`.

> **Disclaimer:** For devices you own. This bypasses the setup/activation UI on the
> device itself; it does not remove an iCloud account from Apple's servers or make
> the device cellular/iCloud functional.

## Why this repo exists

Every guide stops at "patch `mobileactivationd`, tap Connect to iTunes". That gets
the device to *report* `FactoryActivated` — but the setup UI can remain stuck on
the iTunes/cable screen forever, because **SpringBoard does not read the
`com.apple.purplebuddy.plist` file to decide whether setup is done.**

`BYSetupAssistantNeedsToRun` (SetupAssistant.framework, called by SpringBoard)
reads the **`com.apple.purplebuddy` lockdownd domain** — the same keys iTunes
writes through lockdownd when it finishes setup. If those keys are missing, setup
relaunches no matter what the plist says (and `Setup.app` clobbers the plist on
every launch anyway). This repo includes a small tool that writes them.

## Requirements

- **macOS host** — *required for A7 devices*. The Linux build of checkra1n
  explicitly does not support A7, and raw checkm8 via `ipwndfu`/`gaster` on Linux
  or a Raspberry Pi proved too unreliable to land on this SoC.
- `checkra1n` **0.12.4** (https://checkra.in) — the last release.
- `libimobiledevice` tools: `ideviceactivation`, `ideviceinfo`, `idevicesyslog`.
- A C compiler (`clang`) and `libimobiledevice`/`libplist` headers/libs to build
  `tools/setupdone`.
- The device must be **paired/trusted** with the host at least once
  (`idevicepair pair`), or let Finder see it once while on the iTunes screen.

## Steps

### 1. Jailbreak (tethered)

Put the device in DFU (Power+Home ~10s → release Power → hold Home ~10s), then:

```sh
/Applications/checkra1n.app/Contents/MacOS/checkra1n -c
```

It loops until the exploit lands (`Entered download mode` → `Booting...` →
`All Done`). `-31` failures are normal — leave it running and re-enter DFU if the
device falls back to normal mode.

### 2. USB SSH

checkra1n starts dropbear on device port 44. Any usbmux relay works — `iproxy`,
or the zero-dependency one here (works on macOS and Linux):

```sh
python3 tools/usbmux_relay.py 2222 44 &
ssh -p 2222 root@127.0.0.1        # password: alpine
```

### 3. Patched mobileactivationd

Get the patched `mobileactivationd` (arm64, iOS 12.x) — e.g. from
`wrcsubers/iOS_ActivationBypass`. Expected MD5: `31c27098c867e4444007f625ac0f6d12`.
Push it to `/tmp/mobileactivationd` on the device, then run:

```sh
sh tools/install_mad.sh        # executes ON the device
```

It remounts the rootfs (`mount -o rw,union,update /`), unloads the daemon,
swaps the binary, reloads it.

### 4. Activate

```sh
ideviceactivation activate      # -> "already activated" / FactoryActivated
ideviceactivation itunes        # sets iTunesHasConnected
ideviceactivation state         # verify: FactoryActivated
```

### 5. Unbrick the data ark

The activation container plist may carry `-BrickState = true` (the iCloud lock
flag). On the device:

```sh
cat /private/var/containers/Data/System/*/Library/internal/data_ark.plist
```

If `-BrickState` is `<true/>`, pull the file, set it to `<false/>` (plutil on a
desktop), push it back.

### 6. Write the setup-done state to lockdownd  ← the step everyone misses

```sh
clang -o setupdone tools/setupdone.c \
    -limobiledevice-1.0 -lplist-2.0 -lusbmuxd-2.0
./setupdone 16H81 J86AP          # <ProductBuildVersion> <hardwareModel>
```

This writes `SetupDone`, `SetupFinishedAllSteps`, `SetupState=SetupCompleted`,
`ForceNoBuddy`, `buildVersion`, `hardwareModel`, `SetupVersion`,
`setupMigratorVersion`, all `*Presented`/`*Ran` pane flags and `SetupLastExit`
into the lockdownd `com.apple.purplebuddy` domain — exactly what iTunes writes
when it finishes buddy setup.

### 7. Finish setup and respring

Push `tools/com.apple.purplebuddy.plist` to `/tmp/pb.plist` on the device, then:

```sh
sh tools/finish_setup.sh        # executes ON the device
```

Order matters: `killall Setup` → `killall cfprefsd` (flushes the cached prefs so
they can't be written back over the file) → install plist → `killall backboardd`.

The device resprings to the **home screen**.

## Diagnosing a stuck setup

Watch the device log while respringing:

```sh
idevicesyslog | grep NeedsToRun
```

SpringBoard logs exactly which gate is failing:

| Log line | Missing state |
|---|---|
| `YES because !setupDone` | `com.apple.purplebuddy`/`SetupDone` in lockdownd |
| `YES to show upgrade mini buddy` | `buildVersion`/`setupMigratorVersion` etc. in lockdownd |
| `YES because !activated` | activation not committed — check `ideviceactivation state` |

## Caveats

- **Tethered.** A full reboot returns to the setup screen — redo from step 1
  (jailbreak) through step 7. Keep the battery charged.
- Deleting `Setup.app` does **not** work on 12.5.x — SpringBoard spins at ~100%
  CPU trying to launch it. Leave it in place; `ForceNoBuddy` + the lockdownd
  state make it exit voluntarily.
- `ideviceactivation activate` short-circuits on "already activated" and never
  performs the full host handshake — that's why the lockdownd writes in step 6
  are required.
- After success, the device syncs normally with Finder; iCloud-dependent
  services (iMessage, push certs) will not work — there is no activation record.

## Verified on

| Device | SoC | iOS | Build |
|---|---|---|---|
| iPad mini 2 (iPad4,5) | A7 / S5L8960 | 12.5.7 | 16H81 |

Other checkm8 devices on iOS 12.x should work identically — pass the right
`<buildVersion>`/`hardwareModel` to `setupdone`.
