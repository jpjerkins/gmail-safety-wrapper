# Gmail Safety Wrapper - Laptop Edition (PowerShell)

Windows PowerShell wrapper for safe Gmail management via Google Workspace CLI. Simplified version for laptop use without vault integration.

## Quick Start

```powershell
# List recent messages
.\Gmail-Safe.ps1 -Action List -MaxResults 20

# List unread messages
.\Gmail-Safe.ps1 -Action List -MaxResults 50 -Query "is:unread"

# Get specific message
.\Gmail-Safe.ps1 -Action Get -MessageId "18d4c2f8a1b2c3d4"

# Mark as read
.\Gmail-Safe.ps1 -Action MarkRead -MessageId "18d4c2f8a1b2c3d4"

# Create draft
$content = Get-Content email.txt -Raw
$base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))
.\Gmail-Safe.ps1 -Action CreateDraft -RawMessage $base64
```

## What This Does

**Allows (Safe Operations):**
- ✅ List messages
- ✅ Get message content
- ✅ Mark as read/unread
- ✅ Create drafts

**Blocks (Dangerous Operations):**
- ❌ Send emails → Create draft instead, send via Gmail web UI
- ❌ Delete permanently → Use Gmail web UI for deletion
- ❌ Trash messages → Prevents accidental bulk archiving
- ❌ Modify labels → Use Gmail web UI for label management

## Installation

### Prerequisites

1. **Node.js and npm** (for Google Workspace CLI)
   - Download from: https://nodejs.org/
   - Or via Chocolatey: `choco install nodejs`

2. **Google Workspace CLI**
   ```powershell
   npm install -g @googleworkspace/cli
   ```

3. **PowerShell 5.1+** (included in Windows 10/11)

### Setup

1. **Authenticate with Google Workspace CLI:**
   ```powershell
   # Use minimal scopes (gmail only)
   gws auth login -s gmail
   ```
   Browser will open for OAuth flow. Complete authentication.

2. **Verify authentication:**
   ```powershell
   gws gmail users messages list --params '{"userId":"me","maxResults":1}'
   ```
   Should return a message (or empty list if inbox empty).

3. **Download Gmail-Safe.ps1:**
   Already at: `C:\Local-only PARA\1 Projects\gmail-safety-wrapper\Gmail-Safe.ps1`

4. **Test the wrapper:**
   ```powershell
   cd "C:\Local-only PARA\1 Projects\gmail-safety-wrapper"
   .\Gmail-Safe.ps1 -Action List -MaxResults 5
   ```

## Usage Examples

### List Messages

```powershell
# List 10 most recent messages (default)
.\Gmail-Safe.ps1 -Action List

# List 20 messages
.\Gmail-Safe.ps1 -Action List -MaxResults 20

# List unread messages
.\Gmail-Safe.ps1 -Action List -MaxResults 50 -Query "is:unread"

# List messages from specific sender
.\Gmail-Safe.ps1 -Action List -MaxResults 50 -Query "from:sender@example.com"

# List messages with label
.\Gmail-Safe.ps1 -Action List -Query "label:important"
```

### Get Message Content

```powershell
# Get full message by ID
.\Gmail-Safe.ps1 -Action Get -MessageId "18d4c2f8a1b2c3d4"

# Get message and parse with PowerShell
$msg = .\Gmail-Safe.ps1 -Action Get -MessageId "18d4c2f8a1b2c3d4" | ConvertFrom-Json
$msg.snippet
```

### Mark as Read/Unread

```powershell
# Mark as read
.\Gmail-Safe.ps1 -Action MarkRead -MessageId "18d4c2f8a1b2c3d4"

# Mark as unread
.\Gmail-Safe.ps1 -Action MarkUnread -MessageId "18d4c2f8a1b2c3d4"
```

### Create Draft

```powershell
# Create email file
@"
From: me@example.com
To: recipient@example.com
Subject: Test Draft

This is a test draft message.
"@ | Out-File -FilePath email.txt -Encoding UTF8

# Encode to base64
$content = Get-Content email.txt -Raw
$base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))

# Create draft
.\Gmail-Safe.ps1 -Action CreateDraft -RawMessage $base64

# Review and send via Gmail web UI
```

