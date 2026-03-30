"""Gmail MCP server entry point.

Exposes Gmail operations as MCP tools accessible to Claude Code clients.
Blocked operations are registered as stubs so clients understand they are
intentionally unavailable.

Transport: SSE (HTTP) on PORT (default 8004).
Credentials: vault-t2 FUSE mount at VAULT_CREDS_PATH.
"""
import os

from mcp.server.fastmcp import FastMCP

from gmail_mcp.auth import build_gmail_service
from gmail_mcp.tools_read import register_read_tools
from gmail_mcp.tools_write import register_write_tools
from gmail_mcp.blocked import register_blocked_tools

PORT = int(os.getenv("PORT", "8004"))

mcp = FastMCP("Gmail", host="0.0.0.0", port=PORT)

register_read_tools(mcp, build_gmail_service)
register_write_tools(mcp, build_gmail_service)
register_blocked_tools(mcp)

if __name__ == "__main__":
    mcp.run(transport="sse")
