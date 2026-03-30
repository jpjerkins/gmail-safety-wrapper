"""Read-only Gmail MCP tools.

Registers tools that retrieve data from Gmail without modifying any state.
Every tool call is recorded in the audit log.
"""
from mcp.server.fastmcp import FastMCP

from gmail_mcp.audit import audit


def register_read_tools(mcp: FastMCP, get_service) -> None:
    """Register all read-only Gmail tools on the given FastMCP instance.

    Args:
        mcp:         The FastMCP server instance.
        get_service: Callable with no arguments that returns an authenticated
                     Gmail API service Resource.  Called fresh per-tool so that
                     credential rotation is automatically picked up.
    """

    @mcp.tool()
    def list_messages(max_results: int = 10, query: str = "") -> dict:
        """List Gmail messages matching an optional query.

        Args:
            max_results: Maximum number of message stubs to return (default 10).
            query:       Gmail search query string (e.g. "is:unread from:boss@example.com").

        Returns:
            Raw API response dict with keys: messages, nextPageToken, resultSizeEstimate.
        """
        audit("list_messages", f"max_results={max_results} query={query}")
        service = get_service()
        return (
            service.users()
            .messages()
            .list(userId="me", maxResults=max_results, q=query)
            .execute()
        )

    @mcp.tool()
    def get_message(message_id: str) -> dict:
        """Fetch the full content of a single Gmail message.

        Args:
            message_id: The Gmail message ID (from list_messages).

        Returns:
            Raw API response dict including payload, headers, body, and labels.
        """
        audit("get_message", f"id={message_id}")
        service = get_service()
        return service.users().messages().get(userId="me", id=message_id).execute()

    @mcp.tool()
    def get_message_summary(message_id: str) -> dict:
        """Fetch a lightweight summary of a Gmail message (headers only, no body).

        Retrieves only From, To, Subject, and Date — safe for quick triage
        without exposing full message content to the tool caller.

        Args:
            message_id: The Gmail message ID (from list_messages).

        Returns:
            Dict with keys: id, headers (From, To, Subject, Date).
        """
        audit("get_message_summary", f"id={message_id}")
        service = get_service()
        response = (
            service.users()
            .messages()
            .get(userId="me", id=message_id, format="metadata")
            .execute()
        )

        wanted = {"From", "To", "Subject", "Date"}
        extracted = {
            h["name"]: h["value"]
            for h in response.get("payload", {}).get("headers", [])
            if h["name"] in wanted
        }

        return {"id": response.get("id"), "headers": extracted}
