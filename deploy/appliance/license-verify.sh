#!/usr/bin/env bash
# CZID-13 — offline license verification (scaffold).
#
# The appliance runs OUTSIDE our infrastructure (air-gap-capable), so entitlement is verified
# OFFLINE: the license is a signed token (e.g. a JWT signed with our private key); this script
# verifies the signature against the PUBLIC key shipped in the bundle, and checks expiry — NO
# phone-home. Fail-closed: a missing/expired/forged license exits non-zero and the installer aborts.
#
# [BUCKET-B] the signed-license ISSUANCE pipeline (our side) + the final entitlement schema
# (per-cluster / per-seat / unlimited-on-prem) are a Tom + legal decision (#13 §5). This scaffold
# defines the verification contract the app + installer rely on.
set -euo pipefail

LICENSE_FILE="${1:?usage: license-verify.sh <license-file>}"
PUBKEY="${LICENSE_PUBKEY:-$(dirname "$0")/license-pubkey.pem}"

die() { printf '\033[1;31m[license:ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[ -f "$LICENSE_FILE" ] || die "license file not found: $LICENSE_FILE"
[ -f "$PUBKEY" ]       || die "license public key not found: $PUBKEY (ship it in the bundle)"

# Expected format: a JWT-style "<base64url(header)>.<base64url(payload)>.<base64url(sig)>" where
# payload carries: { "exp": <unix>, "tier": "...", "features": [...], "cluster": "..." }.
b64url_decode() { local s="${1//-/+}"; s="${s//_//}"; case $(( ${#s} % 4 )) in 2) s="${s}==";; 3) s="${s}=";; esac; printf '%s' "$s" | base64 -d 2>/dev/null; }

IFS='.' read -r HDR PAYLOAD SIG <<<"$(cat "$LICENSE_FILE")"
[ -n "${HDR:-}" ] && [ -n "${PAYLOAD:-}" ] && [ -n "${SIG:-}" ] || die "malformed license (expected header.payload.signature)"

# 1) signature: verify "<hdr>.<payload>" against the public key (RS256).
printf '%s.%s' "$HDR" "$PAYLOAD" > /tmp/.lic_signing_input
b64url_decode "$SIG" > /tmp/.lic_sig
openssl dgst -sha256 -verify "$PUBKEY" -signature /tmp/.lic_sig /tmp/.lic_signing_input >/dev/null 2>&1 \
  || die "signature invalid — license is forged or not issued by us"

# 2) expiry: fail-closed if past exp (offline clock).
EXP="$(b64url_decode "$PAYLOAD" | sed -n 's/.*"exp"[ :]*\([0-9]\{1,\}\).*/\1/p')"
[ -n "$EXP" ] || die "license has no exp claim"
NOW="$(date +%s)"
[ "$NOW" -lt "$EXP" ] || die "license expired ($(date -r "$EXP" 2>/dev/null || echo "$EXP"))"

printf '\033[1;32m[license]\033[0m valid (expires %s)\n' "$(date -r "$EXP" 2>/dev/null || echo "$EXP")"
