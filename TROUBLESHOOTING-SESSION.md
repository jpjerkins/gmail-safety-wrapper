# Gmail-Safe.ps1 Troubleshooting Session - 2026-03-20

## Goal
Get Gmail-Safe.ps1 PowerShell wrapper working to safely manage Gmail via Google Workspace CLI (gws).

## Current Status
Script partially working, but has intermittent authentication and JSON parameter issues.

## What Worked

### Initial Success
```powershell
.\Gmail-Safe.ps1 -Action List -MaxResults 5
```
This successfully listed 5 messages on first attempt after fixing the audit log timestamp issue (PowerShell 5.1 doesn't have `-AsUTC` parameter).

**Working approach:**
- Convert PowerShell hashtable to JSON: `ConvertTo-Json -Compress`
- Pass JSON directly to gws: `gws gmail users messages list --params $json`
- PowerShell's default behavior somehow makes this work WITHOUT manual escaping

## What Didn't Work

### JSON Escaping Attempts (All Failed)
1. **Backtick escaping:** `"{`"userId`":`"me`"}"`
   - Error: "Invalid --params JSON: key must be a string at line 1 column 2"

2. **Backslash escaping:** `"{\"userId\":\"me\"}"`
   - Error: PowerShell escapes the backslashes themselves, creating `\:\` in output

3. **Custom ConvertTo-GwsJson function with escaping**
   - Various escape attempts all broke the working behavior

4. **Invoke-Expression approach**
   - Error: "unexpected argument 'userId\\:\\me\\,\\maxResults\\:5}'"

5. **Git Bash wrapper:** `bash -c 'gws gmail users messages list...'`
   - Error: Still got JSON parsing errors

6. **CMD wrapper:** `cmd /c "gws..."`
   - Error: Backslash escaping issues

### Queries with Spaces
```powershell
.\Gmail-Safe.ps1 -Action List -Query "is:unread in:inbox"
```
Failed with various JSON parsing errors. Space-less queries might work but not tested.

## Current Problem — RESOLVED (2026-03-21)

### Root Cause: PowerShell 5.1 Argument Passing Bug

Both the authentication check failure and the query-with-spaces failure had the **same root cause**: PowerShell 5.1 strips double quotes from strings when passing them as arguments to native commands. So `{"userId":"me"}` arrived at `gws` as `{userId:me}`, causing "key must be a string" JSON parse errors.

The auth check (`Test-GwsAuthenticated`) ran a test `gws` command with JSON params — that command failed due to the quote-stripping, and the script misinterpreted it as an authentication failure.

### Fix: Bypass PowerShell Argument Passing

Added `Invoke-Gws` function that uses `System.Diagnostics.Process` to call `node.exe` directly with a properly escaped argument string, bypassing PowerShell's broken native command argument handling entirely. Internal `"` characters are escaped as `\"` for the Windows C runtime parser.

### Previous (Incorrect) Hypothesis
~~gws is using corrupted or stale credentials from previous project.~~
Credentials were fine — the JSON parse error from the mangled params was misdiagnosed as an auth failure.

## Next Steps to Try

### 1. Complete Credential Reset
```powershell
# Clear all gws credentials
Remove-Item -Recurse -Force "$env:USERPROFILE\.config\gws" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\gws" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:APPDATA\gws" -ErrorAction SilentlyContinue

# Re-authenticate fresh
gws auth login -s gmail

# Test
gws auth status
.\Gmail-Safe.ps1 -Action List -MaxResults 5
```

### 2. If Step 1 Works, Test Queries
```powershell
# Without spaces
.\Gmail-Safe.ps1 -Action List -MaxResults 10 -Query "is:unread"

# With spaces (may require different approach)
.\Gmail-Safe.ps1 -Action List -MaxResults 10 -Query "is:unread in:inbox"
```

### 3. If Queries Fail, Alternative Approaches
- Check if gws supports alternative query syntax
- Use multiple separate filters instead of space-separated query
- Accept limitation: no spaces in queries from PowerShell
- Consider wrapper that uses WSL/Git Bash ONLY for queries with spaces

## Technical Notes

### PowerShell -> External Command JSON Passing
PowerShell has notoriously difficult quoting behavior when passing JSON to external commands:
- Single quotes `'...'` are sometimes processed by PowerShell
- Double quotes `"..."` require escaping but escaping methods vary
- Variables containing JSON: `$json = '...'` then `gws --params $json` is simplest
- **Key insight:** Don't try to escape - let PowerShell's default behavior work

### gws CLI Credential Storage
- Uses Windows keyring (not plaintext JSON file)
- Config location varies: `~/.config/gws/` or AppData locations
- Message "Using keyring backend: keyring" confirms this
- Credentials from previous OAuth flows may persist and conflict

### File Locations
- Script: `C:\Local-only PARA\1 Projects\gmail-safety-wrapper\Gmail-Safe.ps1`
- Audit log: `$env:USERPROFILE\.gmail-safe\audit.log`
- Documentation: `C:\Users\PhilJ\Nextcloud\Notes\1 Projects\Gmail Management Skill\`
- Skill: `C:\Users\PhilJ\.claude\skills\managing-gmail-safely\SKILL.md`

## Recommended Approach for Fresh Start

1. **Complete credential wipe** (see step 1 above)
2. **Test script with simple list** (no query)
3. **If working, test without spaces in query**
4. **If that works, consider query limitation acceptable**
5. **Document limitation in README-LAPTOP.md**
6. **Alternative:** Create separate bash-only version for complex queries

## Success Criteria

**Minimum:**
- List messages (no query) works reliably
- Get message by ID works
- Mark as read/unread works
- Simple queries (no spaces) work

**Nice to have:**
- Queries with spaces work
- All operations work through wrapper

**Acceptable limitation:**
- For complex queries with spaces, user runs raw gws command manually
- Most use cases (list recent, mark read, etc.) don't need complex queries

## Session Notes

User (Phil) and Claude both tired - good time for session reset. This doc provides continuity for next session.

**Key takeaway:** The simple approach (`ConvertTo-Json -Compress` + direct pass) worked initially. Don't over-engineer the escaping. Focus on credential issue first.

---

**Last updated:** 2026-03-21
**Status:** RESOLVED — both issues fixed by Invoke-Gws process bypass
