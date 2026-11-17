# SPDX-License-Identifier: AGPL-3.0-only
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # Dockwell's scripts/catalog-e2e.sh sets what this reads and reads what this sets
#
# umami's check, which Dockwell's scripts/catalog-e2e.sh sources to prove an install
# and an upgrade of it (Dockwell's ADR 0100): check_umami first, once it's installed,
# and check_umami upgraded, once it's upgraded from an earlier release. It answers,
# signs in with what Dockwell generated, and after an upgrade finds what it wrote.
# Where Dockwell makes its owner, it proves admin's known password no longer signs in.

# The release before, by its version and each image by digest, which an upgrade
# is proven from where the catalog's history holds none of another version.
before[umami]="3.4.0 ghcr.io/umami-software/umami:3.4.0@sha256:85909afc45bdcda1917394594a087421fdbb05610fded0fa9f6fb861abb2f367"

# What a person gives its install, as dockwell catalog install takes it: the owner's
# user and password, which only this release takes, so the check signs in as the
# owner Dockwell makes from admin. A release before that takes neither gets neither.
given[umami]="OWNER_USER=owner OWNER_PASSWORD"
given_env[umami]="OWNER_PASSWORD=Ow9Kx7Vq2mRt9Lw4zBpN8cT3"

# umami_owner_made waits for the owner Dockwell makes from the account Umami starts
# with (Dockwell's ADR 0105), and says no where the install has none, as one from
# before upgraded keeps.
umami_owner_made() {
  local said owner_state
  for _ in $(seq 100); do
    said=$(dw catalog installs --json) || fail "catalog installs failed"
    owner_state=$(jq -r --arg p "$installed" '.installs[] | select(.project == $p) | .owner.state // empty' <<<"$said")
    case "$owner_state" in
    "") return 1 ;;
    CATALOG_OWNER_STATE_MADE) return 0 ;;
    CATALOG_OWNER_STATE_FAILED) fail "Dockwell couldn't make Umami's owner: $(jq -c --arg p "$installed" '.installs[] | select(.project == $p) | .owner' <<<"$said")" ;;
    esac
    sleep 3
  done
  fail "Dockwell didn't make Umami's owner within 5 minutes: it reads $owner_state"
}

check_umami() {
  local port said token who user=admin password=umami
  port=$(value PORT)
  umami_sign_in() {
    curl -sS --max-time 15 -H 'Content-Type: application/json' -d "{\"username\":\"$1\",\"password\":\"$2\"}" "http://127.0.0.1:$port/api/auth/login"
  }
  if umami_owner_made; then
    user=owner password=Ow9Kx7Vq2mRt9Lw4zBpN8cT3
    # No one signs in with the password everyone knows, as admin or as the owner.
    for who in admin owner; do
      said=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
        -d "{\"username\":\"$who\",\"password\":\"umami\"}" "http://127.0.0.1:$port/api/auth/login") || fail "Umami's sign-in got no answer"
      [[ "$said" == 401 ]] || fail "Umami signs $who in with the password everyone knows: $said"
    done
  fi
  said=$(umami_sign_in "$user" "$password") || fail "Umami doesn't answer on port $port"
  token=$(jq -r '.token // empty' <<<"$said" 2>/dev/null)
  [[ -n "$token" ]] || fail "Umami doesn't sign $user in: ${said:0:300}"
  if [[ "$1" == first ]]; then
    said=$(curl -fsS --max-time 15 -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
      -d '{"name":"e2e-kept","domain":"example.com"}' "http://127.0.0.1:$port/api/websites") || fail "Umami doesn't add a site"
    kept[umami]=$(jq -r .id <<<"$said")
  fi
  said=$(curl -fsS --max-time 15 -H "Authorization: Bearer $token" "http://127.0.0.1:$port/api/websites/${kept[umami]}") ||
    fail "Umami doesn't have the site added before the upgrade"
  [[ "$(jq -r .name <<<"$said")" == e2e-kept ]] || fail "Umami's site reads $said"
  said=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
    -d "{\"username\":\"$user\",\"password\":\"not-the-password\"}" "http://127.0.0.1:$port/api/auth/login") || fail "Umami's sign-in got no answer"
  [[ "$said" == 401 ]] || fail "Umami answered $said to a wrong password, want 401"
}
