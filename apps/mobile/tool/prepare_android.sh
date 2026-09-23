#!/usr/bin/env bash
# Generates the android/ project (not committed, see README) and adds the
# manifest entries this app needs. Safe to re-run.
set -euo pipefail
cd "$(dirname "$0")/.."

had_widget_test=0
[ -f test/widget_test.dart ] && had_widget_test=1

flutter create --platforms=android --org mn.achaago .

# flutter create adds a counter-app smoke test that references a MyApp class
# this project doesn't have.
[ "$had_widget_test" = 0 ] && rm -f test/widget_test.dart

manifest=android/app/src/main/AndroidManifest.xml
if ! grep -q ACCESS_FINE_LOCATION "$manifest"; then
  # usesCleartextTraffic: the server is plain HTTP until it gets a domain + HTTPS.
  perl -0pi -e 's#<application#<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n    <application android:usesCleartextTraffic="true"#' "$manifest"
fi
perl -pi -e 's#android:label="[^"]*"#android:label="AchaaGo"#' "$manifest"
