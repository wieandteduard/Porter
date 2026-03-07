#!/bin/zsh

set -euo pipefail

PROJECT="${PROJECT:-Porter.xcodeproj}"
SCHEME="${SCHEME:-Porter}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-Port Menu}"
OUTPUT_DIR="${OUTPUT_DIR:-dist}"
ARCHIVE_PATH="${OUTPUT_DIR}/${APP_NAME}.xcarchive"
EXPORT_APP_PATH="${OUTPUT_DIR}/${APP_NAME}.app"
STAGING_DIR="${OUTPUT_DIR}/dmg-staging"
STAGING_BACKGROUND_DIR="${STAGING_DIR}/.background"
ZIP_PATH="${OUTPUT_DIR}/${APP_NAME}.zip"
TEMP_DMG_PATH="${OUTPUT_DIR}/${APP_NAME}-temp.dmg"
DMG_PATH="${OUTPUT_DIR}/${APP_NAME}.dmg"
MOUNT_DIR="${OUTPUT_DIR}/${APP_NAME}-mount"
BACKGROUND_SOURCE_PATH="${BACKGROUND_SOURCE_PATH:-packaging/dmg-background.png}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"
NOTARY_APPLE_ID="${NOTARY_APPLE_ID:-}"
NOTARY_PASSWORD="${NOTARY_PASSWORD:-}"

: "${TEAM_ID:?Set TEAM_ID to your Apple Developer team ID.}"
: "${DEVELOPER_ID_APP:?Set DEVELOPER_ID_APP to your Developer ID Application signing identity.}"

cleanup_dmg_mount() {
  if mount | awk -v target="${MOUNT_DIR}" '$3 == target { found = 1 } END { exit found ? 0 : 1 }'; then
    hdiutil detach "${MOUNT_DIR}" >/dev/null 2>&1 || true
  fi
}

cleanup_dmg_mount
rm -rf "${ARCHIVE_PATH}" "${EXPORT_APP_PATH}" "${STAGING_DIR}" "${ZIP_PATH}" "${TEMP_DMG_PATH}" "${DMG_PATH}" "${MOUNT_DIR}"
mkdir -p "${OUTPUT_DIR}"

echo "Archiving ${APP_NAME}..."
xcodebuild archive \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -archivePath "${ARCHIVE_PATH}" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  CODE_SIGN_IDENTITY="${DEVELOPER_ID_APP}"

cp -R "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app" "${EXPORT_APP_PATH}"

echo "Verifying code signature..."
codesign --verify --deep --strict --verbose=2 "${EXPORT_APP_PATH}"

echo "Creating notarization archive..."
/usr/bin/ditto -c -k --keepParent "${EXPORT_APP_PATH}" "${ZIP_PATH}"

submit_for_notarization() {
  local artifact_path="$1"
  if [[ -n "${NOTARY_APPLE_ID}" && -n "${NOTARY_PASSWORD}" ]]; then
    xcrun notarytool submit "${artifact_path}" \
      --apple-id "${NOTARY_APPLE_ID}" \
      --team-id "${TEAM_ID}" \
      --password "${NOTARY_PASSWORD}" \
      --wait
  else
    xcrun notarytool submit "${artifact_path}" \
      --keychain-profile "${NOTARY_PROFILE}" \
      --wait
  fi
}

echo "Submitting app for notarization..."
submit_for_notarization "${ZIP_PATH}"

echo "Stapling app notarization ticket..."
xcrun stapler staple "${EXPORT_APP_PATH}"

echo "Preparing DMG staging folder..."
mkdir -p "${STAGING_BACKGROUND_DIR}"
cp -R "${EXPORT_APP_PATH}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"
cp "${BACKGROUND_SOURCE_PATH}" "${STAGING_BACKGROUND_DIR}/background.png"

echo "Creating temporary DMG..."
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDRW \
  "${TEMP_DMG_PATH}"

echo "Attaching temporary DMG..."
mkdir -p "${MOUNT_DIR}"
hdiutil attach "${TEMP_DMG_PATH}" -mountpoint "${MOUNT_DIR}" -noverify -noautoopen

echo "Configuring Finder layout..."
osascript <<EOF
set dmgFolder to POSIX file "${MOUNT_DIR}" as alias
tell application "Finder"
  tell folder dmgFolder
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    try
      set sidebar width of container window to 0
    end try
    set bounds of container window to {200, 120, 740, 480}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 80
    set text size of opts to 12
    set background picture of opts to file ".background:background.png"
    set position of item "${APP_NAME}.app" of container window to {130, 160}
    set position of item "Applications" of container window to {410, 160}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF

echo "Detaching temporary DMG..."
hdiutil detach "${MOUNT_DIR}"

echo "Creating final DMG..."
hdiutil convert "${TEMP_DMG_PATH}" \
  -format UDZO \
  -o "${DMG_PATH}"
rm -f "${TEMP_DMG_PATH}"
rmdir "${MOUNT_DIR}" 2>/dev/null || true

echo "Signing DMG..."
codesign --force --sign "${DEVELOPER_ID_APP}" "${DMG_PATH}"

echo "Submitting DMG for notarization..."
submit_for_notarization "${DMG_PATH}"

echo "Stapling DMG notarization ticket..."
xcrun stapler staple "${DMG_PATH}"

echo "Release ready:"
echo "  App: ${EXPORT_APP_PATH}"
echo "  DMG: ${DMG_PATH}"
