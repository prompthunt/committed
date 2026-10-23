#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/CommitStandings.xcodeproj"
SCHEME="CommitStandings"
CONFIGURATION="Release"
APP_DISPLAY_NAME="Committed"
APP_BUNDLE_NAME="${APP_DISPLAY_NAME}.app"
DEFAULT_TEAM_ID="82P3N9JUM7"
DEFAULT_BUNDLE_ID="com.digg.commitstandings"
NOTARY_PROFILE="${NOTARY_PROFILE:-CommitStandingsNotary}"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"
RELEASE_BUNDLE_ID="${PRODUCT_BUNDLE_IDENTIFIER:-${DEFAULT_BUNDLE_ID}}"
SPARKLE_VERSION="${SPARKLE_VERSION:-2.9.2}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-Digg Commit Standings}"
# Enclosure URL prefix for the appcast. Default is computed per-release below (a permanent
# per-tag URL) once the version is known — see the APPCAST_DOWNLOAD_URL_PREFIX assignment after
# VERSION is read. An explicit env override still wins. Trailing slash required: generate_appcast
# appends the archive filename to this prefix.
APPCAST_DOWNLOAD_URL_PREFIX="${APPCAST_DOWNLOAD_URL_PREFIX:-}"
BUILD_ROOT="${ROOT_DIR}/.build/distribution"
SPARKLE_CACHE_DIR="${ROOT_DIR}/.build/sparkle-tools"
SPARKLE_TOOLS_DIR="${SPARKLE_TOOLS_DIR:-${SPARKLE_CACHE_DIR}/Sparkle-${SPARKLE_VERSION}}"
SPARKLE_ARCHIVES_DIR="${BUILD_ROOT}/sparkle-archives"
DIST_DIR="${ROOT_DIR}/dist"
ARCHIVE_PATH="${BUILD_ROOT}/CommitStandings.xcarchive"
EXPORT_PATH="${BUILD_ROOT}/export"
DMG_ROOT="${BUILD_ROOT}/dmg-root"
EXPORT_OPTIONS_PLIST="${BUILD_ROOT}/ExportOptions.plist"
SKIP_NOTARIZATION=0
SKIP_GIT_CHECK=0
DRY_RUN=0
CHECK_ONLY=0

usage() {
    cat <<'USAGE'
Package Committed as a signed, drag-to-Applications DMG.

Required environment:
  none

Optional environment:
  TEAM_ID                 Apple Developer Team ID. Default: 82P3N9JUM7 (Digg)
  PRODUCT_BUNDLE_IDENTIFIER Release bundle ID. Default: com.digg.commitstandings
  NOTARY_PROFILE          notarytool keychain profile. Default: CommitStandingsNotary
  MACOSX_DEPLOYMENT_TARGET Release deployment target. Default: 26.0 (matches the SwiftUI app target)
  SPARKLE_ACCOUNT         Keychain account for Sparkle signing. Default: Digg Commit Standings
  SPARKLE_PRIVATE_KEY     Private EdDSA key for CI appcast signing.
  SPARKLE_PRIVATE_KEY_FILE Private EdDSA key file for CI appcast signing.
  APPCAST_DOWNLOAD_URL_PREFIX Download URL prefix for appcast enclosures.

Options:
  --check                Check release signing/notary readiness and exit.
  --skip-notarization     Build and create the DMG, but do not submit/staple it.
  --skip-git-check        Allow packaging with uncommitted changes.
  --dry-run               Print the resolved release settings and exit.
  -h, --help              Show this help.

One-time notary profile setup:
  xcrun notarytool store-credentials "CommitStandingsNotary" \
    --apple-id "you@example.com" \
    --team-id "TEAMID1234" \
    --password "app-specific-password"
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-notarization)
            SKIP_NOTARIZATION=1
            shift
            ;;
        --skip-git-check)
            SKIP_GIT_CHECK=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --check)
            CHECK_ONLY=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 2
            ;;
    esac
done

