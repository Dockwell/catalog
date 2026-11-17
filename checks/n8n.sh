# SPDX-License-Identifier: AGPL-3.0-only
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # Dockwell's scripts/catalog-e2e.sh sets what this reads and reads what this sets
#
# n8n's check, which Dockwell's scripts/catalog-e2e.sh sources to prove an install
# and an upgrade of it (Dockwell's ADR 0100): check_n8n first, once it's installed,
# and check_n8n upgraded, once it's upgraded from an earlier release. It answers,
# signs in with what Dockwell generated, and after an upgrade finds what it wrote.
# Where Dockwell makes its owner, it proves the owner is there and no one else can
# take n8n; where it doesn't, as an install from before keeps, it makes one.

# The release before, by its version and each image by digest, which an upgrade
# is proven from where the catalog's history holds none of another version.
before[n8n]="2.44.6 n8nio/n8n:2.44.6@sha256:d02752c6ab446ae9db8deec2f9cc887c378f77cdcad31650814df936b7386dfb"

# n8n_owner_made waits for the owner Dockwell makes as the entry says (Dockwell's
# ADR 0105), giving it an email where an install by a token waits for one, and says
# no where the install has none, as one from before upgraded keeps.
n8n_owner_made() {
  local said state planned
  for _ in $(seq 100); do
    said=$(dw catalog installs --json) || fail "catalog installs failed"
    state=$(jq -r --arg p "$installed" '.installs[] | select(.project == $p) | .owner.state // empty' <<<"$said")
    case "$state" in
    "") return 1 ;;
    CATALOG_OWNER_STATE_MADE) return 0 ;;
    CATALOG_OWNER_STATE_FAILED) fail "Dockwell couldn't make n8n's owner: $(jq -c --arg p "$installed" '.installs[] | select(.project == $p) | .owner' <<<"$said")" ;;
    CATALOG_OWNER_STATE_WAITING_EMAIL)
      planned=$(dw catalog set-owner-email "$installed" --email owner@example.com --plan-only --json) || fail "planning n8n's owner's email failed: $planned"
      plans+=("$(jq -r .change.id <<<"$planned")")
      apply "${plans[-1]}"
      ;;
    esac
    sleep 3
  done
  fail "Dockwell didn't make n8n's owner within 5 minutes: it reads $state"
}

check_n8n() {
  local port said owner
  port=$(value PORT)
  said=$(curl -fsS --max-time 10 "http://127.0.0.1:$port/healthz/readiness") || fail "n8n isn't ready on port $port, with its database"
  [[ "$(jq -r .status <<<"$said")" == ok ]] || fail "n8n says it's $said"
  owner='{"email":"owner@example.com","password":"E2e-owner-passw0rd"}'
  n8n_sign_in() {
    curl -sS --max-time 15 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
      -d "$(jq -c --arg p "$1" '{emailOrLdapLoginId: .email, password: $p}' <<<"$owner")" "http://127.0.0.1:$port/rest/login"
  }
  if n8n_owner_made; then
    said=$(curl -fsS --max-time 15 "http://127.0.0.1:$port/rest/settings") || fail "n8n's settings got no answer"
    [[ "$(jq -r '.data.userManagement.showSetupOnFirstLoad' <<<"$said")" == false ]] || fail "n8n still offers its owner's setup: $said"
    # A first visitor's setup is refused, as n8n has its owner.
    said=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
      -d '{"email":"visitor@example.com","firstName":"A","lastName":"Visitor","password":"Visitor7Passw0rdX"}' "http://127.0.0.1:$port/rest/owner/setup") || fail "n8n's owner setup got no answer"
    [[ "$said" == 4?? ]] || fail "n8n let a first visitor make its owner: it answered $said"
  else
    if [[ "$1" == first ]]; then
      said=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
        -d "$(jq -c '. + {firstName: "Owner", lastName: "Example"}' <<<"$owner")" "http://127.0.0.1:$port/rest/owner/setup") || fail "n8n's owner setup got no answer"
      [[ "$said" == 200 ]] || fail "n8n didn't make its owner: it answered $said"
    fi
    [[ "$(n8n_sign_in "$(jq -r .password <<<"$owner")")" == 200 ]] || fail "n8n's owner can't sign in"
  fi
  [[ "$(n8n_sign_in not-the-password)" == 401 ]] || fail "n8n didn't refuse a wrong password"
}
