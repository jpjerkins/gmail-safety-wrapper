## Documentation
The documentation for this project lives in my notes vault, in a project folder called "Gmail Management Skill".

## MCP Server

The `mcp/` subfolder contains a Python FastMCP server that exposes Gmail operations as MCP tools for Claude Code clients.

### Architecture
- FastMCP SSE server, port 8004, UID 50010
- Credentials read from vault-t2 FUSE mount at `/run/vault-t2-fs/gws_credentials`
- UID 50010 is listed in `/etc/vault-t2/acl.yaml` for `gws_credentials`
- Audit log: `/data/.audit.log` inside container → `/mnt/data/gmail-mcp/.audit.log` on host
- Deployed via DCM (`gmail-mcp` service)

### Deployment

Deploy via DCM with `vault_uid: 50010` and `data_dir: true`. The template auto-generates
`user:`, the FUSE volume mount, and the `/data` volume. Only one manual patch needed
(Claude handles this, not the user) — add `ports:` to the generated compose file:

```yaml
ports:
  - "8004:8004"
```

Build context in the compose file must point to `/home/philj/apps/gmail-safety-wrapper/mcp`.

**Pre-deploy requirements on pi5:**
1. UID 50010 must be in `/etc/vault-t2/acl.yaml` for `gws_credentials`
2. `sudo systemctl restart vault-t2-fuse`

### Registering the MCP client

```bash
# From laptop or other remote device:
claude mcp add --transport sse gmail --scope user http://thejerkins.duckdns.org:8004/sse

# On pi5 itself:
claude mcp add --transport sse gmail --scope user http://localhost:8004/sse
```

### Re-authenticating (when credentials expire)

Google revokes refresh tokens after ~7 days if the OAuth consent screen is in *testing* mode.

**1. On the laptop** (browser required — `gws auth login` cannot run headlessly over SSH):
```bash
gws auth login -s gmail
gws auth export --unmasked > gws-creds-new.json
```

**2. Copy to pi5 and re-seal:**
```bash
# From laptop:
scp gws-creds-new.json philj@thejerkins.duckdns.org:/tmp/

# On pi5:
t2-set gws_credentials < /tmp/gws-creds-new.json
rm /tmp/gws-creds-new.json
```

No container restart needed — the FUSE mount decrypts on demand.
