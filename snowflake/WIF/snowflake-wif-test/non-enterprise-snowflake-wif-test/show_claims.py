"""
Steps 1-2 of the handshake: get a token from GitHub and show what's written on it.
The token itself is never printed, only its claims.
"""
import datetime as dt
import os

from snowflake_conn import decode_claims, get_github_oidc_token

CLAIMS_TO_SHOW = [
    "iss", "aud", "sub",
    "repository", "repository_id", "repository_owner_id",
    "ref", "event_name", "workflow", "run_id",
    "iat", "exp",
]


def as_time(seconds: int) -> str:
    return dt.datetime.fromtimestamp(seconds, dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")


def main():
    claims = decode_claims(get_github_oidc_token(os.environ["SNOWFLAKE_AUDIENCE"]))

    rows = []
    for key in CLAIMS_TO_SHOW:
        if key in claims:
            value = claims[key]
            if key in ("iat", "exp"):
                value = f"{value} ({as_time(value)})"
            rows.append((key, value))

    print("Token claims (the token itself is never printed):\n")
    for key, value in rows:
        print(f"  {key:<20} {value}")

    minutes = (claims["exp"] - claims["iat"]) // 60
    print(f"\nThis token is valid for about {minutes} minutes.")
    print("\nPaste this exact value into SUBJECT in setup.sql:\n")
    print(f"  {claims['sub']}\n")

    # Also write a table to the run's summary page in GitHub
    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as f:
            f.write("## Steps 1-2: GitHub token claims\n\n| Claim | Value |\n| --- | --- |\n")
            for key, value in rows:
                f.write(f"| `{key}` | `{value}` |\n")
            f.write(f"\nToken lifetime: about {minutes} minutes.\n\n")


if __name__ == "__main__":
    main()
