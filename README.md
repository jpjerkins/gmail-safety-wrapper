# Gmail Safety Wrapper

Safe Gmail management via Google Workspace CLI with three-layer security: credential isolation, operation whitelisting, and content separation. Also includes a private MCP server for Claude Code integration.

## Components

- **`gmail-safe.sh`** — CLI wrapper for direct use and scripting
- **`mcp/`** — MCP server exposing the same safe operations as tools for Claude Code clients
- **`reader-prompt.md`** — Reader agent template for the dual-LLM pattern

## MCP Server

### Connecting a Claude Code client

Run once on any machine that can reach pi5:

```bash
# From laptop or other device:
claude mcp add --transport sse gmail --scope user http://thejerkins.duckdns.org:8004/sse

# On pi5 itself:
claude mcp add --transport sse gmail --scope user http://localhost:8004/sse
```

Verify: `claude mcp list` should show `gmail: ... ✓ Connected`.

### Available tools

| Tool | Description |
|---|---|
| `list_messages` | List messages (`max_results`, `query`) |
| `get_message` | Full message by ID |
| `get_message_summary` | Headers only (From/To/Subject/Date) — no body |
| `mark_read` | Mark a message as read |
| `mark_unread` | Mark a message as unread |
| `create_draft` | Create a draft (`to`, `subject`, `body`) |
| `send_message` | **Blocked** — create a draft, send via Gmail web UI |
| `delete_message` | **Blocked** |
| `trash_message` | **Blocked** |
| `modify_labels` | **Blocked** |

### Re-authenticating

Google revokes OAuth refresh tokens after ~7 days when the consent screen is in
*testing* mode. If the MCP server returns an authentication error:

**Step 1 — On your laptop** (browser required; `gws auth login` cannot run headlessly over SSH):

```bash
gws auth login -s gmail
gws auth export --unmasked > gws-creds-new.json
```

**Step 2 — Copy to pi5 and re-seal into vault-t2:**

```bash
# From laptop:
scp gws-creds-new.json philj@thejerkins.duckdns.org:/tmp/

# On pi5:
t2-set gws_credentials < /tmp/gws-creds-new.json
rm /tmp/gws-creds-new.json
```

No container restart needed — the vault-t2 FUSE mount decrypts on demand.

## gmail-safe.sh

### Quick Start

```bash
# List unread messages
./gmail-safe.sh --list 20 "is:unread"

# Get specific message
./gmail-safe.sh --get MESSAGE_ID

# Mark as read
./gmail-safe.sh --mark-read MESSAGE_ID

# Create draft
BASE64_MSG=$(base64 -w0 < email.txt)
./gmail-safe.sh --create-draft "$BASE64_MSG"
```

### Installation

1. **Google Workspace CLI:**
   ```bash
   npm install -g @googleworkspace/cli
   ```

2. **Tier 2 Vault** — `t2-get` must be available and `vault-t2-fuse` running.

3. **Dependencies:**
   ```bash
   sudo apt-get install jq
   ```

4. **Store credentials in vault:**
   ```bash
   # On laptop:
   gws auth login -s gmail
   gws auth export --unmasked > /tmp/gws-creds.json

   # On pi5:
   t2-set gws_credentials < /tmp/gws-creds.json
   rm /tmp/gws-creds.json
   ```

## Security model

| Scenario | Protected? | How |
|---|---|---|
| Accidental deletion | ✅ Yes | Delete blocked |
| Accidental sending | ✅ Yes | Send blocked; draft-only |
| Credential theft from disk | ✅ Yes | vault-t2 hardware-sealed encryption |
| Email content leak in AI conversation | ✅ Yes | Dual-LLM pattern isolates content |

- Credentials stored in vault-t2, never on disk in plaintext
- Operation whitelist enforced in both shell wrapper and MCP tools
- MCP port 8004 not exposed via Cloudflare — LAN/Tailscale only
- Audit logging for all operations

## AI-Assisted Usage (Dual-LLM Pattern)

For tasks involving email content analysis, use the dual-LLM pattern to prevent
email content from appearing in the orchestrator's context:

- **Reader Agent:** Sees email content, outputs structured JSON only
- **Orchestrator:** Makes decisions based on structure, never sees raw content

See `reader-prompt.md` for the reader agent template.

## Documentation

Full documentation in notes vault: `1 Projects/Gmail Management Skill/`
