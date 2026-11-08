#!/usr/bin/env bash
#
# Upload the iPhone app to TestFlight and release it to every tester, internal and external.
# Run this for every TestFlight upload, so outside testers never fall behind. See
# docs/distribution.md → TestFlight.
#
#   1. Takes the next build number from App Store Connect (highest uploaded + 1), so the
#      project's CURRENT_PROJECT_VERSION doesn't need a commit per upload.
#   2. Archives the CommitStandingsiOS scheme (Release, so it uses the deployed relay) and uploads it.
#   3. Waits for processing, adds the build to the external "Friends" group, and submits it
#      for TestFlight beta review. Testers get it once Apple approves it. The internal
#      "Prompt Hunt" group gets every build without review.
#
# Usage:
#   scripts/testflight.sh --notes-file notes.txt
#
# The notes are the build's "What to Test" text, written with the release-notes skill as
# .agents/rules/testflight-notes.md requires: plain text, category headings and bullets kept.
# The script won't upload without them, and prints back what App Store Connect saved.
#
# Needs the asc CLI signed in to the Prompt Hunt team, and the team API key file for Xcode's
# cloud signing. Override any of these with environment variables:
#   ASC_KEY_ID              default: asc's default credential
#   ASC_ISSUER_ID           default: Prompt Hunt's issuer
#   ASC_PRIVATE_KEY_PATH    default: ~/.asc/keys/AuthKey_<ASC_KEY_ID>.p8
#   TESTFLIGHT_GROUPS       default: Friends (external groups to add the build to)
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ID="6831797452"   # App Store Connect: Committed: Commit Leaderboard
TEAM_ID="R36J43WZ34"  # Prompt Hunt, Inc.
BETA_GROUPS="${TESTFLIGHT_GROUPS:-Friends}"
OUT_DIR="${ROOT_DIR}/build/testflight"

cd "${ROOT_DIR}"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: the working tree has uncommitted changes. TestFlight builds come from a commit." >&2
  exit 1
fi
BRANCH="$(git branch --show-current)"
# A worktree can't check out main while another one has it, so main's commit detached counts too.
if [[ "${BRANCH}" != "main" && "$(git rev-parse HEAD)" != "$(git rev-parse origin/main 2>/dev/null)" ]]; then
  echo "warning: uploading $(git rev-parse --short HEAD) from '${BRANCH:-a detached HEAD}', not main." >&2
fi

NOTES_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes-file) NOTES_FILE="${2:-}"; shift 2 ;;
    *) echo "error: unknown argument '$1'. Usage: scripts/testflight.sh --notes-file <file>" >&2; exit 1 ;;
  esac
done
if [[ -z "${NOTES_FILE}" || ! -s "${NOTES_FILE}" ]]; then
  echo "error: What to Test notes are required: scripts/testflight.sh --notes-file <file>." >&2
  echo "  Write them with the release-notes skill; see .agents/rules/testflight-notes.md." >&2
  exit 1
