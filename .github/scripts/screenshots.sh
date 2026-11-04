#!/bin/bash
# Runs Prism in the iPhone and iPhone Duo simulators and saves screenshots of the main screens.
# Needs REDDIT_CLIENT_ID in the environment (from the repository secret).
set -uo pipefail

BUNDLE="com.shotatredline.prism"
OUT="screenshots"
mkdir -p "$OUT"

APP=$(find build/Build/Products -maxdepth 3 -path "*iphonesimulator*" -name "Prism.app" | head -1)
if [ -z "$APP" ]; then
  echo "::error::Simulator build of Prism.app not found."
  exit 1
fi
echo "App: $APP"

xcrun simctl list devicetypes > "$OUT/available-devices.txt"
xcrun simctl list runtimes >> "$OUT/available-devices.txt"

# Prints "<devicetype id> <runtime id>" for the newest device whose name matches the regex,
# paired with the newest iOS runtime that supports it.
pick() {
  python3 - "$1" <<'PY'
import json, re, subprocess, sys
pattern = re.compile(sys.argv[1])
types = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devicetypes", "-j"]))["devicetypes"]
runtimes = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "runtimes", "-j"]))["runtimes"]
runtimes = [r for r in runtimes if r.get("platform") == "iOS" and r.get("isAvailable")]
runtimes.sort(key=lambda r: [int(p) for p in r["version"].split(".") if p.isdigit()])
matches = [t for t in types if pattern.search(t["name"])]
for t in reversed(matches):
    for r in reversed(runtimes):
        supported = [d["identifier"] for d in r.get("supportedDeviceTypes", [])]
        if not supported or t["identifier"] in supported:
            print(t["identifier"], r["identifier"])
            sys.exit(0)
PY
}

shoot() {
  local label="$1" pattern="$2"
  local picked
  picked=$(pick "$pattern")
  if [ -z "$picked" ]; then
    echo "::warning::No simulator matching '$pattern' on this runner; skipping $label."
    return
  fi
  local type runtime udid
  read -r type runtime <<< "$picked"
  echo "== $label: $type on $runtime"
  udid=$(xcrun simctl create "prism-$label" "$type" "$runtime") || { echo "::warning::Couldn't create $label simulator."; return; }
  xcrun simctl boot "$udid"
  xcrun simctl bootstatus "$udid" -b > /dev/null
  xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiBars 3 || true
  xcrun simctl install "$udid" "$APP"
  xcrun simctl io "$udid" enumerate > "$OUT/$label-displays.txt" 2>&1 || true

  for mode in light dark; do
    xcrun simctl ui "$udid" appearance "$mode"
    for screen in feed post media subreddit; do
      xcrun simctl terminate "$udid" "$BUNDLE" > /dev/null 2>&1 || true
      xcrun simctl launch "$udid" "$BUNDLE" -clientID "$REDDIT_CLIENT_ID" -prismScreen "$screen" > /dev/null
      sleep 15
      xcrun simctl io "$udid" screenshot "$OUT/$label-$mode-$screen.png" > /dev/null 2>&1 \
        || echo "::warning::Screenshot failed: $label $mode $screen"
      # iPhone Duo has two displays; try to grab the other one as well.
      xcrun simctl io "$udid" screenshot --display=external "$OUT/$label-$mode-$screen-second-display.png" > /dev/null 2>&1 || true
    done
  done

  xcrun simctl shutdown "$udid" || true
  xcrun simctl delete "$udid" || true
}

shoot "iphone" '^iPhone [0-9]+ Pro$'
shoot "iphone-duo" 'iPhone Duo'

echo "Saved:"
ls -1 "$OUT"
