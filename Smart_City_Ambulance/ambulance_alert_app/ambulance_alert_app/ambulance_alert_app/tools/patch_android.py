#!/usr/bin/env python3
"""Adds permissions and the app name to AndroidManifest.xml (runs after flutter create).
Usage: patch_android.py <AndroidManifest.xml> "<App Label>"
"""
import re
import sys

path, label = sys.argv[1], sys.argv[2]
s = open(path, encoding="utf-8").read()

perms = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_LOCATION",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.WAKE_LOCK",
    "android.permission.VIBRATE",
]
add = ""
for p in perms:
    if p not in s:
        add += f'    <uses-permission android:name="{p}"/>\n'
if add:
    s = s.replace("<application", add + "    <application", 1)

# Text-to-speech (required on Android 11+)
tts = '<intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>'
if "TTS_SERVICE" not in s:
    if "<queries>" in s:
        s = s.replace("<queries>", "<queries>\n        " + tts, 1)
    else:
        s = s.replace("</manifest>", "    <queries>\n        " + tts + "\n    </queries>\n</manifest>", 1)

# App name
s = re.sub(r'android:label="[^"]*"', f'android:label="{label}"', s, count=1)

open(path, "w", encoding="utf-8").write(s)
print("Manifest patched:", label)
