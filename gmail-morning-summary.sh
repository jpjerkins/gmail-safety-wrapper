#!/bin/bash
#
# gmail-morning-summary.sh — Daily Gmail unread summary for pi5
#
# Reads unread counts by Gmail category using vault-t2 credentials,
# then overwrites a markdown note in the Nextcloud notes vault.
#
# Prerequisites on pi5:
#   - vault-t2 daemon running (systemctl status vault-t2-fuse)
#   - gws_credentials secret stored in vault-t2 (t2-set gws_credentials < oauth.json)
#   - This script's UID in vault-t2 ACL for gws_credentials
#   - gws CLI installed (npm install -g @googleworkspace/cli)
#   - jq installed (apt install jq)
#
# Usage:
#   ./gmail-morning-summary.sh
#
# Configuration via environment variables:
#   NOTE_PATH   Full path for the output markdown note
#               Default: ~/Nextcloud/Notes/0 Inbox/Gmail Morning Summary.md
#   VAULT_CREDS Path to gws credentials in vault-t2 FUSE mount
#               Default: /run/vault-t2-fs/gws_credentials

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

VAULT_CREDS="${VAULT_CREDS:-/run/vault-t2-fs/gws_credentials}"
NOTE_PATH="${NOTE_PATH:-$HOME/Nextcloud/Notes/0 Inbox/Gmail Morning Summary.md}"
AUDIT_LOG="${AUDIT_LOG:-/mnt/data/secrets/.audit.log}"

# ── Preflight checks ─────────────────────────────────────────────────────────

if [[ ! -f "$VAULT_CREDS" ]]; then
    echo "ERROR: vault-t2 credentials not found at $VAULT_CREDS" >&2
    echo "       Is vault-t2-fuse running? (systemctl status vault-t2-fuse)" >&2
    exit 1
fi

if ! command -v gws &>/dev/null; then
    echo "ERROR: gws CLI not found. Install with: npm install -g @googleworkspace/cli" >&2
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq not found. Install with: apt install jq" >&2
    exit 1
fi

NOTE_DIR="$(dirname "$NOTE_PATH")"
if [[ ! -d "$NOTE_DIR" ]]; then
    echo "ERROR: Note directory does not exist: $NOTE_DIR" >&2
    echo "       Is Nextcloud synced? Check: ls '$NOTE_DIR'" >&2
    exit 1
fi

# ── Credentials ───────────────────────────────────────────────────────────────

export GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE="$VAULT_CREDS"

# ── Helpers ───────────────────────────────────────────────────────────────────

audit() {
    local action="$1" details="$2"
    local ts; ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "{\"timestamp\":\"$ts\",\"action\":\"gmail-morning:$action\",\"details\":\"$details\",\"user\":\"$(whoami)\"}" \
        >> "$AUDIT_LOG" 2>/dev/null || true
}

# Returns resultSizeEstimate for a Gmail search query.
# Note: Gmail's estimate is approximate but accurate enough for a daily digest.
count_unread() {
    local query="$1"
    gws gmail users messages list \
        --params "{\"userId\":\"me\",\"maxResults\":1,\"q\":\"$query\"}" \
        2>/dev/null \
        | jq -r '.resultSizeEstimate // 0'
}

# ── Fetch counts ──────────────────────────────────────────────────────────────

echo "Fetching Gmail unread counts..."

TOTAL=$(count_unread "is:unread in:inbox")
PROMO=$(count_unread "is:unread in:inbox category:promotions")
UPDATES=$(count_unread "is:unread in:inbox category:updates")
SOCIAL=$(count_unread "is:unread in:inbox category:social")
FORUMS=$(count_unread "is:unread in:inbox category:forums")
PERSONAL=$(count_unread "is:unread in:inbox category:personal")

# "Primary" = inbox unread not in any named category tab
PRIMARY=$(( TOTAL - PROMO - UPDATES - SOCIAL - FORUMS - PERSONAL ))
# Guard against negative (estimate drift)
PRIMARY=$(( PRIMARY < 0 ? 0 : PRIMARY ))

audit "summary" "total=$TOTAL promo=$PROMO updates=$UPDATES social=$SOCIAL forums=$FORUMS personal=$PERSONAL"

# ── Write note ────────────────────────────────────────────────────────────────

DATE=$(date "+%Y-%m-%d")
TIME=$(date "+%H:%M")

cat > "$NOTE_PATH" <<EOF
---
generated: ${DATE}T${TIME}
type: gmail-summary
---

# Gmail — $DATE

> Unread counts as of $TIME (estimates)

| Category | Unread |
|---|---:|
| Primary | $PRIMARY |
| Promotions | $PROMO |
| Updates | $UPDATES |
| Social | $SOCIAL |
| Forums | $FORUMS |
| Personal | $PERSONAL |
| **Total** | **$TOTAL** |
EOF

echo "Note written to: $NOTE_PATH"
