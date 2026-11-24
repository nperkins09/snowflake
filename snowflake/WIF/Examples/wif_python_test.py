import json
import os
import urllib.parse
import urllib.request
import snowflake.connector

SNOWFLAKE_ACCOUNT = os.environ.get("SNOWFLAKE_ACCOUNT")
SNOWFLAKE_AUDIENCE = os.environ.get("SNOWFLAKE_AUDIENCE")

def get_github_oidc_token(audience: str) -> str:
    """
    Ask GitHub for a short-lived ID token (the "badge") for this job.

    Only works inside a GitHub Actions job that has `permissions: id-token: write`.
    """
    # 1. Read the two variables GitHub created for this job
    request_url = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_URL")
    request_token = os.environ.get("ACTIONS_ID_TOKEN_REQUEST_TOKEN")

    if not request_url or not request_token:
        raise RuntimeError(
            "No GitHub OIDC variables found. This must run inside GitHub Actions, "
            "and the workflow needs 'permissions: id-token: write'."
        )

    # 2. Add the audience: who this badge is for (your Snowflake account).
    #    quote() makes the URL safe to put inside another URL (e.g. ':' and '/').
    full_url = request_url + "&audience=" + urllib.parse.quote(audience, safe="")

    # 3. Call GitHub's token service, showing the job's temporary pass
    request = urllib.request.Request(
        full_url,
        headers={"Authorization": f"Bearer {request_token}"},
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        body = json.load(response)

    # 4. GitHub replies with JSON like {"count": ..., "value": "<the token>"}
    return body["value"]



def connect_to_snowflake(app_name: str):
    """
    Log in to Snowflake with a fresh GitHub badge.

    No username or password: Snowflake works out the user from the token.
    Call this each time you need a connection, because tokens expire within minutes.
    """
    # Step 1: get a fresh badge from GitHub
    token = get_github_oidc_token(SNOWFLAKE_AUDIENCE)

    # Step 3: hand the badge to Snowflake
    return snowflake.connector.connect(
        account=SNOWFLAKE_ACCOUNT,
        authenticator="WORKLOAD_IDENTITY",       # "I'm logging in with a token, not a password"
        workload_identity_provider="OIDC",       # "the token is a standard OIDC token (from GitHub)"
        token=token,                              # the badge itself
        application=app_name,                     # shows up in Snowflake's login history
        session_parameters={"QUERY_TAG": app_name},  # labels every query this connection runs
    )

def main():
    conn = connect_to_snowflake("orchestrator")    # Steps 1–6 all happen inside this call
    try:
        cur = conn.cursor()

        # Proof of who you logged in as
        cur.execute("SELECT CURRENT_USER(), CURRENT_ROLE()")
        print("Logged in as:", cur.fetchone())
        # -> ('SVC_OPERATIONS_USER', 'OPERATIONS_ROLE')

        cur.execute("SELECT * FROM governance.public.data_source_registry")
        for row in cur.fetchall():
            print(row)
    finally:
        conn.close()


if __name__ == "__main__":
    main()