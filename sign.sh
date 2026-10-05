#!/bin/bash
# Signs yDock.app with a stable self-signed identity so macOS keeps granting permissions
# (Photos, Calendar, Reminders, Automation) across rebuilds. An ad-hoc signature changes with every build,
# which makes macOS treat each build as a brand-new app and ask again.
#
# The identity lives in its own keychain inside ./signing — your login keychain and the system trust
# settings are never touched. Delete ./signing to start over (you will be asked for permissions once more).
set -e
cd "$(dirname "$0")"
APP="${1:-yDock.app}"
NAME="yDock Local Signing"
KC="$PWD/signing/ydock.keychain-db"
PASS="ydock"

if [ ! -f "$KC" ]; then
  echo "Creating local signing identity…"
  mkdir -p signing
  cat > signing/openssl.cnf <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
  /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config signing/openssl.cnf \
    -keyout signing/key.pem -out signing/cert.pem 2>/dev/null
  /usr/bin/openssl pkcs12 -export -inkey signing/key.pem -in signing/cert.pem -out signing/id.p12 -passout pass:$PASS
  security create-keychain -p "$PASS" "$KC"
  security set-keychain-settings "$KC"
  security import signing/id.p12 -k "$KC" -P "$PASS" -T /usr/bin/codesign >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null
  rm -f signing/key.pem signing/id.p12
fi

security unlock-keychain -p "$PASS" "$KC"
codesign --force --sign "$NAME" --keychain "$KC" "$APP"