### Blocked Operations

```powershell
# Try to send (blocked)
.\Gmail-Safe.ps1 -Action Send
# Output:
# [ERROR] BLOCKED: send_message
# [ERROR] Reason: Sending emails without review can cause professional embarrassment...
```

## AI-Assisted Usage (Dual-LLM Pattern)

For Claude Code tasks involving email content analysis:

### Example: Triage Inbox

```powershell
# In Claude Code conversation:
# "Use the dual-LLM pattern to triage my unread emails"

# Claude will:
# 1. Spawn reader agent (sees email content)
# 2. Reader uses Gmail-Safe.ps1 to list and categorize emails
# 3. Reader outputs structured JSON only (NO email subjects/content)
# 4. Orchestrator receives JSON, makes decisions
# 5. Orchestrator uses Gmail-Safe.ps1 to execute actions
```

**Reader agent will use:**
```powershell
.\Gmail-Safe.ps1 -Action List -MaxResults 50 -Query "is:unread"
.\Gmail-Safe.ps1 -Action Get -MessageId "MESSAGE_ID"
```

**Orchestrator will use:**
```powershell
.\Gmail-Safe.ps1 -Action MarkRead -MessageId "MESSAGE_ID"
.\Gmail-Safe.ps1 -Action CreateDraft -RawMessage $base64
```

**Critical:** Reader agent outputs structured JSON only. Never includes email subjects, body, or sender details.

## Configuration

### Audit Log

All operations are logged to: `$env:USERPROFILE\.gmail-safe\audit.log`

Example log entry:
```json
{"timestamp":"2026-03-20T14:30:00Z","action":"gmail-safe:list_messages","details":"max_results=20, query=is:unread","user":"PhilJ","success":true}
```

### Gmail Search Queries

Common query patterns:
- `is:unread` - Unread messages
- `is:read` - Read messages
- `from:sender@example.com` - From specific sender
- `to:recipient@example.com` - To specific recipient
- `subject:keyword` - Subject contains keyword
- `label:important` - Has specific label
- `newer_than:7d` - From last 7 days
- `older_than:30d` - Older than 30 days

Combine with AND/OR:
- `is:unread from:boss@company.com`
- `is:unread newer_than:7d`

## Security Model

### Credential Storage

- ✅ Credentials stored in gws CLI's encrypted config
- ✅ Uses Windows OS keyring for encryption
- ⚠️ Not YubiKey-protected (simpler than pi5 vault approach)
- ✅ Minimal OAuth scopes (gmail only)

### Operation Whitelisting

- ✅ Only safe operations allowed
- ✅ Dangerous operations explicitly blocked with clear errors
- ✅ Audit logging for all operations

### Privacy (Dual-LLM Pattern)

- ✅ Email content isolated to reader agent
- ✅ Orchestrator conversation history privacy-safe
- ✅ Structured data only in main conversation

### Threat Model

| Attacker Scenario | Protected? | How |
|-------------------|------------|-----|
| Accidental deletion | ✅ Yes | Delete operation blocked |
| Accidental sending | ✅ Yes | Send operation blocked, draft-only |
| Email content leak in AI | ✅ Yes | Dual-LLM pattern isolates content |
| Credential theft (laptop offline) | ✅ Yes | OS keyring encryption |
| Credential theft (laptop running) | ⚠️ Partial | Admin access can read keyring |

## Troubleshooting

### "gws is not installed"

**Cause:** Google Workspace CLI not installed

**Solution:**
```powershell
npm install -g @googleworkspace/cli
```

### "Not authenticated with Google Workspace CLI"

**Cause:** OAuth not completed or expired

**Solution:**
```powershell
gws auth login -s gmail
```

### "Message ID is required"

**Cause:** Forgot to provide -MessageId parameter

**Solution:**
```powershell
# Get message ID from list first
.\Gmail-Safe.ps1 -Action List -MaxResults 5
# Then use the ID
.\Gmail-Safe.ps1 -Action Get -MessageId "ACTUAL_ID_HERE"
```

