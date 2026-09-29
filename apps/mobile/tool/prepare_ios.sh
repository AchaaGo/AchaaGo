#!/usr/bin/env bash
# Generates the ios/ project (not committed, see README) and adds the
# Info.plist/AppDelegate entries this app needs. Safe to re-run. Requires a
# Mac with Xcode — Flutter's iOS tooling doesn't run anywhere else.
set -euo pipefail
cd "$(dirname "$0")/.."

had_widget_test=0
[ -f test/widget_test.dart ] && had_widget_test=1

flutter create --platforms=ios --org mn.achaago .

# flutter create adds a counter-app smoke test that references a MyApp class
# this project doesn't have.
[ "$had_widget_test" = 0 ] && rm -f test/widget_test.dart

plist=ios/Runner/Info.plist
if ! grep -q NSLocationWhenInUseUsageDescription "$plist"; then
  perl -0pi -e 's#</dict>\n</plist>#\t<key>NSLocationWhenInUseUsageDescription</key>\n\t<string>AchaaGo needs your location to set the pickup point and show nearby drivers.</string>\n</dict>\n</plist>#' "$plist"
fi
# A failed substitution above would silently leave the permission missing —
# no error, just a crash the first time the app asks for location, possibly
# weeks from now on someone else's Mac. Fail here instead, loudly, in case a
# future Flutter version changes Info.plist's template enough that the
# pattern above stops matching.
grep -q NSLocationWhenInUseUsageDescription "$plist" || { echo "prepare_ios.sh: Info.plist location-permission edit didn't take (template changed?)" >&2; exit 1; }

# google_maps_flutter's iOS side needs GMSServices.provideAPIKey() called
# before anything else touches the SDK — there's no manifest-style
# meta-data slot like Android, so the key is baked directly into
# AppDelegate.swift's source here, the same way prepare_android.sh bakes
# it into the manifest, so local setup without a key still works (Google's
# docs say an empty/invalid key degrades to blank tiles, same as Android —
# unconfirmed against a real run here; see README). Like the Android key,
# this comes from Perl's $ENV, not shell interpolation, for the same
# reason: this whole -e argument is single-quoted, so a bash "$VAR" here
# would never expand — it'd write that literal text into the source
# instead of the key.
appdelegate=ios/Runner/AppDelegate.swift
if ! grep -q GoogleMaps "$appdelegate"; then
  perl -pi -e 's#^import Flutter#import Flutter\nimport GoogleMaps#' "$appdelegate"
  perl -0pi -e 'my $key = $ENV{GOOGLE_MAPS_API_KEY_IOS} // ""; s#(GeneratedPluginRegistrant\.register\(with: self\))#GMSServices.provideAPIKey("$key")\n    $1#' "$appdelegate"
fi
# Same reasoning as the Info.plist check above: a silently-skipped edit here
# means google_maps_flutter's iOS side never gets provideAPIKey() called at
# all, which fails at runtime, not at build time — fail loudly here instead.
grep -q "import GoogleMaps" "$appdelegate" || { echo "prepare_ios.sh: AppDelegate.swift's GoogleMaps import didn't take (template changed?). Current content:" >&2; cat "$appdelegate" >&2; exit 1; }
grep -q "GMSServices.provideAPIKey" "$appdelegate" || { echo "prepare_ios.sh: AppDelegate.swift's provideAPIKey call didn't take (template changed?). Current content:" >&2; cat "$appdelegate" >&2; exit 1; }
