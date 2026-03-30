"""Write (state-mutating) Gmail MCP tools.

Registers tools that modify Gmail state: marking messages read/unread and
creating drafts.  Sending and deleting are intentionally not here — see
blocked.py.  Every tool call is recorded in the audit log.
"""
import base64
import email.message

from mcp.server.fastmcp import FastMCP

from gmail_mcp.audit import audit


def register_write_tools(mcp: FastMCP, get_service) -> None:
    """Register all write Gmail tools on the given FastMCP instance.

    Args:
        mcp:         The FastMCP server instance.
        get_service: Callable with no arguments that returns an authenticated
                     Gmail API service Resource.
    """

    @mcp.tool()
    def mark_read(message_id: str) -> dict:
        """Remove the UNREAD label from a Gmail message.

        Args:
            message_id: The Gmail message ID to mark as read.

        Returns:
            Raw API response dict from the modify call.
        """
        audit("mark_read", f"id={message_id}")
        service = get_service()
        return (
            service.users()
            .messages()
            .modify(
                userId="me",
                id=message_id,
                body={"removeLabelIds": ["UNREAD"]},
            )
            .execute()
        )

    @mcp.tool()
    def mark_unread(message_id: str) -> dict:
        """Add the UNREAD label to a Gmail message.

        Args:
            message_id: The Gmail message ID to mark as unread.

        Returns:
            Raw API response dict from the modify call.
        """
        audit("mark_unread", f"id={message_id}")
        service = get_service()
        return (
            service.users()
            .messages()
            .modify(
                userId="me",
                id=message_id,
                body={"addLabelIds": ["UNREAD"]},
            )
            .execute()
        )

    @mcp.tool()
    def create_draft(to: str, subject: str, body: str) -> dict:
        """Create a Gmail draft.  The draft is NOT sent — review and send via Gmail web UI.

        Args:
            to:      Recipient email address.
            subject: Email subject line.
            body:    Plain-text email body.

        Returns:
            Dict with keys: draft_id, message_id, note.
        """
        audit("create_draft", f"to={to} subject={subject}")

        msg = email.message.EmailMessage()
        msg["From"] = "me"
        msg["To"] = to
        msg["Subject"] = subject
        msg.set_content(body)

        encoded = base64.urlsafe_b64encode(msg.as_bytes()).decode("utf-8")

        service = get_service()
        response = (
            service.users()
            .drafts()
            .create(userId="me", body={"message": {"raw": encoded}})
            .execute()
        )

        return {
            "draft_id": response["id"],
            "message_id": response["message"]["id"],
            "note": "Review and send via Gmail web UI",
        }
