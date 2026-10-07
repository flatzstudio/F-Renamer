#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT/MultitrackCleaner.xcodeproj"
SCHEME="MultitrackCleaner"

if [[ -z "${TEAM_ID:-}" || -z "${DEVELOPER_ID_APPLICATION_IDENTITY:-}" ]]; then
    printf '%s\n' 'Set TEAM_ID and DEVELOPER_ID_APPLICATION_IDENTITY to your own signing values.' >&2
    exit 2
fi
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    printf '%s\n' 'TEAM_ID must be a 10-character Apple Developer Team ID.' >&2
    exit 2
fi
case "$DEVELOPER_ID_APPLICATION_IDENTITY" in
    "Developer ID Application:"*) ;;
    *) printf '%s\n' 'The signing identity must be a Developer ID Application certificate, not Apple Development.' >&2; exit 2 ;;
esac
case "$DEVELOPER_ID_APPLICATION_IDENTITY" in
    *"($TEAM_ID)"*) ;;
    *) printf '%s\n' 'TEAM_ID does not match the selected Developer ID Application identity.' >&2; exit 2 ;;
esac

IDENTITIES="$(security find-identity -v -p codesigning)"
case "$IDENTITIES" in
    *"$DEVELOPER_ID_APPLICATION_IDENTITY"*) ;;
    *) printf '%s\n' 'The requested Developer ID Application identity is not available in the Keychain.' >&2; exit 2 ;;
esac

RUN_ID="$(date '+%Y%m%d-%H%M%S')"
RUN_DIR="${RELEASE_RUN_DIR:-$ROOT/build/release/$RUN_ID}"
if [[ -e "$RUN_DIR" ]]; then
    printf 'Release output already exists: %s\n' "$RUN_DIR" >&2
    exit 2
fi
mkdir -p "$RUN_DIR"
ARCHIVE="$RUN_DIR/F Renamer.xcarchive"
EXPORT_DIR="$RUN_DIR/export"
APP="$EXPORT_DIR/F Renamer.app"
EXTENSION="$APP/Contents/PlugIns/MultitrackCleanerFinderAction.appex"
ZIP="$RUN_DIR/F-Renamer-1.0.0-macOS-pre-notarization.zip"
OPTIONS="$(/usr/bin/mktemp "$RUN_DIR/export-options.XXXXXX")"
trap 'rm -f "$OPTIONS"' EXIT

/usr/libexec/PlistBuddy -c 'Add :method string developer-id' "$OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :destination string export' "$OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :signingStyle string manual' "$OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :signingCertificate string Developer ID Application' "$OPTIONS"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$OPTIONS"
/usr/libexec/PlistBuddy -c 'Add :stripSwiftSymbols bool true' "$OPTIONS"

xcodebuild clean \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$RUN_DIR/DerivedData" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID"

xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$RUN_DIR/DerivedData" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION_IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID"

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$OPTIONS"

if [[ ! -d "$APP" || ! -d "$EXTENSION" ]]; then
    printf '%s\n' 'Export is missing the app or embedded Finder extension.' >&2
    exit 1
fi

for PRODUCT in "$APP" "$EXTENSION"; do
    codesign --verify --deep --strict --verbose=2 "$PRODUCT"
    codesign -dvv "$PRODUCT" 2>&1
done

APP_EXECUTABLE="$APP/Contents/MacOS/F Renamer"
EXTENSION_EXECUTABLE="$EXTENSION/Contents/MacOS/MultitrackCleanerFinderAction"
for EXECUTABLE in "$APP_EXECUTABLE" "$EXTENSION_EXECUTABLE"; do
    ARCHITECTURES="$(lipo -archs "$EXECUTABLE")"
    if [[ "$ARCHITECTURES" != arm64 ]]; then
        printf 'Expected arm64-only executable, got %s: %s\n' "$ARCHITECTURES" "$EXECUTABLE" >&2
        exit 1
    fi
    file "$EXECUTABLE"
    otool -L "$EXECUTABLE"
done

plutil -lint "$APP/Contents/Info.plist" "$EXTENSION/Contents/Info.plist"
codesign -d --entitlements :- "$APP" 2>/dev/null
codesign -d --entitlements :- "$EXTENSION" 2>/dev/null

ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
unzip -t "$ZIP"
printf '\nPre-notarization artifact: %s\n' "$ZIP"
printf 'SHA-256: '
shasum -a 256 "$ZIP"
printf '%s\n' 'No notarization request was submitted by this script.'
