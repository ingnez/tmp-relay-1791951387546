#!/usr/bin/env bash
# Build an unsigned Rakazo .ipa with patches/stage2-3.patch applied: the P0 model fixes, the
# scenario slots, the provider remarks and the Grok-Bot-style home screen, all in apps/mobile.
#
# Runs on the GitHub-hosted `xcode-27` macOS runner. The workflow only checks this relay repo out
# and calls this script, so a change here needs no workflow edit: push, then re-dispatch the run.
set -euxo pipefail

RELAY_REPO="ingnez/tmp-relay-1791951387546"
BRANCH="${GITHUB_REF_NAME:-main}"
PATCH="${PATCH:-patches/stage2-3.patch}"

# The server baked into the JS bundle (EXPO_PUBLIC_API_URL). Rakazo's login screen can still point
# the app at another server at runtime.
export EXPO_PUBLIC_API_URL="${EXPO_PUBLIC_API_URL:-https://rakazo.163ll.com}"
export EXPO_NO_TELEMETRY=1
export CI=1

git clone --depth 1 https://github.com/elie222/rakazo.git src
cd src

# The upstream branch this builds, so a failed apply names the commit it was tried on.
git log -1 --format='upstream %H %s'

curl -fsSL "https://raw.githubusercontent.com/${RELAY_REPO}/${BRANCH}/${PATCH}" -o /tmp/stage2-3.patch
git apply -v /tmp/stage2-3.patch
git diff --stat

# The build is worthless without the patch: fail here, not after 40 minutes of compiling.
test -f apps/mobile/lib/model-provider-label.ts
grep -q 'OpenAI 兼容（第三方）' apps/mobile/lib/model-provider-label.ts
test -f apps/mobile/lib/scenario-models.ts
test -f apps/mobile/components/scenario-model-slots.tsx
test -f apps/mobile/components/home-hero.tsx
test -f apps/mobile/components/home-bottom-bar.tsx
test -f apps/mobile/components/press-scale.tsx
grep -q 'enable' apps/mobile/app.json
# No over-the-air updates in this build: the config must disable them and name no update server.
node -e '
const { expo } = require("./apps/mobile/app.json");
const updates = expo.updates ?? {};
if (updates.enabled !== false) throw new Error("updates must be disabled in app.json");
if (updates.url) throw new Error("app.json must not name an update URL");
console.log("updates config:", JSON.stringify(updates));
'

npm i -g pnpm@12.18.0
pnpm install --frozen-lockfile

cd apps/mobile
pnpm exec expo install --check ||
  echo "::warning::expo patch-level version drift ignored (app.config.ts is dynamic, so --fix cannot write it)"
pnpm exec expo prebuild --platform ios --no-install

# The built app must carry that switch: EXUpdatesEnabled must be false in Info.plist.
node -e '
const fs = require("fs");
const plist = fs.readFileSync("ios/Rakazo/Info.plist", "utf8");
if (!/EXUpdatesEnabled[\s\S]{0,80}?<false\/>/.test(plist)) {
  console.log("::warning::Info.plist does not show EXUpdatesEnabled=false; inspect before shipping");
} else {
  console.log("Info.plist: EXUpdatesEnabled = false");
}
'

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
