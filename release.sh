#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# release.sh  —  Create a new OTA release
#
# PREREQUISITES
#   brew install gh          # GitHub CLI  (https://cli.github.com)
#   gh auth login            # Authenticate once
#   git remote set-url origin git@github.com:USERNAME/REPO.git
#
# USAGE
#   chmod +x release.sh
#   ./release.sh path/to/MyApp.ipa 1.0.1
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ──────────────────────────── CONFIG — EDIT THESE ────────────────────────────
GITHUB_USER="YOUR_GITHUB_USERNAME"
REPO_NAME="YOUR_REPO_NAME"
BUNDLE_ID="com.yourcompany.myapp"
APP_NAME="MyApp"
CONTACT_EMAIL="you@example.com"
# ─────────────────────────────────────────────────────────────────────────────

IPA_PATH="${1:-}"
VERSION="${2:-}"

if [[ -z "$IPA_PATH" || -z "$VERSION" ]]; then
  echo "Usage: $0 <path/to/App.ipa> <version>   e.g. $0 ./MyApp.ipa 1.0.1"
  exit 1
fi

if [[ ! -f "$IPA_PATH" ]]; then
  echo "Error: IPA not found at $IPA_PATH"
  exit 1
fi

IPA_SIZE=$(du -sh "$IPA_PATH" | cut -f1)
TODAY=$(date +%Y-%m-%d)
PAGES_BASE="https://${GITHUB_USER}.github.io/${REPO_NAME}"
MANIFEST_FILENAME="${VERSION}.plist"
MANIFEST_PATH="manifests/${MANIFEST_FILENAME}"
RELEASE_TAG="v${VERSION}"

echo ""
echo "┌─────────────────────────────────────────────┐"
echo "│  OTA Release Builder                         │"
echo "├─────────────────────────────────────────────┤"
printf "│  App     : %-33s│\n" "$APP_NAME"
printf "│  Version : %-33s│\n" "$VERSION"
printf "│  IPA     : %-33s│\n" "$(basename "$IPA_PATH") ($IPA_SIZE)"
printf "│  Date    : %-33s│\n" "$TODAY"
echo "└─────────────────────────────────────────────┘"
echo ""

# 1 ── Upload .ipa to a GitHub Release (bypasses the 100MB Pages limit)
echo "▶  Creating GitHub Release $RELEASE_TAG and uploading IPA..."
gh release create "$RELEASE_TAG" \
  "$IPA_PATH" \
  --repo "${GITHUB_USER}/${REPO_NAME}" \
  --title "$APP_NAME $RELEASE_TAG" \
  --notes "Ad-hoc build $VERSION — $TODAY" 2>/dev/null || true
  # 'true' so we don't fail if release already exists; re-upload asset:

# Get the download URL of the uploaded asset
IPA_URL=$(gh release view "$RELEASE_TAG" \
  --repo "${GITHUB_USER}/${REPO_NAME}" \
  --json assets \
  --jq ".assets[] | select(.name == \"$(basename "$IPA_PATH")\") | .browserDownloadUrl")

if [[ -z "$IPA_URL" ]]; then
  echo "Error: Could not retrieve asset URL from GitHub release."
  exit 1
fi

echo "   IPA URL: $IPA_URL"

# 2 ── Generate the .plist manifest
echo "▶  Generating manifest: $MANIFEST_PATH"
mkdir -p manifests

cat > "$MANIFEST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>items</key>
  <array>
    <dict>
      <key>assets</key>
      <array>
        <dict>
          <key>kind</key>   <string>software-package</string>
          <key>url</key>    <string>${IPA_URL}</string>
        </dict>
        <dict>
          <key>kind</key>        <string>full-size-image</string>
          <key>needs-shine</key> <false/>
          <key>url</key>         <string>${PAGES_BASE}/icons/icon-512.png</string>
        </dict>
        <dict>
          <key>kind</key>        <string>display-image</string>
          <key>needs-shine</key> <false/>
          <key>url</key>         <string>${PAGES_BASE}/icons/icon-57.png</string>
        </dict>
      </array>
      <key>metadata</key>
      <dict>
        <key>bundle-identifier</key> <string>${BUNDLE_ID}</string>
        <key>bundle-version</key>    <string>${VERSION}</string>
        <key>kind</key>              <string>software</string>
        <key>title</key>             <string>${APP_NAME}</string>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

# 3 ── Update apps.json with the new version (prepend to versions array)
echo "▶  Updating apps.json..."
MANIFEST_URL="${PAGES_BASE}/${MANIFEST_PATH}"

# Use Python (available everywhere) to update the JSON
python3 - <<PYEOF
import json, sys

with open('apps.json', 'r') as f:
    apps = json.load(f)

new_entry = {
    "version": "${VERSION}",
    "date": "${TODAY}",
    "size": "${IPA_SIZE}",
    "manifest_url": "${MANIFEST_URL}"
}

# Prepend to front (newest first); remove duplicate version if exists
apps[0]['versions'] = [v for v in apps[0].get('versions', []) if v['version'] != "${VERSION}"]
apps[0]['versions'].insert(0, new_entry)

with open('apps.json', 'w') as f:
    json.dump(apps, f, indent=2)

print("  apps.json updated.")
PYEOF

# 4 ── Commit & push to GitHub Pages
echo "▶  Committing and pushing to GitHub Pages..."
git add "apps.json" "$MANIFEST_PATH"
git commit -m "release: $APP_NAME $RELEASE_TAG"
git push

echo ""
echo "✅  Done! Install page:"
echo "   ${PAGES_BASE}/"
echo ""
echo "   Direct install link (open on iOS device in Safari):"
echo "   itms-services://?action=download-manifest&url=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${MANIFEST_URL}', safe=''))")"
echo ""