run() {
    echo "+ $*"
    "$@"
}

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required tool: $1" >&2
        exit 1
    fi
}

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "${ROOT_DIR}/CommitStandings/Info.plist"
}

print_release_settings() {
    echo "Release settings"
    echo "  project:             ${PROJECT_PATH}"
    echo "  scheme:              ${SCHEME}"
    echo "  configuration:       ${CONFIGURATION}"
    echo "  team:                ${TEAM_ID}"
    echo "  bundle id:           ${RELEASE_BUNDLE_ID}"
    echo "  deployment target:   macOS ${DEPLOYMENT_TARGET}"
    echo "  notary profile:      ${NOTARY_PROFILE}"
    echo "  Sparkle account:     ${SPARKLE_ACCOUNT}"
    echo "  appcast URL prefix:  ${APPCAST_DOWNLOAD_URL_PREFIX}"
    echo "  skip notarization:   ${SKIP_NOTARIZATION}"
    echo "  output:              ${FINAL_DMG}"
    echo "  update zip:          ${FINAL_UPDATE_ZIP}"
    echo "  appcast:             ${FINAL_APPCAST}"
}

developer_id_identity() {
    security find-identity -v -p codesigning 2>/dev/null \
        | grep -F "Developer ID Application" \
        | grep -F "(${TEAM_ID})" \
        | sed -n '1p'
}

