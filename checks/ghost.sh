# SPDX-License-Identifier: AGPL-3.0-only
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # Dockwell's scripts/catalog-e2e.sh sets what this reads and reads what this sets
#
# ghost's check, which Dockwell's scripts/catalog-e2e.sh sources to prove an install
# and an upgrade of it (Dockwell's ADR 0100): check_ghost first, once it's installed,
# and check_ghost upgraded, once it's upgraded from an earlier release. It answers,
# signs in with what Dockwell generated, and after an upgrade finds what it wrote.
# Where Dockwell makes its owner, it proves the owner is there and no one else can
# take Ghost; where it doesn't, as an install from before keeps, it makes one.

# The release before, by its version and each image by digest, which an upgrade
# is proven from where the catalog's history holds none of another version.
before[ghost]="6.71.0 ghost:6.71.0@sha256:00032f15726204565bf799ac272ee6fef588547cce50bedd38de3db55272c053"

# What a person gives its install, as dockwell catalog install takes it: the owner's
# email and password, which only this release takes, so the check signs in as the
# owner Dockwell makes. A release before that takes neither gets neither.
given[ghost]="URL=https://blog.example.com OWNER_EMAIL=owner@example.com OWNER_PASSWORD"
given_env[ghost]="OWNER_PASSWORD=Ow9Kx7Vq2mRt9Lw4zBpN8cT3"

# ghost_get asks Ghost as the https proxy in front of it does.
ghost_get() {
  curl -fsS --max-time 15 -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$1$2"
}

# ghost_owner_made waits for the owner Dockwell makes as the entry says (Dockwell's
# ADR 0105), giving it an email where an install by a token waits for one, and says
# no where the install has none, as one from before upgraded keeps.
ghost_owner_made() {
  local said owner_state planned
  for _ in $(seq 100); do
    said=$(dw catalog installs --json) || fail "catalog installs failed"
    owner_state=$(jq -r --arg p "$installed" '.installs[] | select(.project == $p) | .owner.state // empty' <<<"$said")
    case "$owner_state" in
    "") return 1 ;;
    CATALOG_OWNER_STATE_MADE) return 0 ;;
    CATALOG_OWNER_STATE_FAILED) fail "Dockwell couldn't make Ghost's owner: $(jq -c --arg p "$installed" '.installs[] | select(.project == $p) | .owner' <<<"$said")" ;;
    CATALOG_OWNER_STATE_WAITING_EMAIL)
      planned=$(dw catalog set-owner-email "$installed" --email owner@example.com --plan-only --json) || fail "planning Ghost's owner's email failed: $planned"
      plans+=("$(jq -r .change.id <<<"$planned")")
      apply "${plans[-1]}"
      ;;
    esac
    sleep 3
  done
  fail "Dockwell didn't make Ghost's owner within 5 minutes: it reads $owner_state"
}

# ghost_sign_in signs in as a fresh client, with no cookie of a device Ghost knows,
# and says the status Ghost answered.
ghost_sign_in() {
  curl -sS --max-time 30 -o /dev/null -w '%{http_code}' -H 'X-Forwarded-Proto: https' -H 'Content-Type: application/json' -H 'Origin: https://blog.example.com' \
    -d "$(jq -nc --arg u owner@example.com --arg p "$2" '{username: $u, password: $p}')" "http://127.0.0.1:$1/ghost/api/admin/session"
}

check_ghost() {
  local ghost port said reported title="E2E kept" password="Kx7-Vq2!mRt9-Lw4zB"
  ghost=$(container ghost)
  port=$(value PORT)
  # It's given an https address, as behind a domain, so it answers what the proxy in front
  # sends, and sends anything else there. Its health check asks as that proxy does.
  said=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code} %{redirect_url}' "http://127.0.0.1:$port/ghost/api/admin/site/") || fail "Ghost doesn't answer on port $port"
  [[ "$said" == 30?\ https://blog.example.com/ghost/* ]] || fail "Ghost answers '$said' to plain http, want it sent to https://blog.example.com"
  said=$(ghost_get "$port" /ghost/api/admin/site/) || fail "Ghost doesn't answer on port $port behind an https proxy"
  # It says its version without the patch, and its image says the whole of it.
  reported=$(jq -r '.site.version // empty' <<<"$said")
  [[ -n "$reported" && "$reported" == "${version%.*}" && "$(env_of "$ghost" GHOST_VERSION)" == "$version" ]] ||
    fail "Ghost says it's '$reported' and its image '$(env_of "$ghost" GHOST_VERSION)', want $version"
  [[ "$(env_of "$ghost" url)" == https://blog.example.com ]] || fail "Ghost's url is '$(env_of "$ghost" url)', want the address it was given"
  if ghost_owner_made; then
    # Made from inside its container at its https address, as its steps ask, so its
    # setup is done, and a first visitor's is refused.
    said=$(ghost_get "$port" /ghost/api/admin/authentication/setup/) || fail "Ghost's setup doesn't answer"
    [[ "$(jq -r '.setup[0].status' <<<"$said")" == true ]] || fail "Ghost still offers its setup: $said"
    said=$(curl -sS --max-time 30 -o /dev/null -w '%{http_code}' -H 'X-Forwarded-Proto: https' -H 'Content-Type: application/json' -H 'Origin: https://blog.example.com' \
      -d '{"setup":[{"name":"Visitor","email":"visitor@example.com","password":"Kx7-Vq2!mRt9-Lw4zB","blogTitle":"Taken"}]}' \
      "http://127.0.0.1:$port/ghost/api/admin/authentication/setup/") || fail "Ghost's setup got no answer"
    [[ "$said" == 4?? ]] || fail "Ghost let a first visitor set it up: it answered $said"
    title=Ghost password=Ow9Kx7Vq2mRt9Lw4zBpN8cT3
  elif [[ "$1" == first ]]; then
    # Ghost refuses a password with a common word in it, such as passw0rd, so this has none.
    said=$(curl -sS --max-time 30 -w '\n%{http_code}' -H 'X-Forwarded-Proto: https' -H 'Content-Type: application/json' -H 'Origin: https://blog.example.com' \
      -d "$(jq -nc --arg p "$password" '{setup: [{name: "Owner", email: "owner@example.com", password: $p, blogTitle: "E2E kept"}]}')" \
      "http://127.0.0.1:$port/ghost/api/admin/authentication/setup/") || fail "Ghost's setup got no answer"
    [[ "${said##*$'\n'}" == 201 ]] || fail "Ghost didn't make its owner: it answered ${said##*$'\n'}, saying ${said%$'\n'*}"
  fi
  # What it keeps is in MySQL, so the site keeps its title through an upgrade.
  said=$(ghost_get "$port" /ghost/api/admin/site/) || fail "Ghost doesn't answer on port $port behind an https proxy"
  [[ "$(jq -r .site.title <<<"$said")" == "$title" ]] || fail "Ghost's site reads $said, want the title $title"
  # A release that turns staff device verification off lets its owner sign in from a
  # fresh client, with no code it would email; an earlier one asks for the code.
  if [[ "$(env_of "$ghost" security__staffDeviceVerification)" == false ]]; then
    said=$(ghost_sign_in "$port" "$password") || fail "Ghost's sign-in got no answer"
    [[ "$said" == 201 ]] || fail "Ghost's owner can't sign in from a fresh client: it answered $said"
  fi
  said=$(ghost_sign_in "$port" not-the-password) || fail "Ghost's sign-in got no answer"
  [[ "$said" == 4?? ]] || fail "Ghost answered $said to a wrong password"
}
