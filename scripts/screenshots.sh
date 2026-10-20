#!/bin/bash
# Снимает скриншоты приложения в симуляторе iPhone.
# Использование: scripts/screenshots.sh <путь/к/Kvartet.app> <папка-для-скриншотов>
# Нужна Debug-сборка (в ней работает аргумент -skipOnboarding).
set -euo pipefail

APP="$1"
OUT="$2"
mkdir -p "$OUT"
rm -f "$OUT"/*.jpg
RAW="$(mktemp -d)"

BUNDLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist")
echo "Bundle: $BUNDLE"

# Отвечает ли iTunes Search API этой машине (оттуда берутся обложки и постеры).
itunes_check() {
  local code count
  code=$(curl -s -o "$RAW/itunes.json" -w "%{http_code}" "https://itunes.apple.com/search?$1&country=us&limit=5" || echo "000")
  count=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["resultCount"])' "$RAW/itunes.json" 2>/dev/null || echo "?")
  echo "iTunes: HTTP $code, найдено: $count — $1"
}
itunes_check "term=Fargo&media=movie&entity=movie"
sleep 3
itunes_check "term=Bon%20Iver%20For%20Emma%2C%20Forever%20Ago&media=music&entity=album"
sleep 3
itunes_check "term=Nils%20Frahm%20Felt&media=music&entity=album"

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

# Журнал приложения (ошибки сети, ненайденные обложки) — печатается в конце.
xcrun simctl spawn "$UDID" log stream --level info --predicate 'subsystem == "Kvartet"' >"$RAW/app.log" 2>&1 &
LOG_PID=$!

shot() {
  sleep "$2"
  xcrun simctl io "$UDID" screenshot --type=png "$RAW/$1.png" >/dev/null 2>&1
  echo "📸 $1"
}

# Перезапуск приложения сразу на нужном экране (аргумент -openURL работает в Debug-сборке;
# simctl openurl для своей схемы показывает системный вопрос «Открыть в …?»).
relaunch_with() {
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 1
  xcrun simctl launch "$UDID" "$BUNDLE" -skipOnboarding -openURL "$1" >/dev/null
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
06-reader-wikipedia kvartet://item/article-voynich-manuscript?open=reader 22
07-album kvartet://item/album-nils-frahm-felt 10
08-film kvartet://item/film-into-great-silence 10
09-reader-arzamas kvartet://item/article-arzamas-pasternak-bruegel?open=reader 20
10-album-2 kvartet://item/album-bon-iver-for-emma 10
11-film-2 kvartet://item/film-fargo 10
12-archive kvartet://archive 5
13-journal kvartet://journal 5
14-settings kvartet://settings 5
EOF

# Тёмная тема.
xcrun simctl ui "$UDID" appearance dark
relaunch_with "kvartet://today"
shot 15-today-dark 10
relaunch_with "kvartet://item/painting-hunters-in-the-snow"
shot 16-painting-dark 12
relaunch_with "kvartet://item/painting-hunters-in-the-snow?open=zoom"
shot 17-zoom-dark 10

# Уменьшаем и сохраняем в JPEG, чтобы не раздувать репозиторий.
for file in "$RAW"/*.png; do
  base=$(basename "$file" .png)
  sips -Z 1400 -s format jpeg -s formatOptions 80 "$file" --out "$OUT/$base.jpg" >/dev/null
done
ls -la "$OUT"

kill "$LOG_PID" >/dev/null 2>&1 || true
echo "--- Журнал приложения ---"
tail -n 200 "$RAW/app.log" || true
