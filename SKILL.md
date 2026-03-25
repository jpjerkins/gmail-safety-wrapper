---
name: managing-gmail-safely
description: Use when the user needs to read, triage, or manage Gmail messages via CLI, especially when working on pi5 where credentials must come from Tier 1 vault. Required for any Gmail operations to prevent accidental sending, deletion, or credential exposure.
---

# Managing Gmail Safely

## Overview

Safe Gmail access pattern using Google Workspace CLI with three-layer protection: credential isolation (Tier 1 vault), operation whitelisting (safety wrapper), and content separation (dual-LLM pattern).

**Core Principle:** Email operations are dangerous. Always use gmail-safe.sh wrapper + dual-LLM pattern, never raw gws commands.

## When to Use

Use this skill when:
- User asks to read, search, or manage Gmail messages
- Working on pi5 where credentials require Tier 1 vault
- Need to triage inbox, mark emails as read, or create drafts
- User mentions email, Gmail, or Google Workspace

**NEVER use raw `gws` commands directly. Always use the wrapper.**

## Quick Reference

### PowerShell (Laptop/Windows)

| Task | Command | Notes |
|------|---------|-------|
| List messages | `.\Gmail-Safe.ps1 -Action List -MaxResults 20 -Query "is:unread"` | Query optional |
| Get message | `.\Gmail-Safe.ps1 -Action Get -MessageId MESSAGE_ID` | Full content |
| Mark read | `.\Gmail-Safe.ps1 -Action MarkRead -MessageId MESSAGE_ID` | Safe operation |
| Create draft | `.\Gmail-Safe.ps1 -Action CreateDraft -RawMessage BASE64` | User sends via web |
| Triage inbox | Use dual-LLM pattern | See below |

### Bash (pi5/Linux)

| Task | Command | Notes |
|------|---------|-------|
| List messages | `./gmail-safe.sh --list 20 "is:unread"` | Max 50, query optional |
| Get message | `./gmail-safe.sh --get MESSAGE_ID` | Full content |
| Mark read | `./gmail-safe.sh --mark-read MESSAGE_ID` | Safe operation |
| Create draft | `./gmail-safe.sh --create-draft BASE64` | User sends via web |
| Triage inbox | Use dual-LLM pattern | See below |

## Dual-LLM Pattern (REQUIRED)

**For ANY task involving email content:**

```python
# 1. Spawn reader agent (sees email content)
reader_output = Task(
    subagent_type="general-purpose",
    description="Categorize emails",
    prompt=READ("C:/Local-only PARA/1 Projects/gmail-safety-wrapper/reader-prompt.md") +
           "\n\nTask: List and categorize unread emails from last 7 days"
)

# 2. Parse structured output (NO email content)
emails = json.loads(reader_output)

# 3. Make decisions without seeing content
for email in emails["emails"]:
    if email["category"] == "promotional" and email["urgency"] == "low":
        # Execute action
        Bash("./gmail-safe.sh --mark-read " + email["id"])
```

**Critical:** Reader agent outputs structured JSON only. Orchestrator (you) NEVER sees raw email content.

## Blocked Operations

These operations are **explicitly blocked** by gmail-safe.sh:

| Operation | Why Blocked |
|-----------|-------------|
| `--send` | No email sending without review. Create drafts instead. |
| `--delete` | Permanent deletion can't be undone. Use Gmail web UI. |
| `--trash` | Bulk trashing hides important messages. Use web UI. |
| `--modify-labels` | Label changes beyond read/unread disrupt organization. |

If user requests these, explain the block and suggest Gmail web UI.

## Credentials

### Laptop (PowerShell)

Gmail-Safe.ps1 uses gws CLI's native credential storage:
1. One-time OAuth: `gws auth login -s gmail`
2. Credentials encrypted in Windows OS keyring
3. No YubiKey required
4. Minimal scopes (gmail only)

### Pi5 (Bash with Vault)

gmail-safe.sh uses Tier 1 vault integration:
1. Calls `vault-expose gws_credentials --duration 15`
2. Sets `GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE`
3. Auto-cleanup after 15 minutes or script exit
4. **May require YubiKey tap** if session key expired

**Never** export credentials manually or store outside vault.

## Common Mistakes

### ❌ Using raw gws commands
```bash
# WRONG
gws gmail users messages list ...
```

### ❌ Single LLM seeing email content
```bash
# WRONG - don't read emails directly
content = Bash("./gmail-safe.sh --get MESSAGE_ID")
# Now you have email content in conversation!
```

### ❌ Reader agent outputs email subjects
```json
// WRONG - reader includes content
{"id": "123", "subject": "Q4 Budget Review"}
```

### ✅ Correct: Dual-LLM with structure only
```json
// CORRECT - generic classification only
{"id": "123", "category": "work", "urgency": "high", "reason": "Meeting request"}
```

## Rationalizations to Reject

| Excuse | Reality |
|--------|---------|
| "Just this once, I'll use gws directly" | Wrapper exists to prevent mistakes. Use it. |
| "User is admin, they want direct access" | Admin makes mistakes too. Use wrapper. |
| "Sending draft saves user time" | Unreviewed emails cause problems. Create draft. |
| "Single LLM is simpler" | Privacy matters. Use dual-LLM pattern. |

**All of these mean: Use the wrapper and dual-LLM pattern. No exceptions.**

## Implementation Files

All files located in: `C:/Local-only PARA/1 Projects/gmail-safety-wrapper/`

- `gmail-safe.sh` - Safety wrapper (use for all operations)
- `reader-prompt.md` - Reader agent template (for dual-LLM pattern)

Documentation in: `C:/Users/PhilJ/Nextcloud/Notes/1 Projects/Gmail Management Skill/`

## Example: Inbox Triage

```bash
# User request: "Clean up my promotional emails"

# Step 1: Spawn reader agent
reader_result = Task(
    subagent_type="general-purpose",
    description="Find promotional emails",
    prompt=READ("C:/Local-only PARA/1 Projects/gmail-safety-wrapper/reader-prompt.md") + """

    Task: List emails from last 30 days, categorize as promotional.
    Rate urgency for each.
    """
)

# Step 2: Parse structured output
emails = json.loads(reader_result)

# Step 3: Mark low-urgency promotional emails as read
count = 0
for email in emails["emails"]:
    if email["category"] == "promotional" and email["urgency"] == "low":
        Bash("cd 'C:/Local-only PARA/1 Projects/gmail-safety-wrapper' && ./gmail-safe.sh --mark-read " + email["id"])
        count += 1

# Step 4: Report to user
print(f"Marked {count} low-priority promotional emails as read.")
```

## Security Properties

✅ **Credentials:** Tier 1 vault (YubiKey required)
✅ **Operations:** Whitelisted (send/delete blocked)
✅ **Privacy:** Dual-LLM (no email content in conversation)
✅ **Audit:** All operations logged to vault audit trail
✅ **Auto-cleanup:** Credentials removed after session

## When NOT to Use

- Gmail web UI tasks (labels, filters, settings)
- Sending emails (create draft, user sends via web)
- Permanent deletion (user does manually in web UI)
- Non-Gmail Google Workspace operations (use appropriate tool)

## Testing Checklist

Before using with real emails:
- [ ] vault-expose works (YubiKey tap succeeds)
- [ ] gmail-safe.sh --list returns messages
- [ ] Reader agent outputs JSON (no email content)
- [ ] Orchestrator receives structured data only
- [ ] Blocked operations return clear error messages
- [ ] Credentials auto-cleanup after script exit