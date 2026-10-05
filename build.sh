#!/bin/bash
# Builds yDock and wraps it in yDock.app (no Xcode needed).
set -e
cd "$(dirname "$0")"
swift build -c release
APP=yDock.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS
cp .build/release/yDock $APP/Contents/MacOS/
cat > $APP/Contents/Info.plist <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>yDock</string>
<key>CFBundleIdentifier</key><string>local.ydock</string>
<key>CFBundleName</key><string>yDock</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSCalendarsFullAccessUsageDescription</key><string>yDock shows your next calendar event.</string>
<key>NSCalendarsUsageDescription</key><string>yDock shows your next calendar event.</string>
<key>NSRemindersFullAccessUsageDescription</key><string>yDock shows your due reminders.</string>
<key>NSRemindersUsageDescription</key><string>yDock shows your due reminders.</string>
<key>NSPhotoLibraryUsageDescription</key><string>yDock shows a photo from your library in the Photos widget.</string>
<key>NSAppleEventsUsageDescription</key><string>yDock reads Music, Spotify and Notes for its Now Playing and Notes widgets.</string>
</dict></plist>
PL
./sign.sh $APP
echo "Built $APP"
