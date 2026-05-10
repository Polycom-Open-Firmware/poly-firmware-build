#!/usr/bin/env bash
# fetch-avb-test-key.sh — download the AOSP RSA-4096 AVB test key.
#
# This is the PUBLIC test key shipped in the Android source tree at
# external/avb/test/data/testkey_rsa4096.pem. Boots produced with it pass
# AVB verification but show "orange state" because the panel's u-boot has
# Polycom's pubkey burned in, not this one. Fine for development; do not
# use for production fleets — generate your own key with `openssl genrsa`
# and replace.
#
# USAGE:
#   ./scripts/fetch-avb-test-key.sh             # writes ./testkey_rsa4096.pem
#   ./scripts/fetch-avb-test-key.sh /custom/path/key.pem
#
# After running:
#   export TC8_AVB_KEY="$PWD/testkey_rsa4096.pem"

set -euo pipefail

OUT="${1:-$(pwd)/testkey_rsa4096.pem}"
URL="https://android.googlesource.com/platform/external/avb/+/refs/heads/main/test/data/testkey_rsa4096.pem?format=TEXT"

# AOSP gitiles serves files base64-encoded with ?format=TEXT
echo "==> fetching AOSP AVB test key -> $OUT"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL "$URL" -o "$tmp"
base64 -d < "$tmp" > "$OUT"

# Sanity check: PEM header + RSA key length
head -1 "$OUT" | grep -q '^-----BEGIN .*PRIVATE KEY-----$' || {
    echo "ERROR: $OUT doesn't look like a PEM private key:" >&2
    head -3 "$OUT" >&2
    exit 1
}
openssl rsa -in "$OUT" -noout -text 2>/dev/null | grep -q '4096 bit' || {
    echo "ERROR: $OUT is not RSA-4096" >&2
    exit 1
}

chmod 0600 "$OUT"
echo "[OK] wrote $OUT (RSA-4096 PEM, mode 0600)"
echo
echo "Use it:"
echo "    export TC8_AVB_KEY=\"$OUT\""
