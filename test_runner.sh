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

# Disable WebView Browser Shell to prevent Open With chooser dialog
echo "=== Disabling WebView Browser Shell ==="
adb shell pm disable-user org.chromium.webview_shell || true

MICROG_APK=$(find apks -name "*microg*" | head -n 1)
YOUTUBE_APK=$(find apks -name "*autospoof*" -o -name "*v17*" | head -n 1)

echo "Found MicroG: $MICROG_APK"
echo "Found YouTube: $YOUTUBE_APK"

echo "=== Installing MicroG ==="
adb install -r -d "$MICROG_APK" 2>&1 | tee test_results/microg_install.log

echo "=== Verifying MicroG package ==="
adb shell pm list packages | grep -i gms || true

echo "=== Launching MicroG Settings ==="
adb shell am start -n app.revanced.android.gms/org.microg.gms.ui.SettingsActivity || true
sleep 4
adb exec-out screencap -p > test_results/01_microg_launched.png
# Press back to close MicroG Settings UI
adb shell input keyevent 4 || true
sleep 1

echo "=== Pushing Auto-Spoof YouTube ReVanced APK to emulator ==="
adb push "$YOUTUBE_APK" /data/local/tmp/yt.apk

echo "=== Installing YouTube ReVanced ==="
timeout 180 adb shell pm install -r -d /data/local/tmp/yt.apk 2>&1 | tee test_results/yt_install.log
adb shell rm -f /data/local/tmp/yt.apk

echo "=== Verifying YouTube package ==="
adb shell pm list packages | grep -i rvx || true

# Grant storage permissions
adb shell pm grant app.rvx.android.youtube android.permission.WRITE_EXTERNAL_STORAGE || true
adb shell pm grant app.rvx.android.youtube android.permission.READ_EXTERNAL_STORAGE || true

echo "=== Launching Auto-Spoofed YouTube ReVanced Home ==="
adb shell monkey -p app.rvx.android.youtube -c android.intent.category.LAUNCHER 1 || true

echo "=== Waiting 15 seconds for Home startup & layout load ==="
sleep 15
adb exec-out screencap -p > test_results/02_youtube_home.png

# Dump UI hierarchy of Home
adb shell uiautomator dump /data/local/tmp/ui_home.xml || true
adb pull /data/local/tmp/ui_home.xml test_results/ui_home.xml || true

echo "=== Checking Process List after Home Launch ==="
adb shell ps | grep -E 'youtube|microg|rvx' | tee test_results/ps_after_launch.log

echo "=== Testing Direct Video Playback Intent (UrlActivity) ==="
# Rick Astley - Never Gonna Give You Up (dQw4w9WgXcQ)
adb shell am start -n app.rvx.android.youtube/com.google.android.youtube.UrlActivity \
  -a android.intent.action.VIEW \
  -d "https://www.youtube.com/watch?v=dQw4w9WgXcQ" \
  -p app.rvx.android.youtube || true

echo "=== Waiting 15 seconds into video buffering & playback ==="
sleep 15
adb exec-out screencap -p > test_results/03_video_playback_active.png

# Dump UI hierarchy of Video player
adb shell uiautomator dump /data/local/tmp/ui_video.xml || true
adb pull /data/local/tmp/ui_video.xml test_results/ui_video.xml || true

echo "=== Tap Video Center (540, 400) to expose player controls & playback bar ==="
adb shell input tap 540 400 || true
sleep 3
adb exec-out screencap -p > test_results/04_video_controls_active.png

echo "=== Waiting another 15s of continuous playback ==="
sleep 15
adb exec-out screencap -p > test_results/05_video_playback_continued.png

echo "=== Top Activity Information ==="
adb shell dumpsys activity top | tee test_results/dumpsys_activity_top.log || true

echo "=== Media & Audio Status ==="
adb shell dumpsys media.player | tee test_results/dumpsys_media_player.log || true
adb shell dumpsys audio | grep -iE 'mode|player|state' | tee test_results/dumpsys_audio.log || true

echo "=== Extracting playback and error logs ==="
adb logcat -d -s AndroidRuntime:* *:E > test_results/crash_errors.log || true
adb logcat -d | grep -iE 'exo|player|playback|videoplayback|innertube|googlevideo' | tail -n 120 > test_results/playback_logs.txt || true

echo "=== Final Process Status ==="
adb shell ps | grep -E 'youtube|microg|rvx' | tee test_results/ps_final.log

# Stop background logcat
kill $LOGCAT_PID || true

echo "=== Done test runner ==="
