#!/usr/bin/env bash
# Measures Wind Chimes' battery use on a real Android phone.
#
#   tool/battery_check.sh [minutes] [device-serial]
#
# Install a release or profile build first. For a true level drop, connect over wireless
# debugging (Developer options → Wireless debugging; `adb pair`, `adb connect`) so the phone is
# not charging; over USB the script still reports Android's own estimate of the app's drain.
# The screen stays on for the whole run (the app is meant to be watched), and the timeout is put
# back afterwards. Budget from docs/DESIGN.md: about 5 % an hour for the app itself.
set -euo pipefail

MINUTES=${1:-30}
SERIAL=${2:-}
PKG=com.example.wind_chimes
ADB=(adb)
[[ -n "$SERIAL" ]] && ADB=(adb -s "$SERIAL")

level() { "${ADB[@]}" shell dumpsys battery | awk -F': ' '/^  level:/ {print $2}' | tr -d '\r'; }

old_timeout=$("${ADB[@]}" shell settings get system screen_off_timeout | tr -d '\r')
restore() {
  "${ADB[@]}" shell settings put system screen_off_timeout "$old_timeout" >/dev/null
  "${ADB[@]}" shell dumpsys battery reset >/dev/null
}
trap restore EXIT

"${ADB[@]}" shell settings put system screen_off_timeout $(((MINUTES + 2) * 60 * 1000))
# Count this run as time on battery, even if a cable is connected.
"${ADB[@]}" shell dumpsys battery unplug
"${ADB[@]}" shell dumpsys batterystats --reset >/dev/null
"${ADB[@]}" shell am force-stop "$PKG"
"${ADB[@]}" shell am start -n "$PKG/.MainActivity" >/dev/null
"${ADB[@]}" shell input keyevent KEYCODE_WAKEUP

start=$(level)
echo "Running Wind Chimes for $MINUTES min, screen on; battery at $start %."
sleep $((MINUTES * 60))
end=$(level)

stats=$("${ADB[@]}" shell dumpsys batterystats --charged "$PKG" | tr -d '\r')
# Older Android prints the app's id as userId=, newer as appId=.
uid=$("${ADB[@]}" shell dumpsys package "$PKG" |
  awk 'match($0, /(userId|appId)=[0-9]+/) {split(substr($0, RSTART, RLENGTH), a, "="); print a[2]; exit}' |
  tr -d '\r')
capacity=$(awk -F'Capacity: ' '/Capacity: / {split($2, a, ","); print a[1]; exit}' <<<"$stats")
# Newer Android: "UID u0a229: 12.3 ( ... )"; older: "Uid u0a229: 12.3 ...".
app_uid="u0a$((uid - 10000))"
app_mah=$(awk -v id="$app_uid:" 'tolower($1) == "uid" && $2 == id {print $3; exit}' <<<"$stats")

echo
echo "Battery: $start % → $end % over $MINUTES min (the whole phone, screen included)."
if [[ -n "$app_mah" && -n "$capacity" && "$capacity" != "0" ]]; then
  awk -v mah="$app_mah" -v cap="$capacity" -v min="$MINUTES" 'BEGIN {
    printf "Android attributes %.1f mAh to the app: %.1f %% of %d mAh, about %.1f %% an hour.\n",
      mah, 100 * mah / cap, cap, 100 * mah / cap * 60 / min
  }'
else
  echo "Could not read the app's estimated drain; the full report follows."
  echo "$stats" | grep -iA40 "Estimated power use" | head -60
fi
