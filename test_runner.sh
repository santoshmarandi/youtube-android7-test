#!/bin/bash
set -x

mkdir -p test_results

# Start continuous live logcat in background
adb logcat -v time > test_results/live_logcat.txt 2>&1 &
LOGCAT_PID=$!

echo "=== System Info ==="
echo "Android Release: $(adb shell getprop ro.build.version.release)"
echo "Android SDK: $(adb shell getprop ro.build.version.sdk)"
echo "CPU ABI: $(adb shell getprop ro.product.cpu.abi)"

# Optimize dexopt for fast installation
adb shell setprop pm.dexopt.install quicken || true
adb shell setprop dalvik.vm.dex2oat-filter quicken || true

# Enable networking
echo "=== Enabling Network ==="
adb shell svc data enable || true
adb shell svc wifi enable || true
sleep 3
adb shell ping -c 3 8.8.8.8 || true

echo "=== Unlocking Screen ==="
adb shell input keyevent 82 || true
adb shell wm dismiss-keyguard || true

MICROG_APK=$(find apks -name "*microg*" | head -n 1)
YOUTUBE_APK=$(find apks \( -name "*v17*" -o -name "*youtube_android7*" \) | head -n 1)

echo "Found MicroG: $MICROG_APK"
echo "Found YouTube: $YOUTUBE_APK"

echo "=== Installing MicroG ==="
adb install -r -d "$MICROG_APK" 2>&1 | tee test_results/microg_install.log

echo "=== Verifying MicroG package ==="
adb shell pm list packages | grep -i gms || true

echo "=== Launching MicroG Settings ==="
adb shell am start -n app.revanced.android.gms/org.microg.gms.ui.SettingsActivity || true
sleep 5
adb exec-out screencap -p > test_results/01_microg_launched.png

echo "=== Pushing YouTube ReVanced Android 7 APK to emulator ==="
adb push "$YOUTUBE_APK" /data/local/tmp/yt.apk

echo "=== Installing YouTube ReVanced ==="
timeout 180 adb shell pm install -r -d /data/local/tmp/yt.apk 2>&1 | tee test_results/yt_install.log
adb shell rm -f /data/local/tmp/yt.apk

echo "=== Verifying YouTube package ==="
adb shell pm list packages | grep -i rvx || true

echo "=== Launching YouTube ReVanced Home ==="
adb shell am start -n app.rvx.android.youtube/com.google.android.youtube.app.honeycomb.Shell\$HomeActivity || \
adb shell monkey -p app.rvx.android.youtube -c android.intent.category.LAUNCHER 1 || true

echo "=== Waiting 15 seconds for Home startup & layout load ==="
sleep 15
adb exec-out screencap -p > test_results/02_youtube_home.png

echo "=== Checking Process List ==="
adb shell ps | grep -E 'youtube|microg|rvx' | tee test_results/ps_after_launch.log

echo "=== Testing Video Playback Intent (vnd.youtube) ==="
adb shell am start -a android.intent.action.VIEW -d "vnd.youtube:dQw4w9WgXcQ" app.rvx.android.youtube || true
sleep 12
adb exec-out screencap -p > test_results/03_video_intent_playback.png

echo "=== Waiting 10s into playback ==="
sleep 10
adb exec-out screencap -p > test_results/04_video_playing.png

echo "=== Testing Video Playback URL (https) ==="
adb shell am start -a android.intent.action.VIEW -d "https://www.youtube.com/watch?v=dQw4w9WgXcQ" app.rvx.android.youtube || true
sleep 12
adb exec-out screencap -p > test_results/05_video_url_playback.png

echo "=== Media & Audio Status ==="
adb shell dumpsys media.player | tee test_results/dumpsys_media_player.log || true
adb shell dumpsys audio | grep -iE 'mode|player|state' | tee test_results/dumpsys_audio.log || true

echo "=== Extracting crash errors ==="
adb logcat -d -s AndroidRuntime:* *:E > test_results/crash_errors.log || true

echo "=== Final Process Status ==="
adb shell ps | grep -E 'youtube|microg|rvx' | tee test_results/ps_final.log

# Stop background logcat
kill $LOGCAT_PID || true

echo "=== Done test runner ==="
