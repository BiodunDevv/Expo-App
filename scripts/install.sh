#!/bin/zsh
# Installs your configuration and a Release build.
#   scripts/install.sh            copy .env (if none installed), build, copy to /Applications
#   scripts/install.sh --env      only (re)install .env
set -e
cd "${0:A:h}/.."
support="$HOME/Library/Application Support/Expo"
if [[ -f .env ]]; then
  mkdir -p "$support"
  chmod 700 "$support"
  if [[ "$1" == "--env" || ! -f "$support/.env" ]]; then
    install -m 600 .env "$support/.env"
    echo "Configuration installed to $support/.env"
  else
    echo "Keeping the existing $support/.env (run with --env to replace it)."
  fi
fi
[[ "$1" == "--env" ]] && exit 0

build="$(mktemp -d)"
# A new build number each time, so macOS never keeps showing an old icon.
xcodebuild -project Expo.xcodeproj -scheme Expo -configuration Release -derivedDataPath "$build" \
  CURRENT_PROJECT_VERSION="$(date +%y%m%d%H%M)" -quiet build
target=/Applications/Expo.app
if [[ -d "$target" ]]; then
  id=$(plutil -extract CFBundleIdentifier raw "$target/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$id" != "core4.Expo" ]]; then
    echo "$target is a different app ($id), probably the old Electron build."
    echo "Move it to the Trash or rename it, then run this again. The new build is in $build/Build/Products/Release."
    exit 1
  fi
  osascript -e 'tell application id "core4.Expo" to quit' 2>/dev/null || true
  rm -rf "$target"
fi
ditto "$build/Build/Products/Release/Expo.app" /Applications/Expo.app
# Point macOS at the installed copy only, and refresh its icon.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$lsregister" -u "$build/Build/Products/Release/Expo.app" 2>/dev/null || true
touch "$target"
"$lsregister" -f "$target"
echo "Installed /Applications/Expo.app"
