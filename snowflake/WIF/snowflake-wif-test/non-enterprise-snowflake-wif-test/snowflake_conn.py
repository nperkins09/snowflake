"""
Helpers for logging in to Snowflake from GitHub Actions with
workload identity federation (WIF). No passwords or keys anywhere.
"""
import base64
import json
import os
import urllib.parse
import urllib.request

import snowflake.connector


def _required_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(
            f"Missing environment variable {name}. "
            f"Set it as a repository variable: gh variable set {name} --body \"...\""
        )
    return value


def get_github_oidc_token(audience: str) -> str:
    """
    Steps 1-2: ask GitHub for a short-lived ID token (the "badge") for this job.

    GitHub creates ACTIONS_ID_TOKEN_REQUEST_URL and ACTIONS_ID_TOKEN_REQUEST_TOKEN
    automatically, but only in jobs whose workflow has `permissions: id-token: write`.
    """
    request_url = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_URL")
    request_token = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_TOKEN")
    if not request_url or not request_token:
        raise RuntimeError(
            "GitHub's OIDC variables are missing. This only works inside a GitHub Actions "
            "job whose workflow has 'permissions: id-token: write'."
        )

    # The URL already has a '?', so the audience is added with '&'.
    full_url = request_url + "&audience=" + urllib.parse.quote(audience, safe="")
    request = urllib.request.Request(
        full_url, headers={"Authorization": f"Bearer {request_token}"}
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.load(response)["value"]


def decode_claims(token: str) -> dict:
    """
    Read the token's payload (the text on the badge).

    This does NOT check the signature. Snowflake does that in step 5.
    """
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)  # restore base64 padding
    return json.loads(base64.urlsafe_b64decode(payload))


def connect(app_name: str):
    """
    Step 3: log in to Snowflake by handing over a fresh token.

    No username: Snowflake finds the user whose ISSUER + SUBJECT match the token.
    Call this each time you need a connection, because tokens expire within minutes.
    """
    account = _required_env("SNOWFLAKE_ACCOUNT")
    audience = _required_env("SNOWFLAKE_AUDIENCE")

    return snowflake.connector.connect(
        account=account,
        authenticator="WORKLOAD_IDENTITY",
        workload_identity_provider="OIDC",
        token=get_github_oidc_token(audience),
        application=app_name,
        session_parameters={"QUERY_TAG": app_name},
        login_timeout=30,
    )
