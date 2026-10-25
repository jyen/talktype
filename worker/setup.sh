#!/bin/bash
# One-shot setup: create the D1 db, wire wrangler.toml, set the token secret, deploy.
set -euo pipefail
cd "$(dirname "$0")"

command -v wrangler >/dev/null || { echo "install wrangler first: npm i -g wrangler"; exit 1; }
wrangler whoami >/dev/null 2>&1 || { echo "run 'wrangler login' first"; exit 1; }

if [ ! -f wrangler.toml ]; then
  cp wrangler.toml.example wrangler.toml
  echo "created wrangler.toml from example"
fi

# account id (from env or whoami) — only patch if still the placeholder
if grep -q 'YOUR_ACCOUNT_ID' wrangler.toml; then
  ACC="${CLOUDFLARE_ACCOUNT_ID:-$(wrangler whoami 2>/dev/null | grep -oE '[0-9a-f]{32}' | head -1 || true)}"
  [ -n "$ACC" ] && perl -pi -e "s/YOUR_ACCOUNT_ID/$ACC/" wrangler.toml && echo "account_id set"
fi

# create the D1 db if we don't have an id yet
if grep -q 'YOUR_D1_DATABASE_ID' wrangler.toml; then
  echo "creating D1 database 'talktype'..."
  OUT="$(wrangler d1 create talktype 2>&1 || true)"
  echo "$OUT"
  DBID="$(echo "$OUT" | grep -oE '[0-9a-f-]{36}' | head -1)"
  [ -z "$DBID" ] && { echo "couldn't parse database_id — paste it into wrangler.toml manually"; exit 1; }
  perl -pi -e "s/YOUR_D1_DATABASE_ID/$DBID/" wrangler.toml
  echo "database_id set: $DBID"
fi

echo "applying schema..."
wrangler d1 execute talktype --remote --file=schema.sql

if [ -z "${FLOW_TOKEN:-}" ]; then
  echo "no FLOW_TOKEN in env — generating one:"
  FLOW_TOKEN="$(openssl rand -hex 16)"
  echo "  FLOW_TOKEN=$FLOW_TOKEN   (save this — your clients need it)"
fi
printf '%s' "$FLOW_TOKEN" | wrangler secret put FLOW_TOKEN

echo "deploying..."
wrangler deploy
echo "done. your token is: $FLOW_TOKEN"
