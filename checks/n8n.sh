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

# What a person gives its install, as dockwell catalog install takes it: the owner's
# email and password, which only this release takes, so the check signs in as the
# owner Dockwell makes. A release before that takes neither gets neither.
given[n8n]="OWNER_EMAIL=owner@example.com OWNER_PASSWORD"
given_env[n8n]="OWNER_PASSWORD=Ow9Kx7Vq2mRt9Lw4zBpN8cT3"

# n8n_owner_made waits for the owner Dockwell makes as the entry says (Dockwell's
# ADR 0105), giving it an email where an install by a token waits for one, and says
# no where the install has none, as one from before upgraded keeps.
n8n_owner_made() {
  local said owner_state planned
  for _ in $(seq 100); do
    said=$(dw catalog installs --json) || fail "catalog installs failed"
    owner_state=$(jq -r --arg p "$installed" '.installs[] | select(.project == $p) | .owner.state // empty' <<<"$said")
    case "$owner_state" in
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
  fail "Dockwell didn't make n8n's owner within 5 minutes: it reads $owner_state"
}

# Publish a workflow that needs a credential encrypted by this install. A
# successful request after the upgrade proves the saved workflow can still
# run and decrypt the same credential.
n8n_publish_proof_workflow() {
  local url=$1 login_jar=$2 credential workflow workflow_id version_id

  n8n_api() {
    curl --ipv4 -fsS --max-time 20 -b "$login_jar" -H 'Content-Type: application/json' "$@"
  }

  credential=$(
    jq -cn --arg secret "${kept[n8n-proof-header]}" \
      '{name:"Dockwell proof header", type:"httpHeaderAuth", data:{name:"X-Dockwell-Proof", value:$secret}}' |
      n8n_api --data-binary @- "$url/rest/credentials" |
      jq -er '.data.id | select(type == "string" and length > 0)'
  ) || fail "n8n did not create the test workflow credential"
  workflow=$(
    jq -cn --arg credential "$credential" '{
      name: "Dockwell upgrade proof",
      nodes: [
        {
          id:"8c4c081d-96d4-4c26-b413-6da026d6ed46", name:"Webhook", type:"n8n-nodes-base.webhook",
          typeVersion:2, position:[0,0], webhookId:"ea6be8dc-66e0-4a2e-bdbd-53905de3bfca",
          parameters:{httpMethod:"GET",path:"dockwell-upgrade-proof",authentication:"headerAuth",
            responseMode:"lastNode",responseData:"firstEntryJson",options:{}},
          credentials:{httpHeaderAuth:{id:$credential,name:"Dockwell proof header"}}
        },
        {
          id:"ac005813-613d-4591-b7d1-87d8dc19c1ae", name:"Proof result", type:"n8n-nodes-base.set",
          typeVersion:3.4, position:[220,0],
          parameters:{mode:"manual",assignments:{assignments:[
            {id:"25b9e5eb-15ff-4a45-9ab0-e41a87de4690",name:"upgradeProof",type:"string",value:"kept-through-upgrade"}
          ]},options:{}}
        }
      ],
      connections:{Webhook:{main:[[{node:"Proof result",type:"main",index:0}]]}},
      settings:{executionOrder:"v1"}
    }' | n8n_api --data-binary @- "$url/rest/workflows"
  ) || fail "n8n did not create the test workflow"
  workflow_id=$(jq -er '.data.id | select(type == "string" and length > 0)' <<<"$workflow") ||
    fail "n8n did not return the test workflow ID"
  version_id=$(jq -er '.data.versionId | select(type == "string" and length > 0)' <<<"$workflow") ||
    fail "n8n did not return the test workflow version"
  jq -cn --arg version "$version_id" '{versionId: $version}' |
    n8n_api --data-binary @- "$url/rest/workflows/$workflow_id/activate" >/dev/null ||
    fail "n8n did not accept the test workflow publication"

  # Activation returns while n8n's publication worker registers the webhook.
  local publication
  for _ in $(seq 45); do
    publication=$(n8n_api "$url/rest/workflows/$workflow_id/publication-status") ||
      fail "Could not read the n8n workflow publication status"
    if jq -e --arg version "$version_id" \
      '.data.status == "published" and .data.liveVersionId == $version' <<<"$publication" >/dev/null; then
      return 0
    fi
    sleep 1
  done
  fail "n8n's test workflow did not go live. Publication status: $(jq -r '.data.status // "unknown"' <<<"$publication")"
}

