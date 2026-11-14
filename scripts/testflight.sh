#!/usr/bin/env bash
# Build, sign and upload the Detent iOS app (with its AutoFill extension) to App Store Connect
# for TestFlight. The same approach as the other apps' scripts/testflight.sh.
#
# Bumps the iOS build number (each upload needs a new one), archives without signing, then exports
# with automatic App Store signing and uploads. Archiving unsigned avoids needing a registered
# device for a development profile; the export signs with the team's cloud-managed distribution
# certificate.
#
# Authentication: with Config/testflight.env (see testflight.env.example), it uses that App Store
# Connect API key. Otherwise Xcode must be signed in to an account on the team.
#
# Usage: scripts/testflight.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT=Detent.xcodeproj
PROJECT_FILE="$PROJECT/project.xcproj"
TEAM=3N4984X523
# The App Store Connect record "Detent" shares its bundle ID with the Mac app.
APP_ID=com.colinbm.detent
EXTENSION_ID=com.colinbm.detent.autofill
WORK="$(mktemp -d)"

AUTH=()
if [ -f Config/testflight.env ]; then
  # shellcheck disable=SC1091
  source Config/testflight.env
  [ -f "$ASC_KEY_PATH" ] || { echo "API key not found: $ASC_KEY_PATH" >&2; exit 1; }
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID")
  [ -n "${ASC_ISSUER_ID:-}" ] && AUTH+=(-authenticationKeyIssuerID "$ASC_ISSUER_ID")
  echo "Using App Store Connect API key $ASC_KEY_ID"
fi

# The iOS app and its extension share a build number, which must match; the Mac app keeps its own.
cp "$PROJECT_FILE" "$WORK/project.xcproj"
read -r BUILD NEXT < <(python3 - "$PROJECT_FILE" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
builds = set()
def bump(match):
    builds.add(int(match.group(2)))
    return f'{match.group(1)}"{int(match.group(2)) + 1}"'
for target in ("Detent iOS", "Detent AutoFill"):
    # A target runs from its name, followed by its id, to where the next target starts.
    start = re.search(rf'"name": "{re.escape(target)}",\s*"id"', text).start()
    ends = [i for i in (text.find("\n    }, {", start), text.find("\n  ],", start)) if i >= 0]
    end = min(ends)
    block, count = re.subn(r'("CURRENT_PROJECT_VERSION": )"(\d+)"', bump, text[start:end], count=1)
    if count != 1:
        sys.exit(f"No build number found for {target}")
    text = text[:start] + block + text[end:]
if len(builds) != 1:
    sys.exit(f"The iOS app and extension have different build numbers: {sorted(builds)}")
open(path, "w").write(text)
build = builds.pop()
print(build, build + 1)
PY
)
# Put the build number back if anything below fails, so a failed upload doesn't use one up.
trap 'status=$?; if [ $status -ne 0 ]; then cp "$WORK/project.xcproj" "$PROJECT_FILE"; echo "Upload failed; build number left at $BUILD." >&2; fi; rm -rf "$WORK"' EXIT
echo "Build $BUILD → $NEXT (team $TEAM)"

ARCHIVE="$WORK/Detent.xcarchive"
xcodebuild -project "$PROJECT" -scheme "Detent iOS" -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  CODE_SIGNING_ALLOWED=NO archive -quiet

# An unsigned app carries no entitlements, and the export signs with only what the archive
# already has, so the keychain group and AutoFill would be dropped. Sign ad hoc with each
# bundle's entitlements, resolved as a signed build would have them, for the export to keep.
entitlements() { # source, bundle ID, output
  sed "s/\$(AppIdentifierPrefix)/$TEAM./g" "$1" > "$3"
  /usr/libexec/PlistBuddy -c "Add :application-identifier string $TEAM.$2" "$3"
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM" "$3"
}
APP="$ARCHIVE/Products/Applications/Detent iOS.app"
entitlements Config/Detent-AutoFill.entitlements "$EXTENSION_ID" "$WORK/autofill.entitlements"
entitlements Config/Detent-iOS.entitlements "$APP_ID" "$WORK/app.entitlements"
codesign --force --sign - --entitlements "$WORK/autofill.entitlements" --generate-entitlement-der \
  "$APP/PlugIns/Detent AutoFill.appex"
codesign --force --sign - --entitlements "$WORK/app.entitlements" --generate-entitlement-der "$APP"

cat > "$WORK/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>$TEAM</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>destination</key>
	<string>upload</string>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$WORK/export" \
  -exportOptionsPlist "$WORK/ExportOptions.plist" -allowProvisioningUpdates "${AUTH[@]}" -quiet

echo "Uploaded build $NEXT. It appears in TestFlight once App Store Connect has processed it (usually 5–30 minutes)."
echo "Commit the build number change: git commit -am 'iOS build $NEXT'"
