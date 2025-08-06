#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../chains/ts-cli"

pnpm i >/dev/null
pnpm build >/dev/null

# Create a minimal proposal with no instructions (safe)
PROP_JSON=$(cat <<'JSON'
{
  "realm":"__REALM__",
  "governance":"__GOV__",
  "title":"Sentinel Swarm Demo",
  "descriptionMd":"Smoke test",
  "instructions": [],
  "rpc":"__RPC__",
  "wallet":__WALLET__
}
JSON
)

PROP_JSON="${PROP_JSON/__REALM__/$REALMS_REALM_PUBKEY}"
PROP_JSON="${PROP_JSON/__GOV__/$REALMS_GOVERNANCE_PUBKEY}"
PROP_JSON="${PROP_JSON/__RPC__/$SOLANA_RPC_URL}"
PROP_JSON="${PROP_JSON/__WALLET__/$SOLANA_WALLET_PRIVATE_KEY}"

OUT_PROP=$(echo "$PROP_JSON" | node dist/index.js proposal-create)
echo "[create] $OUT_PROP" >/dev/null

OUT_POST=$(jq -n --argjson pj "$OUT_PROP" --arg rpc "$SOLANA_RPC_URL" --argjson w "$SOLANA_WALLET_PRIVATE_KEY" '{rpc:$rpc, wallet:$w, proposalJson:$pj}')
RESP=$(echo "$OUT_POST" | node dist/index.js proposal-post)

echo "$RESP" | jq .
