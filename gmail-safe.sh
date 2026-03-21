#!/bin/bash
#
# gmail-safe.sh - Safety wrapper for Google Workspace CLI
#
# Purpose: Provides read-only Gmail access with safeguards against
#          accidental deletion, sending, or destructive operations.
#
# Allowed operations:
#   - List messages
#   - Get message content
#   - Mark messages as read/unread
#   - Create drafts
#
# Blocked operations (with clear error messages):
#   - Send messages (use Gmail web UI to review and send drafts)
#   - Delete messages permanently
#   - Trash messages (prevents accidental bulk archiving)
#   - Modify labels (except UNREAD flag)
#
# Security:
#   - Integrates with Tier 1 vault via vault-expose
#   - Credentials exist temporarily in tmpfs only
#   - Auto-cleanup on script exit
#   - Audit logging for all operations
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_SECRET_NAME="${VAULT_SECRET_NAME:-gws_credentials}"
CREDENTIAL_DURATION="${CREDENTIAL_DURATION:-15}"  # minutes
AUDIT_LOG="${AUDIT_LOG:-/mnt/data/secrets/.audit.log}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

audit() {
    local action="$1"
    local details="$2"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    echo "{\"timestamp\":\"$timestamp\",\"action\":\"gmail-safe:$action\",\"details\":\"$details\",\"user\":\"$(whoami)\"}" >> "$AUDIT_LOG" 2>/dev/null || true
}

# Cleanup function
cleanup() {
    if [[ -n "${CREDS_FILE:-}" ]]; then
        log_info "Cleaning up credentials..."
        vault-cleanup "$VAULT_SECRET_NAME" 2>/dev/null || true
    fi
}

# Trap to ensure cleanup on exit
trap cleanup EXIT INT TERM

# Error handler for blocked operations
block_operation() {
    local operation="$1"
    local reason="$2"
    log_error "BLOCKED: $operation"
    log_error "Reason: $reason"
    log_error ""
    log_error "This wrapper only allows safe read-only operations:"
    log_error "  ✓ List messages"
    log_error "  ✓ Get message content"
    log_error "  ✓ Mark as read/unread"
    log_error "  ✓ Create drafts"
    log_error ""
    log_error "For sending or deleting, use Gmail web interface."
    audit "blocked" "$operation: $reason"
    exit 1
}

# Check for required commands
check_dependencies() {
    local missing=()

    command -v gws >/dev/null 2>&1 || missing+=("gws (Google Workspace CLI)")
    command -v vault-expose >/dev/null 2>&1 || missing+=("vault-expose (Tier 1 vault)")
    command -v vault-cleanup >/dev/null 2>&1 || missing+=("vault-cleanup (Tier 1 vault)")
    command -v jq >/dev/null 2>&1 || missing+=("jq (JSON processor)")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies:"
        for dep in "${missing[@]}"; do
            log_error "  - $dep"
        done
        exit 1
    fi
}

# Setup credentials from vault
setup_credentials() {
    log_info "Exposing credentials from Tier 1 vault..."
    log_info "This may require YubiKey tap if session key expired."

    CREDS_FILE=$(vault-expose "$VAULT_SECRET_NAME" --duration "$CREDENTIAL_DURATION")

    if [[ ! -f "$CREDS_FILE" ]]; then
        log_error "Failed to expose credentials from vault"
        exit 1
    fi

    export GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE="$CREDS_FILE"
    log_info "Credentials available for $CREDENTIAL_DURATION minutes"
    audit "credentials_exposed" "duration=${CREDENTIAL_DURATION}m"
}

# Validate that we're using minimal scopes
check_scopes() {
    # This is informational - we can't enforce scopes after auth,
    # but we can remind users to use minimal scopes during initial auth
    log_info "Reminder: Use 'gws auth login -s gmail' for minimal scopes"
    log_info "Avoid 'gws auth login' without scope restriction (85+ scopes)"
}

#
# Safe operations
#

list_messages() {
    local max_results="${1:-10}"
    local query="${2:-}"

    log_info "Listing up to $max_results messages..."

    local params="{\"userId\":\"me\",\"maxResults\":$max_results"
    if [[ -n "$query" ]]; then
        params="$params,\"q\":\"$query\""
    fi
    params="$params}"

    audit "list_messages" "max_results=$max_results, query=$query"
    gws gmail users messages list --params "$params"
}

get_message() {
    local message_id="$1"

    if [[ -z "$message_id" ]]; then
        log_error "Message ID required"
        exit 1
    fi

    log_info "Fetching message: $message_id"
    audit "get_message" "message_id=$message_id"

    gws gmail users messages get --params "{\"userId\":\"me\",\"id\":\"$message_id\"}"
}

