#!/bin/bash
# Zips the app for copying to your other Macs.
set -e
cd "$(dirname "$0")"
./build.sh
rm -f yDock.zip && ditto -c -k --keepParent yDock.app yDock.zip
echo "Created yDock.zip. On the other Mac: unzip, run 'xattr -cr yDock.app', move to ~/Applications, open it."
