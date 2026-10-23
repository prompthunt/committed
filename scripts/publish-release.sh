#!/usr/bin/env bash
#
# Publish a Committed release to the public releases repo, then verify the public links.
# Run this from `main` after the version bump has merged. It packages from the current
# checkout (package-release.sh) and creates the GitHub Release with ALL required assets —
# crucially including the stable-named Committed.dmg, so the permanent share link
# (…/releases/latest/download/Committed.dmg) keeps resolving. See AGENTS.md → Releasing.
#
# Usage:
#   scripts/publish-release.sh                 # generic release notes
#   scripts/publish-release.sh "Notes here…"   # custom release notes
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASES_REPO="prompthunt/commit-standings-releases"
INFO_PLIST="${ROOT_DIR}/CommitStandings/Info.plist"
DIST_DIR="${ROOT_DIR}/dist"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "${INFO_PLIST}")"
TAG="v${VERSION}"
NOTES="${1:-Committed ${VERSION}. ⋯ → Check for Updates.}"

echo "==> Releasing ${TAG} to ${RELEASES_REPO}"

# 1. Build, sign, notarize, and generate the appcast (+ the stable Committed.dmg copy).
"${ROOT_DIR}/scripts/package-release.sh"

# 2. Resolve the freshly built assets for THIS version.
DMG="$(ls -t "${DIST_DIR}/CommitStandings-${VERSION}-"*.dmg 2>/dev/null | head -1)"
ZIP="$(ls -t "${DIST_DIR}/CommitStandings-${VERSION}-"*.app.zip 2>/dev/null | head -1)"
STABLE_DMG="${DIST_DIR}/Committed.dmg"
APPCAST="${DIST_DIR}/appcast.xml"

for f in "${DMG}" "${ZIP}" "${STABLE_DMG}" "${APPCAST}"; do
  if [ -z "${f}" ] || [ ! -f "${f}" ]; then
    echo "ERROR: missing release asset: '${f}'. package-release.sh did not produce the full set." >&2
    exit 1
  fi
done

# 3. Publish. Committed.dmg is REQUIRED — without it the permanent share link breaks.
echo "==> Creating release ${TAG} with: appcast.xml, $(basename "${ZIP}"), $(basename "${DMG}"), Committed.dmg"
gh release create "${TAG}" \
  --repo "${RELEASES_REPO}" \
  --title "Committed ${VERSION}" \
  --notes "${NOTES}" \
  --latest \
  "${APPCAST}" "${ZIP}" "${DMG}" "${STABLE_DMG}"

# 4. Verify the public links the app + humans rely on.
check() {
  local url="$1" code
  code="$(curl -s -o /dev/null -w '%{http_code}' -L "${url}")"
  printf '    %s  %s\n' "${code}" "${url}"
  [ "${code}" = "200" ]
}

echo "==> Verifying public links"
ok=1
check "https://github.com/${RELEASES_REPO}/releases/latest/download/Committed.dmg" || ok=0
check "https://github.com/${RELEASES_REPO}/releases/latest/download/appcast.xml" || ok=0
# The appcast enclosure must be the permanent per-tag form, not latest/download/.
ENCLOSURE="$(grep -o 'url="[^"]*'"${TAG}"'/[^"]*\.app\.zip"' "${APPCAST}" | head -1 | sed 's/^url="//;s/"$//')"
if [ -n "${ENCLOSURE}" ]; then
  check "${ENCLOSURE}" || ok=0
else
  echo "    WARN: could not find a per-tag (${TAG}) enclosure URL in appcast.xml" >&2
  ok=0
fi

if [ "${ok}" != "1" ]; then
  echo "ERROR: one or more release links did not return 200 — investigate before announcing." >&2
  exit 1
fi

echo "==> Published ${TAG}. Permanent share link: https://github.com/${RELEASES_REPO}/releases/latest/download/Committed.dmg"
