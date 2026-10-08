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

# Every edit below is followed by a grep that fails the script if it didn't
# take. A pattern that stops matching after a Flutter template change would
# otherwise be skipped silently and only surface later as a runtime failure
# (this already happened once: the AppDelegate template changed shape).

plist=ios/Runner/Info.plist
if ! grep -q NSLocationWhenInUseUsageDescription "$plist"; then
  perl -0pi -e 's#</dict>\n</plist>#\t<key>NSLocationWhenInUseUsageDescription</key>\n\t<string>AchaaGo needs your location to set the pickup point and show nearby drivers.</string>\n</dict>\n</plist>#' "$plist"
fi
grep -q NSLocationWhenInUseUsageDescription "$plist" || { echo "prepare_ios.sh: Info.plist location-permission edit didn't take (template changed?)" >&2; exit 1; }

# The server is plain HTTP until it gets a domain + HTTPS — the iOS
# counterpart of usesCleartextTraffic in prepare_android.sh. Remove both
# together. (Dart's own HTTP client may not be subject to App Transport
# Security at all, but native plugins are, and this costs nothing.)
if ! grep -q NSAppTransportSecurity "$plist"; then
  perl -0pi -e 's#</dict>\n</plist>#\t<key>NSAppTransportSecurity</key>\n\t<dict>\n\t\t<key>NSAllowsArbitraryLoads</key>\n\t\t<true/>\n\t</dict>\n</dict>\n</plist>#' "$plist"
fi
grep -q NSAppTransportSecurity "$plist" || { echo "prepare_ios.sh: Info.plist App Transport Security edit didn't take (template changed?)" >&2; exit 1; }

# google_maps_flutter's iOS side needs GMSServices.provideAPIKey() called
# before any map is created. There's no manifest-style meta-data slot like
# Android, so the key is baked into AppDelegate.swift's source here, the
# same way prepare_android.sh bakes it into the manifest. It comes from
# Perl's $ENV, not shell interpolation, for the same reason as there: this
# whole -e argument is single-quoted, so a bash "$VAR" would never expand —
# it'd write that literal text into the source instead of the key.
# Without a key a non-empty placeholder goes in, not "": an empty string
# might be treated as "never initialised" (unverified); an invalid key just
# gives a blank map. The pattern matches both the current template
# (register(with: engineBridge.pluginRegistry)) and the older (with: self).
appdelegate=ios/Runner/AppDelegate.swift
if ! grep -q "import GoogleMaps" "$appdelegate"; then
  perl -pi -e 's#^import Flutter#import Flutter\nimport GoogleMaps#' "$appdelegate"
fi
if ! grep -q "GMSServices.provideAPIKey" "$appdelegate"; then
  perl -0pi -e 'my $key = $ENV{GOOGLE_MAPS_API_KEY_IOS} || "NO_IOS_MAPS_KEY_CONFIGURED"; s#(GeneratedPluginRegistrant\.register\(with: [^)]*\))#GMSServices.provideAPIKey("$key")\n    $1#' "$appdelegate"
fi
grep -q "import GoogleMaps" "$appdelegate" || { echo "prepare_ios.sh: AppDelegate.swift's GoogleMaps import didn't take (template changed?). Current content:" >&2; cat "$appdelegate" >&2; exit 1; }
grep -q "GMSServices.provideAPIKey" "$appdelegate" || { echo "prepare_ios.sh: AppDelegate.swift's provideAPIKey call didn't take (template changed?). Current content:" >&2; cat "$appdelegate" >&2; exit 1; }
