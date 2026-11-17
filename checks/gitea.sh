# SPDX-License-Identifier: AGPL-3.0-only
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # Dockwell's scripts/catalog-e2e.sh sets what this reads and reads what this sets
#
# gitea's check, which Dockwell's scripts/catalog-e2e.sh sources to prove an install
# and an upgrade of it (Dockwell's ADR 0100): check_gitea first, once it's installed,
# and check_gitea upgraded, once it's upgraded from an earlier release. It answers,
# signs in with what Dockwell generated, and after an upgrade finds what it wrote.
# Where Dockwell makes its owner, it proves the owner is there and no one else can
# take Gitea; where it doesn't, as an install from before keeps, it makes one.

# The release before, by its version and each image by digest, which an upgrade
# is proven from where the catalog's history holds none of another version.
before[gitea]="28.1.0 gitea/gitea:28.1.0@sha256:f505a0d3a41323b786e05942fc7a4075e07ae7c169fd9485649aa55ee543a21a"

# What a person gives its install, as dockwell catalog install takes it: the owner's
# email and password, which only this release takes, so the check signs in as the
# owner Dockwell makes. A release before that takes neither gets neither.
given[gitea]="OWNER_EMAIL=owner@example.com OWNER_PASSWORD"
given_env[gitea]="OWNER_PASSWORD=Ow9Kx7Vq2mRt9Lw4zBpN8cT3"

# gitea_owner_made waits for the owner Dockwell makes as the entry says (Dockwell's
# ADR 0105), giving it an email where an install by a token waits for one, and says
# no where the install has none, as one from before upgraded keeps.
gitea_owner_made() {
  local said state planned
  for _ in $(seq 100); do
    said=$(dw catalog installs --json) || fail "catalog installs failed"
    state=$(jq -r --arg p "$installed" '.installs[] | select(.project == $p) | .owner.state // empty' <<<"$said")
    case "$state" in
    "") return 1 ;;
    CATALOG_OWNER_STATE_MADE) return 0 ;;
    CATALOG_OWNER_STATE_FAILED) fail "Dockwell couldn't make Gitea's owner: $(jq -c --arg p "$installed" '.installs[] | select(.project == $p) | .owner' <<<"$said")" ;;
    CATALOG_OWNER_STATE_WAITING_EMAIL)
      planned=$(dw catalog set-owner-email "$installed" --email owner@example.com --plan-only --json) || fail "planning Gitea's owner's email failed: $planned"
      plans+=("$(jq -r .change.id <<<"$planned")")
      apply "${plans[-1]}"
      ;;
    esac
    sleep 3
  done
  fail "Dockwell didn't make Gitea's owner within 5 minutes: it reads $state"
}

check_gitea() {
  local gitea port said banner key admins password=E2e-owner-passw0rd
  gitea=$(container gitea)
  port=$(value PORT)
  said=$(curl -fsS --max-time 10 "http://127.0.0.1:$port/api/v1/version") || fail "Gitea doesn't answer on port $port"
  [[ "$(jq -r .version <<<"$said")" == "$version" ]] || fail "Gitea says it's $said, want $version"
  # It encrypts with the key Dockwell generated, not the one its source publishes.
  key=$(docker exec "$gitea" sed -n 's/^SECRET_KEY *= *//p' /data/gitea/conf/app.ini) || fail "Gitea has no app.ini"
  [[ ${#key} -ge 64 && "$key" == "$(env_of "$gitea" GITEA__security__SECRET_KEY)" ]] || fail "Gitea's SECRET_KEY isn't the one Dockwell generated"
  if gitea_owner_made; then
    # Made as the installer, from the email, with its sign-ups closed at install.
    admins=$(docker exec -u git "$gitea" gitea admin user list --admin) || fail "Gitea can't list its admins"
    [[ "$(awk 'NR > 1 {print $2}' <<<"$admins")" == owner ]] || fail "Gitea's admins are $admins, want the owner Dockwell made alone"
    [[ "$(env_of "$gitea" GITEA__service__DISABLE_REGISTRATION)" == true ]] || fail "Gitea's sign-ups are open"
    password=Ow9Kx7Vq2mRt9Lw4zBpN8cT3
  elif [[ "$1" == first ]]; then
    docker exec -u git "$gitea" gitea admin user create --username owner --password "$password" --email owner@example.com --admin --must-change-password=false >/dev/null ||
      fail "Gitea can't make a user"
  fi
  # What it keeps is on its volume, so the user signs in after an upgrade too.
  said=$(curl -fsS --max-time 10 -u "owner:$password" "http://127.0.0.1:$port/api/v1/user") || fail "Gitea's owner can't sign in"
  [[ "$(jq -r .login <<<"$said")" == owner ]] || fail "Gitea signed in as $said"
  said=$(curl -sS --max-time 10 -o /dev/null -w '%{http_code}' -u owner:not-the-password "http://127.0.0.1:$port/api/v1/user") || fail "Gitea's sign-in got no answer"
  [[ "$said" == 401 ]] || fail "Gitea answered $said to a wrong password"
  banner=$(exec 3<>"/dev/tcp/127.0.0.1/$(value SSH_PORT)" && timeout 5 head -c 7 <&3) || fail "Gitea's SSH doesn't answer"
  [[ "$banner" == SSH-2.0 ]] || fail "Gitea's SSH port answers '$banner'"
}
