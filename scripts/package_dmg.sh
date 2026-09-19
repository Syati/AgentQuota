#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "Usage: $0 <version>"
  exit 64
fi

version="$1"
root_dir="${0:A:h:h}"
build_dir="$root_dir/.build/release"
dist_dir="$root_dir/dist"
app_dir="$dist_dir/AgentQuota.app"
dmg_root="$dist_dir/dmg-root"
dmg_path="$dist_dir/AgentQuota-${version}.dmg"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ ! -x "$developer_dir/usr/bin/xcodebuild" ]]; then
  print -u2 "Xcode was not found at $developer_dir"
  exit 69
fi

env DEVELOPER_DIR="$developer_dir" swift build -c release --disable-sandbox

rm -rf "$app_dir"
rm -f "$dmg_path"
rm -rf "$dmg_root"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$build_dir/AgentQuota" "$app_dir/Contents/MacOS/AgentQuota"
cp "$build_dir/AgentQuotaClaudeStatusLine" "$app_dir/Contents/MacOS/AgentQuotaClaudeStatusLine"
cp "$root_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp "$root_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"
mkdir -p "$dmg_root"
cp -R "$app_dir" "$dmg_root/AgentQuota.app"
ln -s /Applications "$dmg_root/Applications"
hdiutil create -volname AgentQuota -srcfolder "$dmg_root" -ov -format UDZO "$dmg_path"
print "$dmg_path"
