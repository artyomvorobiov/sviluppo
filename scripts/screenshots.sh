#!/bin/bash
# Снимает скриншоты приложения в симуляторе iPhone.
# Использование: scripts/screenshots.sh <путь/к/Kvartet.app> <папка-для-скриншотов>
# Нужна Debug-сборка (в ней работает аргумент -skipOnboarding).
set -euo pipefail

APP="$1"
OUT="$2"
mkdir -p "$OUT"
RAW="$(mktemp -d)"

BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
echo "Bundle: $BUNDLE"

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
devices = []
for runtime, items in sorted(data.items(), reverse=True):
    if "iOS" not in runtime:
        continue
    for item in items:
        devices.append((item["name"], item["udid"]))
for wanted in ["iPhone 16", "iPhone 17", "iPhone 16 Pro", "iPhone 15"]:
    for name, udid in devices:
        if name == wanted:
            print(udid)
            sys.exit(0)
print(next(udid for name, udid in devices if name.startswith("iPhone")))
')
echo "Simulator: $UDID"

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance light
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularMode active --cellularBars 4 || true
xcrun simctl install "$UDID" "$APP"

shot() {
  sleep "$2"
  xcrun simctl io "$UDID" screenshot --type=png "$RAW/$1.png" >/dev/null 2>&1
  echo "📸 $1"
}

relaunch_with() {
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl openurl "$UDID" "$1"
}

# Первый запуск — приветственный экран.
xcrun simctl launch "$UDID" "$BUNDLE"
shot 01-onboarding 6
xcrun simctl terminate "$UDID" "$BUNDLE" || true

# Выпуск дня (дальше приветствие уже не показывается).
xcrun simctl launch "$UDID" "$BUNDLE" -skipOnboarding
shot 02-today 15

# Экраны рекомендаций: kvartet://item/<id>[?open=reader|look|zoom]
while read -r name link wait; do
  [ -z "$name" ] && continue
  relaunch_with "$link"
  shot "$name" "$wait"
done <<'EOF'
03-painting kvartet://item/painting-above-eternal-peace 10
04-slow-looking kvartet://item/painting-above-eternal-peace?open=look 10
05-article kvartet://item/article-cage-4-33 6
06-reader-wikipedia kvartet://item/article-cage-4-33?open=reader 18
07-album kvartet://item/album-nils-frahm-felt 10
08-film kvartet://item/film-into-great-silence 10
09-reader-arzamas kvartet://item/article-arzamas-pasternak-bruegel?open=reader 20
10-album-2 kvartet://item/album-bon-iver-for-emma 10
11-film-2 kvartet://item/film-fargo 10
12-archive kvartet://archive 5
13-journal kvartet://journal 5
EOF

# Тёмная тема.
xcrun simctl ui "$UDID" appearance dark
relaunch_with "kvartet://today"
shot 14-today-dark 10
relaunch_with "kvartet://item/painting-hunters-in-the-snow"
shot 15-painting-dark 12

# Уменьшаем и сохраняем в JPEG, чтобы не раздувать репозиторий.
for file in "$RAW"/*.png; do
  base=$(basename "$file" .png)
  sips -Z 1400 -s format jpeg -s formatOptions 80 "$file" --out "$OUT/$base.jpg" >/dev/null
done
ls -la "$OUT"
