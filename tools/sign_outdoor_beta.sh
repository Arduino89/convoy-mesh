#!/usr/bin/env bash
# Owner-operated signer for an already reviewed Outdoor beta APK.
# Run on a trusted machine with Android SDK build-tools and the owner keystore.
# The key is NEVER generated here or read by CI; no password arguments or logs.
set -euo pipefail
if [[ $# != 7 ]]; then
  echo 'Usage: sign_outdoor_beta.sh INPUT.apk OUTPUT.apk INPUT_SHA256 EXPECTED_VERSION_CODE EXPECTED_CERT_SHA256 KEYSTORE KEY_ALIAS' >&2
  exit 2
fi
input=$1
output=$2
expected_sha=${3,,}
code=$4
cert=${5,,}
keystore=$6
alias=$7
[[ -f "$input" && -f "$keystore" && ! -e "$output" && ! -L "$output" ]]
[[ "$expected_sha" =~ ^[a-f0-9]{64}$ && "$cert" =~ ^[a-f0-9]{64}$ ]]
[[ "$code" =~ ^[1-9][0-9]*$ && ${#code} -le 9 && "$code" -ge 18 ]]
[[ -n "$alias" && "$alias" != -* ]]
# Use SDK's installed tools; alternatively set ANDROID_BUILD_TOOLS explicitly.
if [[ -z "${ANDROID_BUILD_TOOLS:-}" ]]; then
  sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
  [[ -n "$sdk" ]]
  ANDROID_BUILD_TOOLS=$(find "$sdk/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)
fi
apksigner="$ANDROID_BUILD_TOOLS/apksigner"
aapt="$ANDROID_BUILD_TOOLS/aapt"
zipalign="$ANDROID_BUILD_TOOLS/zipalign"
[[ -x "$apksigner" && -x "$aapt" && -x "$zipalign" ]]
actual=$(sha256sum -- "$input" | awk '{print $1}')
[[ "$actual" == "$expected_sha" ]] || { echo 'Input APK hash mismatch' >&2; exit 1; }
check_identity() {
  local info
  info=$("$aapt" dump badging "$1")
  grep -Fq "package: name='com.example.convoy_mesh.outdoor' versionCode='$code' versionName='0.7.7-outdoor'" <<< "$info"
}
check_identity "$input"
"$apksigner" verify "$input"
"$zipalign" -c -P 16 4 "$input"
# Sign a staged file; failed checks never leave a deliverable with the requested name.
# apksigner prompts for passwords securely on the owner's terminal. No -x tracing.
umask 077
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
"$apksigner" sign --ks "$keystore" --ks-key-alias "$alias" --out "$work/signed.apk" "$input"
"$zipalign" -c -P 16 4 "$work/signed.apk"
check_identity "$work/signed.apk"
proof=$("$apksigner" verify --verbose --print-certs "$work/signed.apk")
grep -Fq 'Verified using v2 scheme (APK Signature Scheme v2): true' <<< "$proof"
actual_cert=$(sed -nE 's/^[[:space:]]*(V[0-9]+ )?Signer( #[0-9]+)?:?[[:space:]]+certificate SHA-256 digest:[[:space:]]*([a-fA-F0-9]{64})[[:space:]]*$/\3/p' <<< "$proof" | tr 'A-F' 'a-f' | sort -u)
[[ "$actual_cert" =~ ^[a-f0-9]{64}$ ]] || { echo 'Cannot extract exactly one distinct signer certificate' >&2; exit 1; }
printf 'Actual APK public certificate SHA-256: %s\n' "$actual_cert"
[[ "$actual_cert" == "$cert" ]] || { echo 'Unexpected signing certificate' >&2; exit 1; }
[[ "$(sha256sum -- "$input" | awk '{print $1}')" == "$expected_sha" ]]
# POSIX noclobber prevents replacing an older delivered APK.
(set -o noclobber; cat "$work/signed.apk" > "$output")
printf 'Package: com.example.convoy_mesh.outdoor\nVersion code: %s\nCertificate SHA-256: %s\n' "$code" "$cert"
sha256sum -- "$output"
wc -c < "$output"
