"""Gmail API authentication.

Loads OAuth credentials from the vault-t2 FUSE mount and returns an
authenticated Gmail API service object. The container runs as UID 50010,
which is listed in /etc/vault-t2/acl.yaml for the gws_credentials secret.

Environment:
    VAULT_CREDS_PATH — path to credentials JSON file.
                       Default: /run/vault-t2-fs/gws_credentials
"""
import json
import os
from pathlib import Path

import google.oauth2.credentials
import googleapiclient.discovery

_DEFAULT_CREDS_PATH = "/run/vault-t2-fs/gws_credentials"


def build_gmail_service():
    creds_path = Path(os.getenv("VAULT_CREDS_PATH", _DEFAULT_CREDS_PATH))

    if not creds_path.exists():
        raise RuntimeError(
            f"Credentials file not found at {creds_path}. "
            "Ensure vault-t2-fuse is running and UID 50010 is in acl.yaml."
        )

    try:
        creds_data = json.loads(creds_path.read_text())
    except Exception as exc:
        raise RuntimeError(f"Failed to read credentials at {creds_path}: {exc}") from exc

    creds = google.oauth2.credentials.Credentials.from_authorized_user_info(creds_data)
    return googleapiclient.discovery.build("gmail", "v1", credentials=creds)
