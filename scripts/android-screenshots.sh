#!/bin/bash
# Снимает скриншоты Android-версии в эмуляторе.
# Использование: scripts/android-screenshots.sh <путь/к/app-debug.apk> <папка-для-скриншотов>
set -uo pipefail

APK="$1"
OUT="$2"
PKG=com.example.kvartet
ACTIVITY="$PKG/app.kvartet.MainActivity"
mkdir -p "$OUT"
rm -f "$OUT"/*.png "$OUT"/*.jpg

# adb shell читает стандартный ввод — отдаём ему /dev/null, иначе он «съест» список ниже.
adb() { command adb "$@" </dev/null; }

adb install -r "$APK"
# Системные окна «приложение не отвечает» (в эмуляторе их часто показывает лаунчер) не нужны на снимках.
adb shell settings put global hide_error_dialogs 1
adb shell settings put global anr_show_background 0
# Настройка применяется при смене конфигурации — переключаем ночной режим туда-обратно.
adb shell "cmd uimode night yes"
adb shell "cmd uimode night no"
# Ровные часы и полная батарея в строке состояния (после смены темы SystemUI сбрасывает демо-режим).
demo_status_bar() {
  adb shell settings put global sysui_demo_allowed 1
  adb shell am broadcast -a com.android.systemui.demo -e command enter >/dev/null
  adb shell am broadcast -a com.android.systemui.demo -e command clock -e hhmm 0941 >/dev/null
  adb shell am broadcast -a com.android.systemui.demo -e command battery -e level 100 -e plugged false >/dev/null
  adb shell am broadcast -a com.android.systemui.demo -e command network -e wifi show -e level 4 >/dev/null
  adb shell am broadcast -a com.android.systemui.demo -e command network -e mobile show -e datatype none -e level 4 >/dev/null
  adb shell am broadcast -a com.android.systemui.demo -e command notifications -e visible false >/dev/null
}

close_dialogs() {
  adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS >/dev/null 2>&1
}

shot() {
  sleep "$2"
  close_dialogs
  sleep 1
  adb exec-out screencap -p > "$OUT/$1.png"
  echo "📸 $1"
}

open_link() {
  adb shell am force-stop "$PKG"
  adb shell am start -W -a android.intent.action.VIEW -d "'$1'" -n "$ACTIVITY" --ez skipOnboarding true >/dev/null
}

# Даём лаунчеру спокойно запуститься после загрузки, чтобы он не «зависал» во время съёмки.
adb shell input keyevent KEYCODE_HOME
sleep 20
close_dialogs
demo_status_bar

adb shell am start -W -n "$ACTIVITY" >/dev/null
shot 01-onboarding 8

while read -r name link wait; do
  [ -z "$name" ] && continue
  open_link "$link"
  shot "$name" "$wait"
done <<'LIST'
02-today kvartet://today 15
03-painting kvartet://item/painting-above-eternal-peace 10
04-slow-looking kvartet://item/painting-above-eternal-peace?open=look 10
05-article kvartet://item/article-cage-4-33 6
06-reader kvartet://item/article-voynich-manuscript?open=reader 25
07-album kvartet://item/album-bon-iver-for-emma 12
08-film kvartet://item/film-fargo 12
09-archive kvartet://archive 6
10-journal kvartet://journal 6
11-settings kvartet://settings 6
LIST

adb shell "cmd uimode night yes"
sleep 5
demo_status_bar
open_link kvartet://today
shot 12-today-dark 10
open_link kvartet://item/painting-hunters-in-the-snow
shot 13-painting-dark 10

for file in "$OUT"/*.png; do
  python3 - "$file" <<'PY'
import sys
from PIL import Image
path = sys.argv[1]
image = Image.open(path).convert("RGB")
image.thumbnail((700, 1500))
image.save(path[:-4] + ".jpg", quality=80)
PY
  rm "$file"
done
ls -la "$OUT"

echo "--- Ошибки приложения ---"
adb logcat -d -s AndroidRuntime:E Kvartet:* | tail -n 80
