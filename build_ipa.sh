#!/bin/zsh
# 사이드로딩용 IPA 생성.
# 프로비저닝 없이 빌드한 뒤 ad-hoc 서명으로 앱 그룹 권한(entitlements)만 바이너리에 심는다.
# (AltStore/Sideloadly 등이 이 권한을 읽어 자기 계정에 맞게 재서명한다)
set -e
cd "$(dirname "$0")"
xcodegen generate >/dev/null
rm -rf build/unsigned build/Payload
xcodebuild -project SwipeLauncher.xcodeproj -scheme SwipeLauncher \
  -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath build/unsigned CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir -p build/Payload
APP=build/Payload/SwipeLauncher.app
cp -R build/unsigned/Build/Products/Release-iphoneos/SwipeLauncher.app "$APP"
codesign -f -s - --entitlements Widget/Widget.entitlements "$APP/PlugIns/LauncherWidget.appex"
codesign -f -s - --entitlements App/App.entitlements "$APP"
(cd build && rm -f SwipeLauncher-unsigned.ipa && zip -qry SwipeLauncher-unsigned.ipa Payload)
echo "build/SwipeLauncher-unsigned.ipa"