### "BLOCKED: send_message"

**Cause:** Attempted to send email (blocked by design)

**Solution:** This is expected. Create draft instead:
```powershell
.\Gmail-Safe.ps1 -Action CreateDraft -RawMessage $base64
```
Then send via Gmail web UI after reviewing.

## Differences from Pi5 Version

| Feature | Pi5 Version (bash) | Laptop Version (PowerShell) |
|---------|-------------------|----------------------------|
| **Credential Storage** | Tier 1 vault (YubiKey) | gws native (OS keyring) |
| **Authentication** | YubiKey TOTP | OAuth via browser |
| **Platform** | Linux (pi5) | Windows (laptop) |
| **Vault Integration** | Yes (vault-expose) | No |
| **Auto-Cleanup** | Yes (timer-based) | No (gws manages) |
| **Operation Whitelisting** | ✅ Same | ✅ Same |
| **Dual-LLM Pattern** | ✅ Same | ✅ Same |
| **Use Case** | Attended ops on pi5 | Attended ops on laptop |

## Files

```
gmail-safety-wrapper/
├── README-LAPTOP.md           # This file
├── Gmail-Safe.ps1             # PowerShell wrapper
├── reader-prompt.md           # Reader agent template
├── gmail-safe.sh              # Bash version (for pi5)
└── README.md                  # Original bash version docs
```

## Documentation

Full documentation in: `C:\Users\PhilJ\Nextcloud\Notes\1 Projects\Gmail Management Skill\`

- **Project Index.md** - Project overview
- **Dual-LLM Pattern Design.md** - Content separation architecture
- **Testing Plan.md** - Test strategy

## Claude Code Integration

### Using with Claude Code Skill

The managing-gmail-safely skill is at:
`C:\Users\PhilJ\.claude\skills\managing-gmail-safely\SKILL.md`

When you ask Claude Code to manage Gmail:
1. Skill activates automatically
2. Uses dual-LLM pattern
3. Spawns reader agent (sees email content)
4. Reader outputs structured JSON only
5. Orchestrator (main Claude) makes decisions
6. Actions executed via Gmail-Safe.ps1

### Example Session

```
You: "Triage my unread emails"

Claude:
- Spawns reader agent
- Reader runs: .\Gmail-Safe.ps1 -Action List -Query "is:unread"
- Reader categorizes emails (internal reasoning)
- Reader outputs JSON: {category, urgency, reason}
- Claude receives JSON (NO email content)
- Claude decides actions based on structure
- Claude runs: .\Gmail-Safe.ps1 -Action MarkRead -MessageId "..."
- Reports: "Marked 15 promotional emails as read"
```

## Testing Status

### Confirmed Working (tested 2026-03-25)
- ✅ `List` without query
- ✅ `List` with spaced query (e.g., `"is:unread in:inbox"`) — was previously the failing case
- ✅ `Get` by message ID
- ✅ `MarkRead` — removes `UNREAD` label correctly
- ✅ `MarkUnread` — restores `UNREAD` label correctly
- ✅ Blocked operations (`Send`, `Delete`) — show correct error messages and log to audit trail
- ✅ Audit log — all operations recorded correctly

### Known Minor Issue
The `✓` checkmark characters in blocked-operation output render as garbage (`?o`) in some terminals. Cosmetic only — no functional impact.

- ✅ `CreateDraft` — draft created successfully, appears in Gmail with `DRAFT` label

### Still Needs Testing
- **Reader agent / dual-LLM pattern** — end-to-end test with Claude Code:
  - Ask Claude Code to triage emails
  - Verify NO email content appears in the conversation
  - Only structured data (category, urgency) should be visible

## Related

- Google Workspace CLI: https://github.com/googleworkspace/cli
- Claude Skills: `C:\Users\PhilJ\.claude\skills\managing-gmail-safely\`
- Project Docs: `C:\Users\PhilJ\Nextcloud\Notes\1 Projects\Gmail Management Skill\`

## License

Personal use only. Not for redistribution.
