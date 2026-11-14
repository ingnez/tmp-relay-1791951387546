#!/usr/bin/env bash
# Build an unsigned Rakazo .ipa with patches/p0-models-ui.patch applied.
#
# Runs on the GitHub-hosted `xcode-27` macOS runner. The workflow only checks this relay repo out
# and calls this script, so a change here needs no workflow edit: push, then re-dispatch the run.
set -euxo pipefail

RELAY_REPO="ingnez/tmp-relay-1791951387546"
BRANCH="${GITHUB_REF_NAME:-main}"
PATCH="patches/p0-models-ui.patch"

# The server baked into the JS bundle (EXPO_PUBLIC_API_URL). Rakazo's login screen can still point
# the app at another server at runtime.
export EXPO_PUBLIC_API_URL="${EXPO_PUBLIC_API_URL:-https://rakazo.163ll.com}"
export EXPO_NO_TELEMETRY=1
export CI=1

git clone --depth 1 https://github.com/elie222/rakazo.git src
cd src

# The upstream branch this builds, so a failed apply names the commit it was tried on.
git log -1 --format='upstream %H %s'

curl -fsSL "https://raw.githubusercontent.com/${RELAY_REPO}/${BRANCH}/${PATCH}" -o /tmp/p0-models-ui.patch
git apply -v /tmp/p0-models-ui.patch
git diff --stat
# The build is worthless without the patch: fail here, not after 40 minutes of compiling.
test -f apps/mobile/lib/model-provider-label.ts
grep -q 'OpenAI 兼容（第三方）' apps/mobile/lib/model-provider-label.ts

npm i -g pnpm@12.18.0
pnpm install --frozen-lockfile

cd apps/mobile
pnpm exec expo install --check ||
  echo "::warning::expo patch-level version drift ignored (app.config.ts is dynamic, so --fix cannot write it)"
pnpm exec expo prebuild --platform ios --no-install

cd ios
pod install --repo-update || pod install
xcodebuild -workspace Rakazo.xcworkspace -scheme Rakazo -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build \
  | tee xcodebuild.log

mkdir -p Payload && cp -R build/Build/Products/Release-iphoneos/Rakazo.app Payload/
zip -qry Rakazo-unsigned.ipa Payload
unzip -l Rakazo-unsigned.ipa | head -30
ls -lh Rakazo-unsigned.ipa
