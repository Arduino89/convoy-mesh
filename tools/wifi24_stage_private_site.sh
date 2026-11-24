#!/usr/bin/env bash
# Transfers only the verified APK to the existing owner-private Sites source.
# Native owner-private deployment is a separate operation after this gate.
set -euo pipefail
set +x
umask 077
apk=$(realpath "${1:?verified APK required}")
receipt=$(realpath "${2:?verified receipt required}")
: "${WIFI23_RECIPIENT_PEM:?Existing protected recipient key required to unwrap the short-lived transport token}"
: "${SOURCE_COMMIT:?}"
temp=$(mktemp -d)
trap 'rm -rf -- "$temp"' EXIT
expected_hash=$(jq -er '.apk_sha256 | strings | select(test("^[0-9a-f]{64}$"))' "$receipt")
expected_size=$(jq -er '.apk_bytes | numbers' "$receipt")
printf '%s  %s\n' "$expected_hash" "$apk" | sha256sum --check -
test "$(stat -c%s "$apk")" = "$expected_size"
jq -e --arg source "$SOURCE_COMMIT" --arg run "$GITHUB_RUN_ID" --arg attempt "$GITHUB_RUN_ATTEMPT" \
  '.source_sha == $source and .signing_run == $run and .attempt == $attempt and .version_code == 24 and .upgrade_api == 35' "$receipt" >/dev/null

printf '%s\n' "$WIFI23_RECIPIENT_PEM" > "$temp/recipient.pem"
unset WIFI23_RECIPIENT_PEM
expected_recipient=7f4441ae6dea4a2821c8b03d41ddcdad8bf19d7b543352155048fab39bb95921
actual_recipient=$(openssl x509 -in "$temp/recipient.pem" -outform DER | sha256sum | cut -d' ' -f1)
test "$actual_recipient" = "$expected_recipient"
site_id=appgprj_6b0475c8e9348191bd3b3a0715880f9c
remote=https://git.chatgpt-team.site/58a70ba3-41f5-47ae-afae-59a6e052ab91/$site_id.git
delivery_file=.github/convoy-wifi24-delivery.json

# Receive a short-lived transport credential from the authoring session after the
# emulator gate. A new signing run is unnecessary. The APK itself is never wrapped.
echo 'Waiting for the short-lived private Sites transport credential'
deadline=$((SECONDS + 600))
while (( SECONDS < deadline )); do
  if gh api -H 'Accept: application/vnd.github.raw+json' \
      "repos/$GITHUB_REPOSITORY/contents/$delivery_file?ref=$GITHUB_REF_NAME" > "$temp/transport.json" 2>/dev/null &&
    jq -e --arg run "$GITHUB_RUN_ID" --arg attempt "$GITHUB_RUN_ATTEMPT" --arg source "$SOURCE_COMMIT" \
      '.run == $run and .attempt == $attempt and .source_sha == $source and
       (.expires_at | type == "number") and .expires_at > (now + 240)' "$temp/transport.json" >/dev/null 2>&1; then
    token=$(jq -er '.wrapped_token | strings' "$temp/transport.json" | base64 --decode |
      openssl pkeyutl -decrypt -inkey "$temp/recipient.pem" -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256)
    break
  fi
  sleep 10
done
: "${token:?Private Sites transport credential unavailable before the runner deadline}"
[[ "$token" =~ ^[a-zA-Z0-9_-]+$ ]]
rm -f "$temp/recipient.pem"
export GIT_CONFIG_COUNT=2 GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_KEY_0="http.$remote.extraHeader" GIT_CONFIG_VALUE_0="Authorization: Bearer $token"
export GIT_CONFIG_KEY_1=http.postBuffer GIT_CONFIG_VALUE_1=67108864
unset token
git clone --quiet --depth 1 --branch main "$remote" "$temp/site"
cd "$temp/site"
jq -e --arg site "$site_id" '.project_id == $site and .static.directory == "dist"' .openai/hosting.json >/dev/null

# Keep each source push below the Sites 64 MiB receive-pack limit. The current
# live version remains immutable until a subsequent owner-private deployment.
parts_dir="dist/beta24-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
mkdir -p "$parts_dir"
split -b 8388608 -d -a 2 "$apk" "$parts_dir/part-"
test "$(cat "$parts_dir"/part-* | sha256sum | cut -d' ' -f1)" = "$expected_hash"
git config user.name 'Convoy protected CI'
git config user.email 'actions@users.noreply.github.com'
parts=("$parts_dir"/part-*)
for ((index=0; index<${#parts[@]}; index+=4)); do
  git add "${parts[@]:index:4}"
  if ! git diff --cached --quiet; then
    git commit --quiet -m 'Stage verified private APK parts'
    git push --quiet origin HEAD:refs/heads/main
  fi
done
# Reuse the existing download page and switch it to the verified +24 bytes.
python3 - "$expected_hash" "$expected_size" "$parts_dir" <<'PY'
from pathlib import Path
import re
import sys

digest, size, directory = sys.argv[1:]
page = Path("dist/index.html")
page.write_text(re.sub(r"[0-9a-f]{64}", digest, page.read_text())
                .replace("+23", "+24")
                .replace("dalla +22", "dalla +23")
                .replace("165,3 MB", f"{int(size) / 1_000_000:.1f} MB".replace(".", ",")))
script = Path("dist/download.js")
text = script.read_text().replace("Convoy-Outdoor-Beta-23.apk", "Convoy-Outdoor-Beta-24.apk")
text = re.sub(r"const expectedSize = \d+;", f"const expectedSize = {size};", text)
text = re.sub(r"const expectedDigest = '[0-9a-f]{64}';", f"const expectedDigest = '{digest}';", text)
text = re.sub(r"fetch\('[^']*/part-'", f"fetch('{directory.removeprefix('dist/')}/part-'", text)
script.write_text(text)
assert all(value in text for value in (size, digest, directory.removeprefix("dist/")))
PY
cp "$receipt" dist/receipt.json
if [[ -d dist/parts ]]; then git rm -qr dist/parts; fi
git add dist/index.html dist/download.js dist/receipt.json
if ! git diff --cached --quiet; then
  git commit --quiet -m 'Prepare one owner-private signed Outdoor +24 download'
  git push --quiet origin HEAD:refs/heads/main
fi
unset GIT_CONFIG_VALUE_0
printf 'Private Site source prepared at %s\n' "$(git rev-parse HEAD)"