fi
NOTES="$(cat "${NOTES_FILE}")"
if (( ${#NOTES} > 4000 )); then
  echo "error: the notes are ${#NOTES} characters; App Store Connect allows 4,000." >&2
  exit 1
fi

ASC_KEY_ID="${ASC_KEY_ID:-$(asc auth status --output json | python3 -I -c '
import json, sys
creds = json.load(sys.stdin).get("credentials", [])
print(next((c["keyId"] for c in creds if c.get("isDefault")), ""))')}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-c70979ec-ce57-4352-9479-32ca1309ce3a}"
ASC_PRIVATE_KEY_PATH="${ASC_PRIVATE_KEY_PATH:-${HOME}/.asc/keys/AuthKey_${ASC_KEY_ID}.p8}"
if [[ -z "${ASC_KEY_ID}" || ! -f "${ASC_PRIVATE_KEY_PATH}" ]]; then
  echo "error: no App Store Connect API key. Sign asc in (asc auth login) or set ASC_KEY_ID and ASC_PRIVATE_KEY_PATH." >&2
  exit 1
fi
AUTH=(-allowProvisioningUpdates
  -authenticationKeyPath "${ASC_PRIVATE_KEY_PATH}"
  -authenticationKeyID "${ASC_KEY_ID}"
  -authenticationKeyIssuerID "${ASC_ISSUER_ID}")

LAST_BUILD="$(asc builds list --app "${APP_ID}" --paginate --output json | python3 -I -c '
import json, sys
nums = [int(b["attributes"]["version"]) for b in json.load(sys.stdin).get("data", [])
        if b["attributes"].get("version", "").isdigit()]
print(max(nums, default=0))')"
BUILD=$((LAST_BUILD + 1))
VERSION="$(xcodebuild -showBuildSettings -project CommitStandings.xcodeproj -target CommitStandingsiOS \
  -configuration Release 2>/dev/null | awk '$1 == "MARKETING_VERSION" { print $3 }')"

echo "==> Committed ${VERSION} (${BUILD}) from $(git rev-parse --short HEAD) → TestFlight (${BETA_GROUPS})"

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"
cat > "${OUT_DIR}/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyLists-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>teamID</key><string>${TEAM_ID}</string>
	<key>signingStyle</key><string>automatic</string>
	<key>manageAppVersionAndBuildNumber</key><false/>
	<key>uploadSymbols</key><true/>
</dict>
</plist>
EOF

echo "==> Archiving (log: ${OUT_DIR}/archive.log)"
xcodebuild archive -project CommitStandings.xcodeproj -scheme CommitStandingsiOS -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "${OUT_DIR}/Committed.xcarchive" \
  -derivedDataPath "${ROOT_DIR}/build/DerivedData-testflight" \
  CURRENT_PROJECT_VERSION="${BUILD}" "${AUTH[@]}" > "${OUT_DIR}/archive.log" 2>&1 \
  || { grep -E "error:" "${OUT_DIR}/archive.log" | tail -20 >&2; exit 1; }

echo "==> Uploading (log: ${OUT_DIR}/export.log)"
xcodebuild -exportArchive -archivePath "${OUT_DIR}/Committed.xcarchive" \
  -exportOptionsPlist "${OUT_DIR}/ExportOptions.plist" -exportPath "${OUT_DIR}/export" \
  "${AUTH[@]}" > "${OUT_DIR}/export.log" 2>&1 \
  || { grep -iE "error" "${OUT_DIR}/export.log" | tail -20 >&2; exit 1; }

# App Store Connect lists an upload only after a few minutes, and `asc publish --wait` waits for
# processing of a build it can already find, so wait for it to appear first.
echo "==> Waiting for App Store Connect to list build ${BUILD}"
deadline=$((SECONDS + 1800))
until asc builds list --app "${APP_ID}" --paginate --output json 2>/dev/null | python3 -I -c '
import json, sys
sys.exit(0 if any(b["attributes"].get("version") == sys.argv[1] for b in json.load(sys.stdin).get("data", [])) else 1)' "${BUILD}"; do
  if (( SECONDS >= deadline )); then
    echo "error: build ${BUILD} didn't appear within 30 minutes. Distribute it later with:" >&2
    echo "  asc publish testflight --app ${APP_ID} --build-number ${BUILD} --group '${BETA_GROUPS}' --wait --submit --confirm" >&2
    exit 1
  fi
  sleep 30
done

echo "==> Waiting for processing, then adding to ${BETA_GROUPS} and submitting for beta review"
asc publish testflight --app "${APP_ID}" --build-number "${BUILD}" \
  --group "${BETA_GROUPS}" --test-notes "${NOTES}" --locale en-US \
  --wait --timeout 45m --submit --confirm --output table

echo "==> What to Test, as App Store Connect saved it:"
BUILD_ID="$(asc builds list --app "${APP_ID}" --paginate --output json | python3 -I -c '
import json, sys
print(next(b["id"] for b in json.load(sys.stdin)["data"] if b["attributes"].get("version") == sys.argv[1]))' "${BUILD}")"
asc builds test-notes list --build-id "${BUILD_ID}" --output json | python3 -I -c '
import json, sys
for note in json.load(sys.stdin).get("data", []):
    print(note["attributes"].get("whatsNew") or "")'

echo "==> Done: ${VERSION} (${BUILD}). Internal testers have it now; ${BETA_GROUPS} get it after beta review."
