#Requires -Version 5.1
<#
.SYNOPSIS
    Safety wrapper for Google Workspace CLI - Gmail operations only

.DESCRIPTION
    Provides read-only Gmail access with safeguards against accidental
    deletion, sending, or destructive operations.

    Allowed operations:
      - List messages
      - Get message content
      - Mark messages as read/unread
      - Create drafts

    Blocked operations (with clear error messages):
      - Send messages (use Gmail web UI to review and send drafts)
      - Delete messages permanently
      - Trash messages (prevents accidental bulk archiving)
      - Modify labels (except UNREAD flag)

.PARAMETER Action
    The action to perform: List, Get, MarkRead, MarkUnread, CreateDraft

.PARAMETER MessageId
    The Gmail message ID (required for Get, MarkRead, MarkUnread)

.PARAMETER MaxResults
    Maximum number of messages to list (default: 10)

.PARAMETER Query
    Gmail search query for filtering messages

.PARAMETER RawMessage
    Base64-encoded email message for creating drafts

.EXAMPLE
    .\Gmail-Safe.ps1 -Action List -MaxResults 20

.EXAMPLE
    .\Gmail-Safe.ps1 -Action List -MaxResults 50 -Query "is:unread"

.EXAMPLE
    .\Gmail-Safe.ps1 -Action Get -MessageId "18d4c2f8a1b2c3d4"

.EXAMPLE
    .\Gmail-Safe.ps1 -Action MarkRead -MessageId "18d4c2f8a1b2c3d4"

.EXAMPLE
    $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-Content email.txt -Raw)))
    .\Gmail-Safe.ps1 -Action CreateDraft -RawMessage $base64

.NOTES
    Security:
      - Uses gws CLI's native encrypted credential storage
      - Operation whitelist prevents destructive actions
      - All operations logged to audit trail
      - Dangerous operations explicitly blocked

    Dependencies:
      - Google Workspace CLI (gws) must be installed
      - Must be authenticated: gws auth login -s gmail
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet('List', 'Get', 'MarkRead', 'MarkUnread', 'CreateDraft',
                 'Send', 'Delete', 'Trash', 'ModifyLabels', 'Help')]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [string]$MessageId,

    [Parameter(Mandatory=$false)]
    [int]$MaxResults = 10,

    [Parameter(Mandatory=$false)]
    [string]$Query,

    [Parameter(Mandatory=$false)]
    [string]$RawMessage
)

# Configuration
$AuditLogPath = "$env:USERPROFILE\.gmail-safe\audit.log"

# Ensure audit log directory exists
$auditDir = Split-Path -Parent $AuditLogPath
if (-not (Test-Path $auditDir)) {
    New-Item -ItemType Directory -Path $auditDir -Force | Out-Null
}

# Helper Functions

function Write-ColorOutput {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Warn', 'Error', 'Success')]
        [string]$Type = 'Info'
    )

    $colors = @{
        'Info' = 'Cyan'
        'Warn' = 'Yellow'
        'Error' = 'Red'
        'Success' = 'Green'
    }

    $prefix = switch ($Type) {
        'Info' { '[INFO]' }
        'Warn' { '[WARN]' }
        'Error' { '[ERROR]' }
        'Success' { '[OK]' }
    }

    Write-Host "$prefix " -ForegroundColor $colors[$Type] -NoNewline
    Write-Host $Message
}

function Write-AuditLog {
    param(
        [string]$Action,
        [string]$Details,
        [bool]$Success = $true
    )

    # Get UTC timestamp (PowerShell 5.1 compatible)
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $username = $env:USERNAME

    $entry = @{
        timestamp = $timestamp
        action = "gmail-safe:$Action"
        details = $Details
        user = $username
        success = $Success
    } | ConvertTo-Json -Compress

    Add-Content -Path $AuditLogPath -Value $entry
}

function Test-GwsInstalled {
    $gws = Get-Command gws -ErrorAction SilentlyContinue
    if (-not $gws) {
        Write-ColorOutput "Google Workspace CLI (gws) is not installed." -Type Error
        Write-ColorOutput "" -Type Error
        Write-ColorOutput "Install with: npm install -g @googleworkspace/cli" -Type Error
        Write-ColorOutput "Then authenticate: gws auth login -s gmail" -Type Error
        exit 1
    }
}

function Test-GwsAuthenticated {
    # Try a simple command to check authentication
    $testParams = @{
        userId = "me"
        maxResults = 1
    } | ConvertTo-Json -Compress

    $testResult = gws gmail users messages list --params $testParams 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-ColorOutput "Not authenticated with Google Workspace CLI." -Type Error
        Write-ColorOutput "" -Type Error
        Write-ColorOutput "Authenticate with: gws auth login -s gmail" -Type Error
        Write-ColorOutput "Use minimal scopes (gmail only) for security." -Type Error
        exit 1
    }
}

function Invoke-BlockedOperation {
    param(
        [string]$Operation,
        [string]$Reason
    )

    Write-ColorOutput "BLOCKED: $Operation" -Type Error
    Write-ColorOutput "Reason: $Reason" -Type Error
    Write-ColorOutput "" -Type Error
    Write-ColorOutput "This wrapper only allows safe read-only operations:" -Type Error
    Write-ColorOutput "  ✓ List messages" -Type Success
    Write-ColorOutput "  ✓ Get message content" -Type Success
    Write-ColorOutput "  ✓ Mark as read/unread" -Type Success
    Write-ColorOutput "  ✓ Create drafts" -Type Success
    Write-ColorOutput "" -Type Error
    Write-ColorOutput "For sending or deleting, use Gmail web interface." -Type Error

    Write-AuditLog -Action "blocked" -Details "$Operation : $Reason" -Success $false
    exit 1
}

# Safe Operations

