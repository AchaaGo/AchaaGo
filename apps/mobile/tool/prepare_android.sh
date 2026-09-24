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

# google_maps_flutter reads its key from this manifest meta-data at runtime.
# Empty is fine (the map just shows blank tiles) so local setup without a key still works.
# The key comes from Perl's $ENV, not shell interpolation: this whole -e
# argument is single-quoted, so a bash "$VAR" here would never expand — it'd
# write that literal text into the manifest instead of the real key.
if ! grep -q com.google.android.geo.API_KEY "$manifest"; then
  perl -0pi -e 'my $key = $ENV{GOOGLE_MAPS_API_KEY_ANDROID} // ""; s#</application>#    <meta-data android:name="com.google.android.geo.API_KEY" android:value="$key"/>\n    </application>#' "$manifest"
fi

# A fixed debug-signing keystore so the app's SHA-1 fingerprint is the same
# on every machine and CI run — without this, each fresh checkout/runner
# gets its own random debug key, and a Maps API key restricted to "Android
# apps" would only ever match one of them. The keystore file itself must
# NOT be committed to this repo (it's public): anyone who could download it
# could sign their own app with the same identity and use our Maps key
# through it, defeating the "Android apps" restriction entirely. It lives
# only as a base64 GitHub secret (see README.md), decoded here at build
# time. Its password is the public Android default, "android" — that part
# really isn't secret, only the key material is.
if [ -n "${MOBILE_DEBUG_KEYSTORE_BASE64:-}" ]; then
  mkdir -p "$HOME/.android"
  echo "$MOBILE_DEBUG_KEYSTORE_BASE64" | base64 -d > "$HOME/.android/debug.keystore"
fi
