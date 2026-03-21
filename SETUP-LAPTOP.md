# Gmail Safety Wrapper - Laptop Setup Guide

Quick setup guide for using Gmail-Safe.ps1 on your Windows laptop with Claude Code.

## Prerequisites Check

```powershell
# 1. Check Node.js installed
node --version
# Should show v18+ or v20+

# 2. Check npm installed
npm --version
# Should show version number

# 3. Check PowerShell version
$PSVersionTable.PSVersion
# Should be 5.1 or higher
```

If Node.js/npm not installed:
```powershell
# Option 1: Download installer
# https://nodejs.org/

# Option 2: Via Chocolatey
choco install nodejs
```

## Installation Steps

### 1. Install Google Workspace CLI

```powershell
npm install -g @googleworkspace/cli
```

Verify installation:
```powershell
gws --version
# Should show version number
```

### 2. Authenticate with Gmail

```powershell
# Authenticate with minimal scopes (gmail only)
gws auth login -s gmail
```

**What happens:**
1. Browser opens for OAuth flow
2. Sign in with Google account
3. Grant permissions (gmail access only)
4. Browser shows "Authentication successful"
5. Credentials stored in `~/.config/gws/`

**IMPORTANT:** Use `-s gmail` flag to restrict to Gmail-only scopes. Without it, gws requests 85+ scopes (drive, calendar, contacts, etc.).

### 3. Verify Authentication

```powershell
# Test with simple list command
gws gmail users messages list --params '{"userId":"me","maxResults":1}'
```

Should return JSON with message data (or empty if no messages).

### 4. Test Gmail-Safe.ps1

```powershell
# Navigate to wrapper directory
cd "C:\Local-only PARA\1 Projects\gmail-safety-wrapper"

# Test list command
.\Gmail-Safe.ps1 -Action List -MaxResults 5
```

**Expected output:**
```
[INFO] Gmail Safety Wrapper - PowerShell Edition
[INFO] =========================================
[INFO]
[INFO] Listing up to 5 messages...
{
  "messages": [...]
}
[OK] Operation complete. Audit log: C:\Users\PhilJ\.gmail-safe\audit.log
```

### 5. Test Blocked Operation

```powershell
# Try to send (should be blocked)
.\Gmail-Safe.ps1 -Action Send
```

**Expected output:**
```
[ERROR] BLOCKED: send_message
[ERROR] Reason: Sending emails without review can cause professional embarrassment...
[ERROR]
[ERROR] This wrapper only allows safe read-only operations:
  ✓ List messages
  ✓ Get message content
  ✓ Mark as read/unread
  ✓ Create drafts
[ERROR]
[ERROR] For sending or deleting, use Gmail web interface.
```

## Quick Test Script

Save as `test-gmail-safe.ps1`:

```powershell
# Test Gmail-Safe.ps1 functionality

$wrapperPath = "C:\Local-only PARA\1 Projects\gmail-safety-wrapper\Gmail-Safe.ps1"

Write-Host "`n=== Testing Gmail-Safe.ps1 ===" -ForegroundColor Cyan

# Test 1: List messages
Write-Host "`nTest 1: List 3 messages" -ForegroundColor Yellow
& $wrapperPath -Action List -MaxResults 3

# Test 2: List unread
Write-Host "`nTest 2: List unread messages" -ForegroundColor Yellow
& $wrapperPath -Action List -MaxResults 5 -Query "is:unread"

# Test 3: Try blocked operation
Write-Host "`nTest 3: Try blocked operation (send)" -ForegroundColor Yellow
& $wrapperPath -Action Send 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "✓ Send operation correctly blocked" -ForegroundColor Green
}

# Test 4: Check audit log
Write-Host "`nTest 4: Check audit log" -ForegroundColor Yellow
$auditLog = "$env:USERPROFILE\.gmail-safe\audit.log"
if (Test-Path $auditLog) {
    Write-Host "✓ Audit log exists at: $auditLog" -ForegroundColor Green
    Write-Host "`nLast 3 entries:" -ForegroundColor Cyan
    Get-Content $auditLog | Select-Object -Last 3
} else {
    Write-Host "✗ Audit log not found" -ForegroundColor Red
}

