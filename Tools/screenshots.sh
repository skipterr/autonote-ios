#!/bin/bash
# Запускает AutoNote в симуляторе iPhone с тестовыми данными и снимает скриншоты экранов.
set -euo pipefail

APP="$1"          # путь к AutoNote.app, собранному для симулятора
OUT="${2:-shots}"
mkdir -p "$OUT"

UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
ios = sorted((k for k in d if "iOS" in k), reverse=True)
for k in ios:
    for x in d[k]:
        if x["name"].startswith("iPhone") and "Pro" in x["name"] and "Max" not in x["name"]:
            print(x["udid"]); sys.exit()
for k in ios:
    for x in d[k]:
        if x["name"].startswith("iPhone"):
            print(x["udid"]); sys.exit()
')
echo "simulator: $UDID"
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularBars 4 --wifiBars 3 || true
xcrun simctl install "$UDID" "$APP"

BUNDLE=com.autonote.app
LOCALE=(-AppleLanguages "(ru)" -AppleLocale ru_RU)

shot() {   # имя, аргументы запуска...
  local name="$1"; shift
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" "${LOCALE[@]}" "$@" >/dev/null
  sleep 5
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
  echo "shot $name"
}

for mode in light dark; do
  xcrun simctl ui "$UDID" appearance "$mode"
  shot "$mode-1-home"      -demo YES -tab 0
  shot "$mode-2-history"   -demo YES -tab 1
  shot "$mode-3-reminders" -demo YES -tab 2
  shot "$mode-4-settings"  -demo YES -tab 3
  shot "$mode-5-editor"    -demo YES -tab 0 -sheet editor
  shot "$mode-6-onboarding" -demo YES -onboarding YES
done

# главная, прокрученная вниз
xcrun simctl ui "$UDID" appearance light
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" "${LOCALE[@]}" -demo YES -tab 0 -scroll bottom >/dev/null
sleep 5
xcrun simctl io "$UDID" screenshot "$OUT/light-1b-home-bottom.png" >/dev/null
