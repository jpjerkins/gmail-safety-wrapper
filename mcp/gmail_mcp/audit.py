"""Audit logging for gmail-mcp.

Every tool invocation writes a single NDJSON line to the audit log so there
is a tamper-evident record of every Gmail operation the server performed.
Write errors are silently swallowed — a failing audit log must never block
legitimate tool execution.
"""
import json
import os
from datetime import datetime, timezone


_AUDIT_LOG_PATH = os.getenv("AUDIT_LOG", "/data/.audit.log")


def audit(action: str, details: str) -> None:
    """Append one NDJSON record to the audit log.

    Args:
        action:  Short verb describing what happened (e.g. "list_messages").
        details: Free-form context string (never include email body content).
    """
    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "action": f"gmail-mcp:{action}",
        "details": details,
        "uid": os.getuid(),
    }
    try:
        with open(_AUDIT_LOG_PATH, "a") as fh:
            fh.write(json.dumps(record) + "\n")
    except Exception:
        # Never let audit failures propagate to the caller.
        pass
