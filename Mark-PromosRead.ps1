#Requires -Version 5.1
<#
.SYNOPSIS
    Marks all unread Promotions and Updates messages in the inbox as read.

.DESCRIPTION
    Queries Gmail for unread messages in the Promotions and Updates categories
    (inbox only), then marks each one as read via the Gmail-Safe.ps1 wrapper.

    Fetches up to -MaxResults messages per category (default: 500).
    Gmail's resultSizeEstimate is unreliable; run again if the inbox still
    shows unread counts after the first pass.

.PARAMETER MaxResults
    Maximum messages to fetch per category. Default: 500.

.PARAMETER WhatIf
    List what would be marked read without actually doing it.

.EXAMPLE
    .\Mark-PromosRead.ps1

.EXAMPLE
    .\Mark-PromosRead.ps1 -WhatIf

.EXAMPLE
    .\Mark-PromosRead.ps1 -MaxResults 200
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [int]$MaxResults = 500
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Wrapper   = Join-Path $ScriptDir "Gmail-Safe.ps1"

function Get-UnreadIds {
    param([string]$Query)

    $raw = powershell.exe -ExecutionPolicy Bypass -Command "
        Set-Location '$ScriptDir'
        `$out = .\Gmail-Safe.ps1 -Action List -MaxResults $MaxResults -Query '$Query' 2>`$null |
            Where-Object { `$_ -notmatch '^\[' } | Out-String
        `$out
    "

    $data = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($data.messages) { return $data.messages.id }
    return @()
}

Write-Host "Fetching unread Promotions..." -NoNewline
$promoIds  = Get-UnreadIds "is:unread in:inbox category:promotions"
Write-Host " $($promoIds.Count)"

Write-Host "Fetching unread Updates..." -NoNewline
$updateIds = Get-UnreadIds "is:unread in:inbox category:updates"
Write-Host " $($updateIds.Count)"

$allIds = @($promoIds) + @($updateIds) | Select-Object -Unique
Write-Host "Total unique messages to mark read: $($allIds.Count)"

if ($allIds.Count -eq 0) {
    Write-Host "Nothing to do."
    exit 0
}

if ($WhatIfPreference) {
    Write-Host "`n-WhatIf: would mark $($allIds.Count) messages as read."
    exit 0
}

$success = 0
$errors  = 0
$i       = 0

foreach ($id in $allIds) {
    $i++
    Write-Host "[$i/$($allIds.Count)] $id" -NoNewline

    powershell.exe -ExecutionPolicy Bypass -Command "
        Set-Location '$ScriptDir'
        .\Gmail-Safe.ps1 -Action MarkRead -MessageId '$id' 2>`$null | Out-Null
    "

    if ($LASTEXITCODE -eq 0) {
        Write-Host " OK"
        $success++
    } else {
        Write-Host " FAILED"
        $errors++
    }
}

Write-Host ""
Write-Host "Done. Marked read: $success   Errors: $errors"
