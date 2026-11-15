#!/bin/zsh
# 사이드로딩용 서명 없는 IPA 생성 (AltStore/Sideloadly 등이 재서명)
set -e
cd "$(dirname "$0")"
xcodegen generate >/dev/null
rm -rf build/unsigned build/Payload
xcodebuild -project SwipeLauncher.xcodeproj -scheme SwipeLauncher \
  -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath build/unsigned CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir -p build/Payload
cp -R build/unsigned/Build/Products/Release-iphoneos/SwipeLauncher.app build/Payload/
(cd build && rm -f SwipeLauncher-unsigned.ipa && zip -qry SwipeLauncher-unsigned.ipa Payload)
echo "build/SwipeLauncher-unsigned.ipa"
