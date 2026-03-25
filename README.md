# Gmail Safety Wrapper

Safe Gmail management via Google Workspace CLI with three-layer security: credential isolation, operation whitelisting, and content separation.

## Quick Start

```bash
# 1. List unread messages
./gmail-safe.sh --list 20 "is:unread"

# 2. Get specific message
./gmail-safe.sh --get MESSAGE_ID

# 3. Mark as read
./gmail-safe.sh --mark-read MESSAGE_ID

# 4. Create draft
BASE64_MSG=$(base64 -w0 < email.txt)
./gmail-safe.sh --create-draft "$BASE64_MSG"
```

## What This Does

**Allows (Safe Operations):**
- ✅ List messages
- ✅ Get message content
- ✅ Mark as read/unread
- ✅ Create drafts

**Blocks (Dangerous Operations):**
- ❌ Send emails (create draft instead, send via Gmail web UI)
- ❌ Delete permanently (use Gmail web UI for deletion)
- ❌ Trash messages (prevents accidental bulk archiving)
- ❌ Modify labels beyond read/unread (use Gmail web UI)

## Security Features

### 1. Credential Isolation (Tier 2 Vault)

Credentials stored in Tier 2 vault, sealed against the Pi's hardware fingerprint:

```bash
# gmail-safe.sh automatically:
# - Calls t2-get gws_credentials (no YubiKey required at runtime)
# - Writes to /dev/shm (memory-only tmpfs)
# - Sets GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE
# - Cleans up on script exit
```

**Never** manually export credentials or store outside vault.

### 2. Operation Whitelisting

Only safe read-only operations allowed. Dangerous operations return clear error messages:

```bash
$ ./gmail-safe.sh --send
[ERROR] BLOCKED: send_message
[ERROR] Reason: Sending emails without review can cause professional embarrassment.
[ERROR]         Create a draft instead, then send via Gmail web UI after reviewing.
```

### 3. Content Separation (Dual-LLM Pattern)

For AI-assisted email management, use dual-LLM pattern:

- **Reader Agent:** Sees email content, outputs structured data only
- **Orchestrator:** Makes decisions, never sees raw email content

See `reader-prompt.md` for reader agent template.

## Installation

### Prerequisites

1. **Google Workspace CLI:**
   ```bash
   npm install -g @googleworkspace/cli
   ```

2. **Tier 2 Vault:**
   - `t2-get` command must be available (from pi-vault)
   - Tier 2 must be provisioned and `vault-t2-fuse` service running
   - See: `~/dev/pi-vault/pi5/vault-t2/docs/install.md`

3. **Dependencies:**
   ```bash
   sudo apt-get install jq  # JSON processor
   ```

### Setup

1. **Authenticate Google Workspace CLI:**
   ```bash
   # Use minimal scopes (gmail only)
   gws auth login -s gmail
   ```

2. **Store credentials in vault:**
   ```bash
   # On laptop: export credentials (gws auth login must have been run first)
   gws auth export --unmasked > /tmp/gws-creds.json

   # On pi5: store in Tier 1, then copy to Tier 2
   cat /tmp/gws-creds.json | vault-set gws_credentials
   rm /tmp/gws-creds.json
   vault-get gws_credentials | t2-set gws_credentials
   ```

3. **Make wrapper executable:**
   ```bash
   chmod +x gmail-safe.sh
   ```

4. **Test:**
   ```bash
   ./gmail-safe.sh --list 5
   # Should list your 5 most recent messages
   ```

## Usage Examples

### List Messages

```bash
# List 10 most recent messages
./gmail-safe.sh --list 10

# List unread messages
./gmail-safe.sh --list 20 "is:unread"

# List messages from specific sender
./gmail-safe.sh --list 50 "from:sender@example.com"
```

### Get Message Content

```bash
# Get full message by ID
./gmail-safe.sh --get 18d4c2f8a1b2c3d4

# Parse with jq
./gmail-safe.sh --get 18d4c2f8a1b2c3d4 | jq '.snippet'
```

### Mark as Read/Unread

```bash
# Mark as read
./gmail-safe.sh --mark-read 18d4c2f8a1b2c3d4

# Mark as unread
./gmail-safe.sh --mark-unread 18d4c2f8a1b2c3d4
```

### Create Draft

