#!/bin/bash
set -x

mkdir -p test_results

echo "=== System Info ==="
echo "Android Release: $(adb shell getprop ro.build.version.release)"
echo "Android SDK: $(adb shell getprop ro.build.version.sdk)"
echo "CPU ABI: $(adb shell getprop ro.product.cpu.abi)"

echo "=== Unlocking Screen ==="
adb shell input keyevent 82 || true
adb shell wm dismiss-keyguard || true

MICROG_APK=$(find apks -name "*microg*" | head -n 1)
YOUTUBE_APK=$(find apks -name "*patched*" -o -name "*youtube*" | head -n 1)

echo "Found MicroG: $MICROG_APK"
echo "Found YouTube: $YOUTUBE_APK"

echo "=== Installing MicroG ==="
adb install -r -d "$MICROG_APK" 2>&1 | tee test_results/microg_install.log

echo "=== Verifying MicroG package ==="
adb shell pm list packages | grep -i gms || true

echo "=== Launching MicroG Settings ==="
adb shell am start -n app.revanced.android.gms/.ui.SettingsActivity || true
sleep 5
adb exec-out screencap -p > test_results/01_microg_launched.png

echo "=== Installing Patched YouTube ReVanced ==="
adb install -r -d "$YOUTUBE_APK" 2>&1 | tee test_results/yt_install.log

echo "=== Verifying YouTube package ==="
adb shell pm list packages | grep -i rvx || true

echo "=== Clearing logcat before launch ==="
adb logcat -c

echo "=== Launching YouTube ReVanced ==="
adb shell am start -n app.rvx.android.youtube/com.google.android.apps.youtube.app.watchwhile.WatchWhileActivity || true

echo "=== Waiting 15 seconds for app startup ==="
sleep 15
adb exec-out screencap -p > test_results/02_youtube_started.png

echo "=== Checking Process List ==="
adb shell ps | grep -E 'youtube|microg|rvx' || true

echo "=== Testing Video Playback Intent ==="
# Open Rick Astley - Never Gonna Give You Up (dQw4w9WgXcQ)
adb shell am start -a android.intent.action.VIEW -d "vnd.youtube:dQw4w9WgXcQ" app.rvx.android.youtube || true
sleep 15
adb exec-out screencap -p > test_results/03_video_playback_attempt.png

echo "=== Testing HTTPS URL Playback Intent ==="
adb shell am start -a android.intent.action.VIEW -d "https://www.youtube.com/watch?v=dQw4w9WgXcQ" app.rvx.android.youtube || true
sleep 15
adb exec-out screencap -p > test_results/04_video_playback_url.png

echo "=== Dumping logcat ==="
adb logcat -d > test_results/full_logcat.log
adb logcat -d -s AndroidRuntime:* *:E > test_results/crash_errors.log

echo "=== Final Process Status ==="
adb shell ps | grep -E 'youtube|microg|rvx' || true
echo "=== Done test runner ==="
