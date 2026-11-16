# SPDX-License-Identifier: AGPL-3.0-only
# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # Dockwell's scripts/catalog-e2e.sh sets what this reads and reads what this sets
#
# cloudflared's check, which Dockwell's scripts/catalog-e2e.sh sources to prove an
# install and an upgrade of it (Dockwell's ADR 0100): check_cloudflared first, once
# it's installed, and check_cloudflared upgraded, once it's upgraded from an earlier
# release.
#
# A tunnel needs a Cloudflare account, which the proof has none of, so this proves
# what a release can without one (Dockwell #745, option 1): given the token of a
# tunnel that doesn't exist, the release starts, reads the token, opens a connection
# to Cloudflare's edge, completes the handshake there, and is refused by the edge,
# "Failed to get tunnel". That shows the binary runs on this platform, its TLS and
# its tunnel protocol reach Cloudflare and are understood, and the token's form is
# the one the release reads. It's held to that, not to staying up: on a refused token
# cloudflared retries for about two minutes, then stops and starts again.

# A made-up token, of the form Cloudflare gives one: its account tag, its tunnel's ID
# and its secret, as base64 of JSON. None of it is real, so the edge refuses it. It's
# the same in every process that reads this file, so the check finds the tunnel ID it
# gave.
cloudflared_tunnel=c7450000-0000-4000-8000-000000000745
given[cloudflared]="TUNNEL_TOKEN"
given_env[cloudflared]="TUNNEL_TOKEN=$(printf '{"a":"0000000000000000000000000000c745","t":"%s","s":"Y2F0YWxvZy1wcm9vZi1ub3QtYS1yZWFsLXR1bm5lbA=="}' "$cloudflared_tunnel" | base64 -w0)"
# Its tunnel runs on a token its far end refuses: the proof holds it neither to its
# health check nor to running for a while, and this check proves the refusal instead.
# Dockwell's scripts/catalog-e2e.sh reads refused once Dockwell's t3/745-refused-hold
# lands and .github/dockwell-commit moves past it. An earlier one stops on this line,
# as refused isn't declared there.
refused[cloudflared]="tunnel"

check_cloudflared() {
  local tunnel said
  # The edge answers within seconds; the first connection can wait on DNS and the
  # runner's network, so up to 90 s, as cloudflared's own health check allowed.
  for _ in $(seq 90); do
    tunnel=$(container tunnel)
    said=$(docker logs "$tunnel" 2>&1) || fail "docker logs $tunnel failed"
    # It read the token as the tunnel it names, connected to the edge, and the edge
    # answered it: refused, as a tunnel that doesn't exist is.
    if grep -q "Starting tunnel tunnelID=$cloudflared_tunnel" <<<"$said" &&
      grep -q 'Register tunnel error from server side error="Failed to get tunnel"' <<<"$said"; then
      # Nothing else went wrong first: no crash, and no token it couldn't read.
      if grep -qiE 'panic:|invalid tunnel token|Provided Tunnel token is not valid' <<<"$said"; then
        fail "cloudflared reached the edge, and said this too: $(grep -iE 'panic:|invalid tunnel token|Provided Tunnel token is not valid' <<<"$said" | head -3)"
      fi
      return 0
    fi
    sleep 1
  done
  fail "cloudflared never reached Cloudflare's edge and was refused there with \"Failed to get tunnel\" in 90 s. It said: $(tail -20 <<<"$said")"
}
