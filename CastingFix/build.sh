#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Compile on the macOS runner using Xcode's iOS SDK; no private headers or
# additional Theos checkout is needed for this small runtime hook.
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
package_root="$(mktemp -d)"
trap 'rm -rf "$package_root"' EXIT
libdir="$package_root/Library/MobileSubstrate/DynamicLibraries"
mkdir -p "$libdir" "$package_root/DEBIAN"
xcrun --sdk iphoneos clang -target arm64-apple-ios15.0 -isysroot "$sdk" \
  -fobjc-arc -fblocks -Wall -Wextra -Werror -dynamiclib \
  -framework Foundation -framework Network \
  -install_name @rpath/YTLiteLocalNetworkFix.dylib \
  YTLiteLocalNetworkFix.m -o "$libdir/YTLiteLocalNetworkFix.dylib"
ldid -S "$libdir/YTLiteLocalNetworkFix.dylib"
cat > "$libdir/YTLiteLocalNetworkFix.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Filter</key><dict><key>Classes</key><array><string>MDXLocalNetworkPermissions</string></array></dict></dict></plist>
PLIST
cat > "$package_root/DEBIAN/control" <<'CONTROL'
Package: com.lilbentley.ytlocalnetworkfix
Name: YTLite Local Network Fix
Version: 0.1.0
Architecture: iphoneos-arm
Description: Bonjour permission verification and system Cast discovery for sideloaded YouTube.
Maintainer: lilbentley
Section: Tweaks
CONTROL
dpkg-deb --root-owner-group --build "$package_root" ../ytlocalnetworkfix.deb
