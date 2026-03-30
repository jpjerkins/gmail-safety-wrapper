"""Explicitly blocked Gmail operations.

These tools are registered so that an LLM client sees them and understands
they exist but are disabled — rather than hallucinating that they succeed.
Each one raises ValueError with a clear remediation message.
"""
from mcp.server.fastmcp import FastMCP


def register_blocked_tools(mcp: FastMCP) -> None:
    """Register stub tools for operations that are intentionally blocked.

    Args:
        mcp: The FastMCP server instance.
    """

    @mcp.tool()
    def send_message(**kwargs) -> None:
        """Blocked: direct sending is disabled for safety."""
        raise ValueError("Blocked: create a draft and send via Gmail web UI.")

    @mcp.tool()
    def delete_message(**kwargs) -> None:
        """Blocked: permanent deletion is disabled for safety."""
        raise ValueError("Blocked: permanent deletion disabled. Use Gmail web UI.")

    @mcp.tool()
    def trash_message(**kwargs) -> None:
        """Blocked: trashing via API is disabled for safety."""
        raise ValueError("Blocked: use Gmail web UI to trash messages.")

    @mcp.tool()
    def modify_labels(**kwargs) -> None:
        """Blocked: arbitrary label changes are disabled for safety."""
        raise ValueError(
            "Blocked: arbitrary label changes disabled. Use mark_read or mark_unread."
        )
