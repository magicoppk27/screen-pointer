#!/usr/bin/env bash
# Creates (once) and unlocks a self-signed code-signing identity in .signing/, then prints
# its SHA-1 hash on stdout. build-app.sh calls this so every build has the same signature
# and macOS keeps the Input Monitoring permission across rebuilds.
#
# .signing/ is gitignored and machine-local. On a new Mac a new certificate is created
# automatically; grant the permission once there and it sticks from then on.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="Screen Pointer Local Signing"
DIR="$PWD/.signing"
KC="$DIR/signing.keychain-db"
PWFILE="$DIR/keychain-password"

log() { echo "$@" >&2; }

ensure_in_search_list() {
    if ! security list-keychains -d user | grep -qF "$KC"; then
        # shellcheck disable=SC2046
        security list-keychains -d user -s "$KC" $(security list-keychains -d user | tr -d '"')
    fi
}

if [[ ! -f "$KC" ]]; then
    log "Creating self-signed signing identity \"$NAME\" in .signing/ …"
    mkdir -p "$DIR"
    chmod 700 "$DIR"
    security list-keychains -d user > "$DIR/search-list-backup.txt"
    openssl rand -hex 16 | tr -d '\n' > "$PWFILE"
    chmod 600 "$PWFILE"
    PW="$(cat "$PWFILE")"

    cat > "$DIR/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$DIR/cert.cnf" \
        -keyout "$TMP/key.pem" -out "$DIR/cert.pem" 2>/dev/null
    openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$DIR/cert.pem" -name "$NAME" \
        -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES \
        -out "$TMP/signing.p12" -passout pass:"$PW"

    security create-keychain -p "$PW" "$KC"
    security set-keychain-settings "$KC"   # no auto-lock timeout
    security unlock-keychain -p "$PW" "$KC"
    security import "$TMP/signing.p12" -k "$KC" -P "$PW" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple: -s -k "$PW" "$KC" >/dev/null
fi

ensure_in_search_list
security unlock-keychain -p "$(cat "$PWFILE")" "$KC"

HASH="$(security find-identity -p codesigning "$KC" | awk -v n="\"$NAME\"" 'index($0, n) { print $2; exit }')"
if [[ -z "$HASH" ]]; then
    log "error: no \"$NAME\" identity found in $KC"
    exit 1
fi
echo "$HASH"