check_n8n() {
  local port said owner url owner_password login_jar
  port=$(value PORT)
  url="http://localhost:$port"
  said=$(curl -fsS --max-time 10 "http://127.0.0.1:$port/healthz/readiness") || fail "n8n isn't ready on port $port, with its database"
  [[ "$(jq -r .status <<<"$said")" == ok ]] || fail "n8n says it's $said"
  owner='{"email":"owner@example.com","password":"E2e-owner-passw0rd"}'
  n8n_sign_in() {
    local password=$1
    shift
    curl --ipv4 -sS --max-time 15 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' "$@" \
      -d "$(jq -c --arg p "$password" '{emailOrLdapLoginId: .email, password: $p}' <<<"$owner")" "$url/rest/login"
  }
  if n8n_owner_made; then
    said=$(curl -fsS --max-time 15 "http://127.0.0.1:$port/rest/settings") || fail "n8n's settings got no answer"
    [[ "$(jq -r '.data.userManagement.showSetupOnFirstLoad' <<<"$said")" == false ]] || fail "n8n still offers its owner's setup: $said"
    # A first visitor's setup is refused, as n8n has its owner.
    said=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
      -d '{"email":"visitor@example.com","firstName":"A","lastName":"Visitor","password":"Visitor7Passw0rdX"}' "http://127.0.0.1:$port/rest/owner/setup") || fail "n8n's owner setup got no answer"
    [[ "$said" == 4?? ]] || fail "n8n let a first visitor make its owner: it answered $said"
    owner='{"email":"owner@example.com","password":"Ow9Kx7Vq2mRt9Lw4zBpN8cT3"}'
  elif [[ "$1" == first ]]; then
    said=$(curl -sS --max-time 15 -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' \
      -d "$(jq -c '. + {firstName: "Owner", lastName: "Example"}' <<<"$owner")" "http://127.0.0.1:$port/rest/owner/setup") || fail "n8n's owner setup got no answer"
    [[ "$said" == 200 ]] || fail "n8n didn't make its owner: it answered $said"
  fi
  owner_password=$(jq -r .password <<<"$owner")
  if [[ "$1" == first ]]; then
    kept[n8n-proof-header]=$(openssl rand -hex 24) || fail "Could not generate the n8n test credential"
    (
      login_jar=$(mktemp) || fail "Could not create a cookie jar for n8n"
      trap 'rm -f -- "$login_jar"' EXIT
      [[ "$(n8n_sign_in "$owner_password" -c "$login_jar")" == 200 ]] || fail "n8n's owner can't sign in"
      n8n_publish_proof_workflow "$url" "$login_jar"
    )
  else
    [[ "$(n8n_sign_in "$owner_password")" == 200 ]] || fail "n8n's owner can't sign in"
  fi
  [[ "$(n8n_sign_in not-the-password)" == 401 ]] || fail "n8n didn't refuse a wrong password"

  said=$(curl --ipv4 -sS --max-time 20 -o /dev/null -w '%{http_code}' \
    -H 'X-Dockwell-Proof: wrong' "$url/webhook/dockwell-upgrade-proof") ||
    fail "n8n's test webhook did not answer"
  [[ "$said" == 403 ]] || fail "n8n's test webhook answered $said to a wrong credential"
  curl --ipv4 -fsS --max-time 20 -H "X-Dockwell-Proof: ${kept[n8n-proof-header]}" \
    "$url/webhook/dockwell-upgrade-proof" |
    jq -e '.upgradeProof == "kept-through-upgrade"' >/dev/null ||
    fail "n8n did not run the test workflow with its saved credential"
}