check_release_readiness() {
    local failed=0
    local identity=""

    echo
    echo "Release readiness"

    if identity="$(developer_id_identity)" && [[ -n "${identity}" ]]; then
        echo "  [ok] Developer ID Application certificate for team ${TEAM_ID}"
        echo "       ${identity}"
    else
        echo "  [missing] Developer ID Application certificate for team ${TEAM_ID}"
        echo "            Add the Digg team in Xcode, then create/download a Developer ID Application certificate."
        failed=1
    fi

    if xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
        echo "  [ok] notarytool profile '${NOTARY_PROFILE}'"
    else
        echo "  [missing] notarytool profile '${NOTARY_PROFILE}'"
        echo "            Store credentials with xcrun notarytool store-credentials."
        failed=1
    fi

    ensure_sparkle_tools
    if "${SPARKLE_TOOLS_DIR}/bin/generate_keys" --account "${SPARKLE_ACCOUNT}" -p >/dev/null 2>&1; then
        echo "  [ok] Sparkle signing key '${SPARKLE_ACCOUNT}'"
    elif [[ -n "${SPARKLE_PRIVATE_KEY:-}" || -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
        echo "  [ok] Sparkle signing key supplied through environment"
    else
        echo "  [missing] Sparkle signing key '${SPARKLE_ACCOUNT}'"
        echo "            Run: ${SPARKLE_TOOLS_DIR}/bin/generate_keys --account \"${SPARKLE_ACCOUNT}\""
        failed=1
    fi

    if xcodebuild \
        -project "${PROJECT_PATH}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -showBuildSettings \
        DEVELOPMENT_TEAM="${TEAM_ID}" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="Developer ID Application" \
        PRODUCT_BUNDLE_IDENTIFIER="${RELEASE_BUNDLE_ID}" \
        MACOSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" >/dev/null 2>&1; then
        echo "  [ok] Xcode can resolve release build settings"
    else
        echo "  [failed] Xcode could not resolve release build settings"
        failed=1
    fi

    echo
    if [[ "${failed}" -eq 0 ]]; then
        echo "Ready to create the friend-install DMG:"
        echo "  ./scripts/package-release.sh"
    else
        echo "Not ready yet. The missing items above require Apple account/team credentials."
    fi

    return "${failed}"
}

ensure_sparkle_tools() {
    local tarball="${SPARKLE_CACHE_DIR}/Sparkle-${SPARKLE_VERSION}.tar.xz"

    if [[ -x "${SPARKLE_TOOLS_DIR}/bin/generate_appcast" ]]; then
        return
    fi

    mkdir -p "${SPARKLE_CACHE_DIR}" "${SPARKLE_TOOLS_DIR}"
    if [[ ! -f "${tarball}" ]]; then
        run curl --fail --location \
            --output "${tarball}" \
            "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
    fi

    run tar -xf "${tarball}" -C "${SPARKLE_TOOLS_DIR}" --strip-components=1
}

run_generate_appcast() {
    local cmd=(
        "${SPARKLE_TOOLS_DIR}/bin/generate_appcast"
        "--download-url-prefix" "${APPCAST_DOWNLOAD_URL_PREFIX}"
        "--maximum-versions" "1"
        "-o" "${FINAL_APPCAST}"
    )

    if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
        cmd+=("--ed-key-file" "${SPARKLE_PRIVATE_KEY_FILE}")
    elif [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
        cmd+=("--ed-key-file" "-")
    else
        cmd+=("--account" "${SPARKLE_ACCOUNT}")
    fi

    cmd+=("${SPARKLE_ARCHIVES_DIR}")

    if [[ -n "${SPARKLE_PRIVATE_KEY:-}" && -z "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
        echo "+ printf '%s' \"\$SPARKLE_PRIVATE_KEY\" | ${cmd[*]}"
        printf '%s' "${SPARKLE_PRIVATE_KEY}" | "${cmd[@]}"
    else
        run "${cmd[@]}"
    fi
}

TEAM_ID="${TEAM_ID:-${DEFAULT_TEAM_ID}}"

require_tool xcodebuild
require_tool xcrun
require_tool hdiutil
require_tool codesign
require_tool spctl
require_tool ditto
require_tool security
require_tool curl

VERSION="$(plist_value CFBundleShortVersionString)"
BUILD_NUMBER="$(plist_value CFBundleVersion)"
GIT_SHA="$(git -C "${ROOT_DIR}" rev-parse --short HEAD 2>/dev/null || echo local)"

# Default the appcast enclosure prefix to the PERMANENT per-tag release URL for this version
# (releases/download/v<version>/), not releases/latest/download/. The latest/download path only
# serves assets on the current latest release, so once a version is superseded its enclosure
# 404s — breaking Sparkle for anyone whose cached appcast still references the old file
# ("error occurred while downloading the update"). The per-tag URL is permanent and never 404s.
# Assumes the GitHub release tag is v<version> (e.g. v0.1.34). An explicit env override wins.
if [[ -z "${APPCAST_DOWNLOAD_URL_PREFIX}" ]]; then
    APPCAST_DOWNLOAD_URL_PREFIX="https://github.com/prompthunt/commit-standings-releases/releases/download/v${VERSION}/"
fi
DMG_BASENAME="CommitStandings-${VERSION}-${BUILD_NUMBER}-${GIT_SHA}"
FINAL_DMG="${DIST_DIR}/${DMG_BASENAME}.dmg"
FINAL_UPDATE_ZIP="${DIST_DIR}/${DMG_BASENAME}.app.zip"
FINAL_APPCAST="${DIST_DIR}/appcast.xml"
RW_DMG="${BUILD_ROOT}/${DMG_BASENAME}.rw.dmg"
APP_NOTARY_ZIP="${BUILD_ROOT}/${DMG_BASENAME}.app.zip"

print_release_settings

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
    check_release_readiness
    exit $?
fi

if [[ "${DRY_RUN}" -eq 1 ]]; then
    exit 0
fi

if [[ "${SKIP_GIT_CHECK}" -eq 0 ]] && [[ -n "$(git -C "${ROOT_DIR}" status --porcelain)" ]]; then
    echo "Working tree has uncommitted changes. Commit them first, or pass --skip-git-check for a local test package." >&2
    exit 1
fi

rm -rf "${BUILD_ROOT}"
mkdir -p "${BUILD_ROOT}" "${DIST_DIR}" "${SPARKLE_ARCHIVES_DIR}"
ensure_sparkle_tools

cat > "${EXPORT_OPTIONS_PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>export</string>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>manageAppVersionAndBuildNumber</key>
    <false/>
</dict>
</plist>
EOF

run xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -archivePath "${ARCHIVE_PATH}" \
    archive \
    DEVELOPMENT_TEAM="${TEAM_ID}" \
    PRODUCT_BUNDLE_IDENTIFIER="${RELEASE_BUNDLE_ID}" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    ENABLE_HARDENED_RUNTIME=YES \
    MACOSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
    OTHER_CODE_SIGN_FLAGS="--timestamp"

run xcodebuild \
    -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}"

EXPORTED_APP="$(find "${EXPORT_PATH}" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "${EXPORTED_APP}" ]]; then
    echo "Could not find exported .app in ${EXPORT_PATH}" >&2
    exit 1
fi

run codesign --verify --deep --strict --verbose=2 "${EXPORTED_APP}"

if [[ "${SKIP_NOTARIZATION}" -eq 0 ]]; then
    run ditto -c -k --keepParent "${EXPORTED_APP}" "${APP_NOTARY_ZIP}"
    run xcrun notarytool submit "${APP_NOTARY_ZIP}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait
    run xcrun stapler staple "${EXPORTED_APP}"
    run xcrun stapler validate "${EXPORTED_APP}"
    run spctl --assess --type execute --verbose=4 "${EXPORTED_APP}"
fi

run ditto -c -k --keepParent "${EXPORTED_APP}" "${SPARKLE_ARCHIVES_DIR}/${DMG_BASENAME}.app.zip"
# NOTE: deliberately no .app.md release-notes file. generate_appcast adds a
# <sparkle:releaseNotesLink> only when a notes file sits next to the archive, and
# that link must be uploaded as a release asset or Sparkle 404s fetching it and
# aborts the whole update. Skipping notes keeps the appcast self-contained.
run_generate_appcast
run cp "${SPARKLE_ARCHIVES_DIR}/${DMG_BASENAME}.app.zip" "${FINAL_UPDATE_ZIP}"

rm -rf "${DMG_ROOT}" "${RW_DMG}" "${FINAL_DMG}"
mkdir -p "${DMG_ROOT}"
run ditto "${EXPORTED_APP}" "${DMG_ROOT}/${APP_BUNDLE_NAME}"
run ln -s /Applications "${DMG_ROOT}/Applications"

run hdiutil create \
    -volname "${APP_DISPLAY_NAME}" \
    -srcfolder "${DMG_ROOT}" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "${RW_DMG}"

run hdiutil convert "${RW_DMG}" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov \
    -o "${FINAL_DMG}"

run codesign --force --sign "Developer ID Application" --timestamp "${FINAL_DMG}"
run codesign --verify --verbose=2 "${FINAL_DMG}"
run hdiutil verify "${FINAL_DMG}"

if [[ "${SKIP_NOTARIZATION}" -eq 0 ]]; then
    run xcrun notarytool submit "${FINAL_DMG}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait
    run xcrun stapler staple "${FINAL_DMG}"
    run xcrun stapler validate "${FINAL_DMG}"
    run spctl --assess --type open --context context:primary-signature --verbose=4 "${FINAL_DMG}"
else
    echo "Skipped notarization and Gatekeeper assessment. This DMG is for local packaging tests, not friend distribution."
fi

# Stable-named copy of the DMG. GitHub's `releases/latest/download/<name>` redirect only
# resolves when an identically-named asset exists on the newest release, so a permanent
# share link (…/releases/latest/download/Committed.dmg) requires uploading this on EVERY
# release alongside the versioned DMG. Same reason the appcast uses per-tag enclosure URLs.
STABLE_DMG="${DIST_DIR}/${APP_DISPLAY_NAME}.dmg"
run cp "${FINAL_DMG}" "${STABLE_DMG}"

echo
echo "Release DMG ready:"
echo "  ${FINAL_DMG}"
echo "  ${STABLE_DMG}  (stable share-link copy — upload this to the release too)"
echo
echo "Sparkle update artifacts ready:"
echo "  ${FINAL_UPDATE_ZIP}"
echo "  ${FINAL_APPCAST}"