function Invoke-ListMessages {
    param(
        [int]$MaxResults,
        [string]$Query
    )

    Write-ColorOutput "Listing up to $MaxResults messages..." -Type Info

    $params = @{
        userId = "me"
        maxResults = $MaxResults
    }

    if ($Query) {
        $params.q = $Query
    }

    $paramsJson = $params | ConvertTo-Json -Compress

    Write-AuditLog -Action "list_messages" -Details "max_results=$MaxResults, query=$Query"

    gws gmail users messages list --params $paramsJson
}

function Invoke-GetMessage {
    param(
        [string]$MessageId
    )

    if (-not $MessageId) {
        Write-ColorOutput "Message ID is required for Get action." -Type Error
        exit 1
    }

    Write-ColorOutput "Fetching message: $MessageId" -Type Info
    Write-AuditLog -Action "get_message" -Details "message_id=$MessageId"

    $paramsJson = @{
        userId = "me"
        id = $MessageId
    } | ConvertTo-Json -Compress

    gws gmail users messages get --params $paramsJson
}

function Invoke-MarkRead {
    param(
        [string]$MessageId
    )

    if (-not $MessageId) {
        Write-ColorOutput "Message ID is required for MarkRead action." -Type Error
        exit 1
    }

    Write-ColorOutput "Marking message as read: $MessageId" -Type Info
    Write-AuditLog -Action "mark_read" -Details "message_id=$MessageId"

    $paramsJson = @{
        userId = "me"
        id = $MessageId
    } | ConvertTo-Json -Compress

    $bodyJson = @{
        removeLabelIds = @("UNREAD")
    } | ConvertTo-Json -Compress

    gws gmail users messages modify --params $paramsJson --json $bodyJson
}

function Invoke-MarkUnread {
    param(
        [string]$MessageId
    )

    if (-not $MessageId) {
        Write-ColorOutput "Message ID is required for MarkUnread action." -Type Error
        exit 1
    }

    Write-ColorOutput "Marking message as unread: $MessageId" -Type Info
    Write-AuditLog -Action "mark_unread" -Details "message_id=$MessageId"

    $paramsJson = @{
        userId = "me"
        id = $MessageId
    } | ConvertTo-Json -Compress

    $bodyJson = @{
        addLabelIds = @("UNREAD")
    } | ConvertTo-Json -Compress

    gws gmail users messages modify --params $paramsJson --json $bodyJson
}

function Invoke-CreateDraft {
    param(
        [string]$RawMessage
    )

    if (-not $RawMessage) {
        Write-ColorOutput "Base64-encoded raw message is required for CreateDraft action." -Type Error
        Write-ColorOutput "" -Type Error
        Write-ColorOutput "Example:" -Type Info
        Write-ColorOutput '  $content = Get-Content email.txt -Raw' -Type Info
        Write-ColorOutput '  $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))' -Type Info
        Write-ColorOutput '  .\Gmail-Safe.ps1 -Action CreateDraft -RawMessage $base64' -Type Info
        exit 1
    }

    Write-ColorOutput "Creating draft..." -Type Info
    Write-AuditLog -Action "create_draft" -Details "message_length=$($RawMessage.Length)"

    $paramsJson = @{
        userId = "me"
    } | ConvertTo-Json -Compress

    $bodyJson = @{
        message = @{
            raw = $RawMessage
        }
    } | ConvertTo-Json -Compress

    gws gmail users drafts create --params $paramsJson --json $bodyJson

    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput "Draft created successfully" -Type Success
        Write-ColorOutput "Review and send via Gmail web interface" -Type Info
    }
}

# Blocked Operations

function Block-SendMessage {
    Invoke-BlockedOperation `
        -Operation "send_message" `
        -Reason "Sending emails without review can cause professional embarrassment. Create a draft instead, then send via Gmail web UI after reviewing."
}

function Block-DeleteMessage {
    Invoke-BlockedOperation `
        -Operation "delete_message" `
        -Reason "Permanent deletion cannot be undone. Use Gmail web UI trash feature for safer deletion with recovery window."
}

function Block-TrashMessage {
    Invoke-BlockedOperation `
        -Operation "trash_message" `
        -Reason "Bulk trashing can hide important messages. Use Gmail web UI to review and trash manually."
}

function Block-ModifyLabels {
    Invoke-BlockedOperation `
        -Operation "modify_labels" `
        -Reason "Label modification beyond read/unread flags can disrupt existing organization. Use Gmail web UI for label management."
}

# Help

function Show-Help {
    Get-Help $PSCommandPath -Detailed
}

# Main Execution

Write-ColorOutput "Gmail Safety Wrapper - PowerShell Edition" -Type Info
Write-ColorOutput "=========================================" -Type Info
Write-ColorOutput "" -Type Info

# Pre-flight checks
Test-GwsInstalled
Test-GwsAuthenticated

# Execute action
switch ($Action) {
    'List' {
        Invoke-ListMessages -MaxResults $MaxResults -Query $Query
    }
    'Get' {
        Invoke-GetMessage -MessageId $MessageId
    }
    'MarkRead' {
        Invoke-MarkRead -MessageId $MessageId
    }
    'MarkUnread' {
        Invoke-MarkUnread -MessageId $MessageId
    }
    'CreateDraft' {
        Invoke-CreateDraft -RawMessage $RawMessage
    }
    'Send' {
        Block-SendMessage
    }
    'Delete' {
        Block-DeleteMessage
    }
    'Trash' {
        Block-TrashMessage
    }
    'ModifyLabels' {
        Block-ModifyLabels
    }
    'Help' {
        Show-Help
    }
}

Write-ColorOutput "" -Type Info
Write-ColorOutput "Operation complete. Audit log: $AuditLogPath" -Type Success
