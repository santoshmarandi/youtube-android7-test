#!/bin/bash
set -x

mkdir -p test_results

# Restart adb as root for full filesystem access
adb root || true
sleep 3

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

# Disable WebView Browser Tester to eliminate any Open With chooser dialog
echo "=== Disabling WebView Browser Shell ==="
adb shell pm disable-user org.chromium.webview_shell || true

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
sleep 4
adb exec-out screencap -p > test_results/01_microg_launched.png
# Press back to close MicroG Settings UI
adb shell input keyevent 4 || true
sleep 1

# Disable battery optimizations to prevent GmsCore alert
echo "=== Whitelisting Battery Optimizations ==="
adb shell dumpsys deviceidle whitelist +app.revanced.android.gms || true
adb shell dumpsys deviceidle whitelist +app.rvx.android.youtube || true

echo "=== Pushing YouTube ReVanced Android 7 APK to emulator ==="
adb push "$YOUTUBE_APK" /data/local/tmp/yt.apk

echo "=== Installing YouTube ReVanced ==="
timeout 180 adb shell pm install -r -d /data/local/tmp/yt.apk 2>&1 | tee test_results/yt_install.log
adb shell rm -f /data/local/tmp/yt.apk

echo "=== Verifying YouTube package ==="
adb shell pm list packages | grep -i rvx || true

# Grant storage permissions
adb shell pm grant app.rvx.android.youtube android.permission.WRITE_EXTERNAL_STORAGE || true
adb shell pm grant app.rvx.android.youtube android.permission.READ_EXTERNAL_STORAGE || true

echo "=== Stage 1: First Run to Fetch Native 17.34.36 Server Layout ==="
adb shell monkey -p app.rvx.android.youtube -c android.intent.category.LAUNCHER 1 || true

echo "=== Waiting 15 seconds for layout fetch from YouTube servers ==="
sleep 15
adb exec-out screencap -p > test_results/02_youtube_home_first_run.png

echo "=== Pulling initial shared_prefs ==="
mkdir -p test_results/shared_prefs_first_run
adb pull /data/data/app.rvx.android.youtube/shared_prefs test_results/shared_prefs_first_run/ || true
ls -la test_results/shared_prefs_first_run/ || true

echo "=== Generating revanced.xml with App Version Spoofing (19.01.34) and Layout Freeze ==="
python3 configure_spoof.py test_results/shared_prefs_first_run/shared_prefs/youtube.xml revanced.xml || \
python3 configure_spoof.py test_results/shared_prefs_first_run/youtube.xml revanced.xml || true
cat revanced.xml

echo "=== Pushing configured revanced.xml to app ==="
adb push revanced.xml /data/data/app.rvx.android.youtube/shared_prefs/revanced.xml
APP_UID=$(adb shell stat -c '%u:%g' /data/data/app.rvx.android.youtube | tr -d '\r')
adb shell chown "$APP_UID" /data/data/app.rvx.android.youtube/shared_prefs/revanced.xml || true
adb shell chmod 660 /data/data/app.rvx.android.youtube/shared_prefs/revanced.xml || true

echo "=== Restarting YouTube with Spoofing & Frozen Layout Active ==="
adb shell am force-stop app.rvx.android.youtube
sleep 3

adb shell monkey -p app.rvx.android.youtube -c android.intent.category.LAUNCHER 1 || true

echo "=== Waiting 12 seconds for Spoofed Home startup ==="
sleep 12
adb exec-out screencap -p > test_results/03_youtube_home_spoofed.png

echo "=== Checking Process List after Spoofed Launch ==="
adb shell ps | grep -E 'youtube|microg|rvx' | tee test_results/ps_after_launch.log

echo "=== Stage 2: Direct Video Playback Intent ==="
# Rick Astley - Never Gonna Give You Up (dQw4w9WgXcQ)
adb shell am start -n app.rvx.android.youtube/com.google.android.apps.youtube.app.watchwhile.WatchWhileActivity \
  -a android.intent.action.VIEW \
  -d "https://www.youtube.com/watch?v=dQw4w9WgXcQ" \
  -p app.rvx.android.youtube || true

echo "=== Waiting 15 seconds into video buffering & playback ==="
sleep 15
adb exec-out screencap -p > test_results/04_video_playback_active.png

echo "=== Tap Video Center (540, 400) to expose player controls & playback bar ==="
adb shell input tap 540 400 || true
sleep 3
adb exec-out screencap -p > test_results/05_video_controls_active.png

echo "=== Waiting another 15s of continuous playback ==="
sleep 15
adb exec-out screencap -p > test_results/06_video_playback_continued.png

echo "=== Top Activity Information ==="
adb shell dumpsys activity top | tee test_results/dumpsys_activity_top.log || true

echo "=== Media & Audio Status ==="
adb shell dumpsys media.player | tee test_results/dumpsys_media_player.log || true
adb shell dumpsys audio | grep -iE 'mode|player|state' | tee test_results/dumpsys_audio.log || true

echo "=== Extracting final shared_prefs ==="
mkdir -p test_results/shared_prefs_after_spoof
adb pull /data/data/app.rvx.android.youtube/shared_prefs test_results/shared_prefs_after_spoof/ || true

echo "=== Extracting playback and error logs ==="
adb logcat -d -s AndroidRuntime:* *:E > test_results/crash_errors.log || true
adb logcat -d | grep -iE 'exo|player|playback|videoplayback|innertube|googlevideo' | tail -n 120 > test_results/playback_logs.txt || true

echo "=== Final Process Status ==="
adb shell ps | grep -E 'youtube|microg|rvx' | tee test_results/ps_final.log

# Stop background logcat
kill $LOGCAT_PID || true

echo "=== Done test runner ==="
