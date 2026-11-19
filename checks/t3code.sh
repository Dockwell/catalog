# SPDX-License-Identifier: AGPL-3.0-only
# shellcheck shell=bash

# Verify the catalog's single port serves Setup, takes the generated key, and
# keeps a workspace file made through Setup when the app upgrades.
check_t3code() {
  local port setup_url setup_key setup_cookie status
  local file_path=/workspace/dockwell-proof.txt file_text='Dockwell upgrade proof'
  port=$(value PORT)
  setup_url="http://127.0.0.1:$port/__setup"
  setup_key=$(generated t3code T3_SETUP_KEY)

  status=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' -H 'Accept: application/json' "$setup_url/status") ||
    fail "T3 Code Setup did not answer on port $port"
  [[ "$status" == 401 ]] || fail "T3 Code Setup answered $status without a key"

  (
    setup_cookie=$(mktemp) || fail "Could not create a cookie jar for T3 Code Setup"
    trap 'rm -f -- "$setup_cookie"' EXIT
    printf '%s' "$setup_key" |
      curl -fsS --max-time 10 -H 'Accept: application/json' -c "$setup_cookie" --data-urlencode 'key@-' "$setup_url/login" |
      jq -e '.ok == true' >/dev/null || fail "T3 Code Setup did not accept the generated key"
    curl -fsS --max-time 25 -b "$setup_cookie" "$setup_url/status" |
      jq -e '.singlePort.port == 8080' >/dev/null || fail "T3 Code Setup did not report its single port after sign-in"

    if [[ "$1" == first ]]; then
      jq -cn --arg path "$file_path" --arg text "$file_text" '{path: $path, text: $text, mode: "create"}' |
        curl -fsS --max-time 10 -b "$setup_cookie" -H 'Content-Type: application/json' --data-binary @-           "$setup_url/files/write" >/dev/null || fail "T3 Code Setup did not write the workspace file"
    fi
    curl -fsS --max-time 10 -b "$setup_cookie" --get --data-urlencode "path=$file_path" "$setup_url/files/read" |
      jq -e --arg text "$file_text" '.text == $text' >/dev/null || fail "T3 Code Setup did not find the workspace file"
  )
}
