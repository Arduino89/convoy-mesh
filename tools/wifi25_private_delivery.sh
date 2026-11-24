#!/usr/bin/env bash
# Retrieve verified +24 and stage verified +25 on the existing private Site.
# Only a wrapped, short-lived transport credential may use the public repo.
set -euo pipefail
set +x
umask 077
site_id=appgprj_6b0475c8e9348191bd3b3a0715880f9c
remote=https://git.chatgpt-team.site/58a70ba3-41f5-47ae-afae-59a6e052ab91/$site_id.git
private="${RUNNER_TEMP:?}/convoy-wifi25-private"
: "${SOURCE_COMMIT:?}"

git_settings() {
  local token
  read -r token < "$private/token"
  [[ "$token" =~ ^[a-zA-Z0-9_-]+$ ]]
  export GIT_CONFIG_COUNT=2 GIT_TERMINAL_PROMPT=0
  export GIT_CONFIG_KEY_0="http.$remote.extraHeader" GIT_CONFIG_VALUE_0="Authorization: Bearer $token"
  export GIT_CONFIG_KEY_1=http.postBuffer GIT_CONFIG_VALUE_1=67108864
}

if [[ ${1:?operation required} == prepare ]]; then
  : "${WIFI23_RECIPIENT_PEM:?Protected recipient key required for the Sites transport credential}"
  mkdir "$private"
  key="$private/recipient.pem"
  printf '%s\n' "$WIFI23_RECIPIENT_PEM" > "$key"
  unset WIFI23_RECIPIENT_PEM
  trap 'rm -f -- "$key"' EXIT
  expected=7f4441ae6dea4a2821c8b03d41ddcdad8bf19d7b543352155048fab39bb95921
  test "$(openssl x509 -in "$key" -outform DER | sha256sum | cut -d' ' -f1)" = "$expected"
  echo 'Waiting for the short-lived private Sites transport credential'
  deadline=$((SECONDS + 600))
  while (( SECONDS < deadline )); do
    if gh api -H 'Accept: application/vnd.github.raw+json' \
        "repos/$GITHUB_REPOSITORY/contents/.github/convoy-wifi25-delivery.json?ref=$GITHUB_REF_NAME" \
        > "$private/transport.json" 2>/dev/null &&
      jq -e --arg run "$GITHUB_RUN_ID" --arg attempt "$GITHUB_RUN_ATTEMPT" --arg source "$SOURCE_COMMIT" \
        '.run == $run and .attempt == $attempt and .source_sha == $source and
          (.expires_at | type == "number") and .expires_at > (now + 480)' "$private/transport.json" >/dev/null 2>&1; then
      token=$(jq -er '.wrapped_token | strings' "$private/transport.json" | base64 --decode |
        openssl pkeyutl -decrypt -inkey "$key" -pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256)
      break
    fi
    sleep 10
  done
  : "${token:?Private Sites transport credential unavailable before the runner deadline}"
  printf '%s\n' "$token" > "$private/token"
  unset token
  git_settings
  git clone --quiet --depth 1 --branch main "$remote" "$private/site"
  cd "$private/site"
  jq -e --arg id "$site_id" '.project_id == $id and .static.directory == "dist"' .openai/hosting.json >/dev/null
  jq -e --arg sha "$BASE_HASH" '.apk_sha256 == $sha and .version_code == 24 and
    .signing_run == "45336135101" and .attempt == "2"' dist/receipt.json >/dev/null
  cat dist/beta24-45336135101-2/part-* > "$private/Convoy-Outdoor-Beta-24.apk"
  printf '%s  %s\n' "$BASE_HASH" "$private/Convoy-Outdoor-Beta-24.apk" | sha256sum --check -
  exit
fi

test "$1" = stage
apk=$(realpath "${2:?verified APK required}")
receipt=$(realpath "${3:?verified receipt required}")
expected_hash=$(jq -er '.apk_sha256 | strings | select(test("^[0-9a-f]{64}$"))' "$receipt")
expected_size=$(jq -er '.apk_bytes | numbers' "$receipt")
printf '%s  %s\n' "$expected_hash" "$apk" | sha256sum --check -
test "$(stat -c%s "$apk")" = "$expected_size"
jq -e --arg source "$SOURCE_COMMIT" --arg run "$GITHUB_RUN_ID" --arg attempt "$GITHUB_RUN_ATTEMPT" \
  '.source_sha == $source and .signing_run == $run and .attempt == $attempt and .version_code == 25 and .upgrade_api == 35' "$receipt" >/dev/null
git_settings
cd "$private/site"
parts_dir="dist/beta25-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
mkdir -p "$parts_dir"
split -b 8388608 -d -a 2 "$apk" "$parts_dir/part-"
test "$(cat "$parts_dir"/part-* | sha256sum | cut -d' ' -f1)" = "$expected_hash"
git config user.name 'Convoy protected CI'
git config user.email 'actions@users.noreply.github.com'
parts=("$parts_dir"/part-*)
for ((index=0; index<${#parts[@]}; index+=4)); do
  git add "${parts[@]:index:4}"
  git commit --quiet -m 'Stage verified private APK parts'
  git push --quiet origin HEAD:refs/heads/main
done
python3 - "$expected_hash" "$expected_size" "$parts_dir" <<'PY'
from pathlib import Path
import re
import sys

digest, size, directory = sys.argv[1:]
page = Path("dist/index.html")
page.write_text(re.sub(r"[a-f0-9]{64}", digest, page.read_text())
                .replace("+24", "+25").replace("dalla +23", "dalla +24"))
page.write_text(re.sub(r"\d+,\d+ MB", f"{int(size) / 1_000_000:.1f} MB".replace(".", ","), page.read_text()))
script = Path("dist/download.js")
text = script.read_text().replace("Convoy-Outdoor-Beta-24.apk", "Convoy-Outdoor-Beta-25.apk")
text = re.sub(r"const expectedSize = \d+;", f"const expectedSize = {size};", text)
text = re.sub(r"const expectedDigest = '[a-f0-9]{64}';", f"const expectedDigest = '{digest}';", text)
text = re.sub(r"fetch\('[^']*/part-'", f"fetch('{directory.removeprefix('dist/')}/part-'", text)
assert all(value in text for value in (size, digest, directory.removeprefix("dist/"), "Beta-25.apk"))
script.write_text(text)
PY
cp "$receipt" dist/receipt.json
git rm -qr dist/beta24-45336135101-2
git add dist/index.html dist/download.js dist/receipt.json
git commit --quiet -m 'Prepare owner-private signed Outdoor +25 download'
git push --quiet origin HEAD:refs/heads/main
unset GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_CONFIG_KEY_1 GIT_CONFIG_VALUE_1
printf 'Private Site source prepared at %s\n' "$(git rev-parse HEAD)"
