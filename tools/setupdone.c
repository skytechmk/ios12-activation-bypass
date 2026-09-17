/*
 * setupdone — write the lockdownd "com.apple.purplebuddy" domain keys that
 * iTunes/Finder writes when it finishes device setup.
 *
 * Why: SpringBoard's BYSetupAssistantNeedsToRun reads setup state from the
 * lockdownd com.apple.purplebuddy domain, NOT from the on-device plist.
 * Setup.app clobbers /var/mobile/Library/Preferences/com.apple.purplebuddy.plist
 * on every launch, so editing the plist alone never sticks.
 *
 * Build (macOS, with libimobiledevice + libplist available):
 *   clang -o setupdone setupdone.c \
 *       -limobiledevice-1.0 -lplist-2.0 -lusbmuxd-2.0
 *   (or link the dylibs directly by path)
 *
 * Usage:
 *   ./setupdone <buildVersion> <hardwareModel>
 *   e.g. ./setupdone 16H81 J86AP      # iPad mini 2 / iOS 12.5.7
 *
 * Then on the device: killall Setup; killall cfprefsd; killall backboardd
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <time.h>

typedef struct idevice_private *idevice_t;
typedef struct lockdownd_client_private *lockdownd_client_t;
typedef void* plist_t;

extern int idevice_new(idevice_t *device, const char *udid);
extern int lockdownd_client_new_with_handshake(idevice_t device, lockdownd_client_t *client, const char *label);
extern plist_t plist_new_bool(uint8_t val);
extern plist_t plist_new_string(const char *val);
extern plist_t plist_new_uint(uint64_t val);
extern plist_t plist_new_date(int32_t sec, int32_t usec);
extern int lockdownd_set_value(lockdownd_client_t client, const char *domain, const char *key, plist_t value);
extern int lockdownd_client_free(lockdownd_client_t client);
extern int idevice_free(idevice_t device);

#define DOM "com.apple.purplebuddy"

static int fail = 0;
static void sb(lockdownd_client_t c, const char *k, uint8_t v) {
    int r = lockdownd_set_value(c, DOM, k, plist_new_bool(v));
    printf("%-28s bool %d -> %d\n", k, v, r);
    if (r) fail = 1;
}
static void ss(lockdownd_client_t c, const char *k, const char *v) {
    int r = lockdownd_set_value(c, DOM, k, plist_new_string(v));
    printf("%-28s \"%s\" -> %d\n", k, v, r);
    if (r) fail = 1;
}
static void su(lockdownd_client_t c, const char *k, uint64_t v) {
    int r = lockdownd_set_value(c, DOM, k, plist_new_uint(v));
    printf("%-28s %llu -> %d\n", k, (unsigned long long)v, r);
    if (r) fail = 1;
}

int main(int argc, char **argv) {
    const char *build = argc > 1 ? argv[1] : "16H81";   /* iOS 12.5.7 */
    const char *hwmodel = argc > 2 ? argv[2] : "J86AP"; /* iPad4,5 */

    idevice_t dev = NULL;
    lockdownd_client_t client = NULL;
    if (idevice_new(&dev, NULL) != 0 || !dev) { puts("NO DEVICE"); return 1; }
    if (lockdownd_client_new_with_handshake(dev, &client, "setupdone") != 0 || !client) {
        puts("NO LOCKDOWND CLIENT (is the device paired?)"); return 1;
    }

    /* core completion flags — this is what iTunes writes after buddy finishes */
    sb(client, "SetupDone", 1);
    sb(client, "SetupFinishedAllSteps", 1);
    sb(client, "BuddySetupDone", 1);
    ss(client, "SetupState", "SetupCompleted");
    /* ForceNoBuddy: Setup.app volunteers to exit if present */
    sb(client, "ForceNoBuddy", 1);

    /* version gate — without buildVersion the upgrade mini-buddy keeps running */
    ss(client, "buildVersion", build);
    ss(client, "hardwareModel", hwmodel);
    su(client, "SetupVersion", 11);
    su(client, "setupMigratorVersion", 99);

    /* pane "already presented" flags so nothing re-prompts */
    sb(client, "AssistantPresented", 1);
    sb(client, "DictationPresented", 1);
    sb(client, "WiFiPresented", 1);
    sb(client, "SafetyPresented", 1);
    sb(client, "ScreenTimePresented", 1);
    sb(client, "MesaPresented", 1);
    sb(client, "PBDiagnostics", 1);
    sb(client, "AppleIDPB10Presented", 1);
    sb(client, "AssistantSOffered", 1);
    sb(client, "PBAppActivity2Presented", 1);
    sb(client, "HSA2UpgradeMiniBuddy3Ran", 1);
    sb(client, "PaymentMiniBuddy4Ran", 1);

    /* SetupLastExit — seconds since 2001-01-01 (Mac absolute time) */
    int32_t sec = (int32_t)(time(NULL) - 978307200);
    printf("%-28s date -> %d\n", "SetupLastExit",
           lockdownd_set_value(client, DOM, "SetupLastExit", plist_new_date(sec, 0)));

    lockdownd_client_free(client);
    idevice_free(dev);
    puts(fail ? "SOME WRITES FAILED" : "ALL WRITES OK — respring the device");
    return fail;
}
