FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Create a non-root user with a fixed UID so host volume permissions are predictable.
RUN groupadd -g 50010 gmail-mcp && useradd -u 50010 -g 50010 -s /bin/false -M gmail-mcp

# Copy source into /app/gmail_mcp/ so it's importable as a package.
COPY gmail_mcp/ ./gmail_mcp/

USER 50010

EXPOSE 8004

CMD ["python", "-m", "gmail_mcp.server"]