mark_read() {
    local message_id="$1"

    if [[ -z "$message_id" ]]; then
        log_error "Message ID required"
        exit 1
    fi

    log_info "Marking message as read: $message_id"
    audit "mark_read" "message_id=$message_id"

    gws gmail users messages modify \
        --params "{\"userId\":\"me\",\"id\":\"$message_id\"}" \
        --json '{"removeLabelIds":["UNREAD"]}'
}

mark_unread() {
    local message_id="$1"

    if [[ -z "$message_id" ]]; then
        log_error "Message ID required"
        exit 1
    fi

    log_info "Marking message as unread: $message_id"
    audit "mark_unread" "message_id=$message_id"

    gws gmail users messages modify \
        --params "{\"userId\":\"me\",\"id\":\"$message_id\"}" \
        --json '{"addLabelIds":["UNREAD"]}'
}

create_draft() {
    local raw_message="$1"

    if [[ -z "$raw_message" ]]; then
        log_error "Base64-encoded raw message required"
        log_error "Tip: Use 'base64' command to encode email message"
        exit 1
    fi

    log_info "Creating draft..."
    audit "create_draft" "message_length=${#raw_message}"

    gws gmail users drafts create \
        --params '{"userId":"me"}' \
        --json "{\"message\":{\"raw\":\"$raw_message\"}}"

    log_info "Draft created successfully"
    log_info "Review and send via Gmail web interface"
}

#
# Blocked operations (explicit rejections)
#

send_message() {
    block_operation \
        "send_message" \
        "Sending emails without review can cause professional embarrassment. Create a draft instead, then send via Gmail web UI after reviewing."
}

delete_message() {
    block_operation \
        "delete_message" \
        "Permanent deletion cannot be undone. Use Gmail web UI trash feature for safer deletion with recovery window."
}

trash_message() {
    block_operation \
        "trash_message" \
        "Bulk trashing can hide important messages. Use Gmail web UI to review and trash manually."
}

modify_labels() {
    block_operation \
        "modify_labels" \
        "Label modification beyond read/unread flags can disrupt existing organization. Use Gmail web UI for label management."
}

#
# Usage and help
#

usage() {
    cat <<EOF
Usage: gmail-safe.sh <command> [arguments]

Safe read-only Gmail operations:
  --list [MAX] [QUERY]          List up to MAX messages (default: 10)
                                Optional QUERY for filtering
  --get MESSAGE_ID              Get full message by ID
  --mark-read MESSAGE_ID        Mark message as read
  --mark-unread MESSAGE_ID      Mark message as unread
  --create-draft RAW_MESSAGE    Create draft (base64-encoded)

Blocked operations (use Gmail web UI):
  --send                        ❌ Blocked: Sending requires review
  --delete                      ❌ Blocked: Permanent deletion dangerous
  --trash                       ❌ Blocked: Use web UI for trashing
  --modify-labels               ❌ Blocked: Use web UI for labels

Configuration:
  VAULT_SECRET_NAME             Name of secret in Tier 1 vault (default: gws_credentials)
  CREDENTIAL_DURATION           Duration in minutes (default: 15)
  AUDIT_LOG                     Path to audit log (default: /mnt/data/secrets/.audit.log)

Examples:
  # List recent messages
  ./gmail-safe.sh --list 20

  # List unread messages
  ./gmail-safe.sh --list 50 "is:unread"

  # Get specific message
  ./gmail-safe.sh --get 18d4c2f8a1b2c3d4

  # Mark as read
  ./gmail-safe.sh --mark-read 18d4c2f8a1b2c3d4

  # Create draft (encode message first)
  RAW=\$(base64 -w0 < email.txt)
  ./gmail-safe.sh --create-draft "\$RAW"

Security:
  - Credentials from Tier 1 vault (YubiKey tap required)
  - Auto-cleanup after $CREDENTIAL_DURATION minutes
  - All operations logged to audit trail
  - Dangerous operations explicitly blocked

EOF
}

#
# Main
#

main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi

    # Check dependencies before exposing credentials
    check_dependencies

    # Parse command
    local command="$1"
    shift

    case "$command" in
        --help|-h)
            usage
            exit 0
            ;;

        # Safe operations - setup credentials then execute
        --list)
            setup_credentials
            check_scopes
            list_messages "${1:-10}" "${2:-}"
            ;;

        --get)
            setup_credentials
            check_scopes
            get_message "$1"
            ;;

        --mark-read)
            setup_credentials
            check_scopes
            mark_read "$1"
            ;;

        --mark-unread)
            setup_credentials
            check_scopes
            mark_unread "$1"
            ;;

        --create-draft)
            setup_credentials
            check_scopes
            create_draft "$1"
            ;;

        # Blocked operations - no credential setup needed
        --send)
            send_message
            ;;

        --delete)
            delete_message
            ;;

        --trash)
            trash_message
            ;;

        --modify-labels)
            modify_labels
            ;;

        *)
            log_error "Unknown command: $command"
            echo ""
            usage
            exit 1
            ;;
    esac
}

main "$@"
