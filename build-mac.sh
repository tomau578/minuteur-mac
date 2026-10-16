#!/bin/bash
# Fabrique "Minuteur-visuel.dmg" (Mac Intel + Apple Silicon). Necessite les outils Xcode en ligne de commande.
set -e
cd "$(dirname "$0")"
APP="Minuteur visuel.app"
rm -rf build dmg "$APP" Minuteur-visuel.dmg
mkdir -p build dmg
swiftc -O -target arm64-apple-macos11.0 main.swift -o build/mv-arm64
swiftc -O -target x86_64-apple-macos11.0 main.swift -o build/mv-x86_64
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/MinuteurVisuel" build/mv-arm64 build/mv-x86_64
cp Info.plist "$APP/Contents/Info.plist"
cp minuteur.icns "$APP/Contents/Resources/minuteur.icns"
codesign --force --deep --sign - "$APP"
cp -R "$APP" dmg/
ln -s /Applications dmg/Applications
hdiutil create -volname "Minuteur visuel" -srcfolder dmg -ov -format UDZO Minuteur-visuel.dmg
echo "Termine : Minuteur-visuel.dmg"