Write-Host "`n=== Tests Complete ===" -ForegroundColor Cyan
```

Run with:
```powershell
.\test-gmail-safe.ps1
```

## Using with Claude Code

### Basic Usage

In Claude Code conversation:
```
You: "List my unread emails"

Claude will use:
.\Gmail-Safe.ps1 -Action List -MaxResults 50 -Query "is:unread"
```

### Dual-LLM Pattern (Privacy-Safe)

For tasks involving email content:
```
You: "Triage my inbox and mark promotional emails as read"

Claude will:
1. Spawn reader agent (sees email content)
2. Reader runs Gmail-Safe.ps1 to list/get emails
3. Reader outputs structured JSON only (NO email content)
4. Orchestrator (main Claude) receives JSON
5. Orchestrator makes decisions and executes actions
```

**Key:** Your conversation history will NOT contain email subjects, senders, or content. Only structured summaries.

## Troubleshooting

### "gws: command not found"

**Cause:** Google Workspace CLI not in PATH or not installed globally

**Solution:**
```powershell
# Reinstall globally
npm install -g @googleworkspace/cli

# Verify installation
where.exe gws
```

### "Not authenticated with Google Workspace CLI"

**Cause:** Authentication expired or never completed

**Solution:**
```powershell
# Re-authenticate
gws auth login -s gmail
```

### "Execution policy does not allow running scripts"

**Cause:** PowerShell execution policy too restrictive

**Solution:**
```powershell
# Check current policy
Get-ExecutionPolicy

# Set to RemoteSigned (allows local scripts)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Gmail-Safe.ps1 can't find gws

**Cause:** gws not in PATH for PowerShell session

**Solution:**
```powershell
# Restart PowerShell session
# Or add npm global bin to PATH:
$env:PATH += ";$env:APPDATA\npm"
```

## Next Steps

1. **Test basic operations** (see Quick Test Script above)

2. **Try with Claude Code:**
   ```
   "List my 10 most recent emails"
   ```

3. **Test dual-LLM pattern:**
   ```
   "Categorize my unread emails by urgency"
   ```
   Verify NO email content in conversation output.

4. **Review audit log:**
   ```powershell
   Get-Content "$env:USERPROFILE\.gmail-safe\audit.log" | ConvertFrom-Json | Format-Table
   ```

## Security Notes

- ✅ Credentials encrypted in Windows OS keyring
- ✅ Minimal OAuth scopes (gmail only)
- ✅ Operation whitelisting (no send/delete)
- ✅ Dual-LLM pattern prevents email content leaks
- ✅ Audit logging for all operations
- ⚠️ Not YubiKey-protected (use pi5 version for that)

## Files Created During Setup

```
~/.config/gws/                    # gws CLI config directory
├── credentials.json              # Encrypted OAuth credentials
└── .encryption_key               # Encryption key (OS keyring)

~/.gmail-safe/                    # Audit log directory
└── audit.log                     # Operation audit trail
```

## Uninstall (if needed)

```powershell
# Remove gws CLI
npm uninstall -g @googleworkspace/cli

# Remove credentials
Remove-Item -Recurse -Force "$env:USERPROFILE\.config\gws"

# Remove audit logs
Remove-Item -Recurse -Force "$env:USERPROFILE\.gmail-safe"
```

## Resources

- **Documentation:** `C:\Users\PhilJ\Nextcloud\Notes\1 Projects\Gmail Management Skill\`
- **README:** `C:\Local-only PARA\1 Projects\gmail-safety-wrapper\README-LAPTOP.md`
- **Skill:** `C:\Users\PhilJ\.claude\skills\managing-gmail-safely\SKILL.md`
- **Google Workspace CLI:** https://github.com/googleworkspace/cli

---

**Setup complete!** You can now use Gmail-Safe.ps1 with Claude Code for safe email management.