```bash
# Create email file
cat > email.txt <<EOF
From: me@example.com
To: recipient@example.com
Subject: Test Draft

This is a test draft message.
EOF

# Encode to base64
BASE64_MSG=$(base64 -w0 < email.txt)

# Create draft
./gmail-safe.sh --create-draft "$BASE64_MSG"

# Review and send via Gmail web UI
```

## AI-Assisted Usage (Dual-LLM Pattern)

For tasks involving email content analysis:

```python
# Example: Triage inbox

# 1. Spawn reader agent to categorize emails
reader_output = Task(
    subagent_type="general-purpose",
    description="Categorize emails",
    prompt=READ("reader-prompt.md") + """

    Task: List unread emails from last 7 days.
    Categorize by: work, personal, promotional, newsletter.
    Rate urgency: high, medium, low.
    """
)

# 2. Parse structured output (NO email content)
emails = json.loads(reader_output)

# 3. Make decisions based on structure
for email in emails["emails"]:
    if email["category"] == "promotional" and email["urgency"] == "low":
        # Mark as read
        Bash("./gmail-safe.sh --mark-read " + email["id"])
```

**Critical:** Reader agent must output structured JSON only. Never include email subjects, body, or sender details in output.

## Configuration

Environment variables (optional):

```bash
# Vault secret name (default: gws_credentials)
export VAULT_SECRET_NAME=gws_credentials

# Credential duration in minutes (default: 15)
export CREDENTIAL_DURATION=30

# Audit log path (default: /mnt/data/secrets/.audit.log)
export AUDIT_LOG=/path/to/audit.log
```

## Security Model

### Threat Model

| Attacker Scenario | Protected? | How |
|-------------------|------------|-----|
| Accidental deletion | ✅ Yes | Delete operation blocked |
| Accidental sending | ✅ Yes | Send operation blocked, draft-only |
| Credential theft from disk | ✅ Yes | Tier 1 vault encryption + YubiKey |
| Root access to pi5 (running) | ⚠️ Partial | Credentials in /dev/shm only during script execution |
| Email content leak in AI conversation | ✅ Yes | Dual-LLM pattern isolates content |

### Security Properties

- ✅ Credentials encrypted at rest (Tier 1 vault)
- ✅ YubiKey TOTP required for access
- ✅ Credentials in memory-backed tmpfs only (no disk)
- ✅ Auto-cleanup after 15 minutes or script exit
- ✅ Operation whitelist prevents destructive actions
- ✅ Audit logging for all operations
- ✅ Dual-LLM pattern prevents content exposure

## Troubleshooting

### "Failed to expose credentials from vault"

**Cause:** vault-expose command failed (YubiKey not tapped, vault not setup)

**Solution:**
1. Ensure YubiKey is plugged in and auth proxy running on laptop
2. Check vault-expose works: `vault-expose test_secret`
3. Verify gws_credentials exists in vault: `vault-list`

### "Missing required dependencies: jq"

**Cause:** jq (JSON processor) not installed

**Solution:**
```bash
sudo apt-get install jq
```

### "BLOCKED: send_message"

**Cause:** Attempted to send email (blocked operation)

**Solution:** This is expected. Create draft instead:
```bash
./gmail-safe.sh --create-draft "BASE64_MESSAGE"
```
Then send via Gmail web UI after reviewing.

### "ERROR: Unknown command"

**Cause:** Unsupported operation or typo

**Solution:** Run `./gmail-safe.sh --help` to see available commands

## Files

```
gmail-safety-wrapper/
├── README.md              # This file
├── gmail-safe.sh          # Main wrapper script
└── reader-prompt.md       # Reader agent template for dual-LLM pattern
```

## Documentation

Full documentation in: `C:/Users/PhilJ/Nextcloud/Notes/1 Projects/Gmail Management Skill/`

- **Tier 1 Temporary Filesystem Design.md** - vault-expose implementation
- **Dual-LLM Pattern Design.md** - Content separation architecture
- **Baseline Risk Assessment.md** - Security analysis and threat model

## Contributing

This is a personal project for pi5 home infrastructure. For bugs or improvements, update files directly and test thoroughly before use.

## License

Personal use only. Not for redistribution.

## Related

- Google Workspace CLI: https://github.com/googleworkspace/cli
- Tier 1 Vault Documentation: `C:/Users/PhilJ/Nextcloud/Notes/1 Projects/Pi5 Vault/`
- Claude Skills: `C:/Users/PhilJ/.claude/skills/managing-gmail-safely/`
