"""
Steps 3-6 of the handshake: hand the token to Snowflake, then check
who we're logged in as (authentication) and what we can do (authorization).
"""
import os
import sys

from snowflake.connector.errors import DatabaseError, ProgrammingError

from snowflake_conn import connect

LOGIN_HINTS = """
Login failed. Most common causes:
  - SUBJECT in setup.sql doesn't exactly match the 'sub' printed in the previous step
  - SNOWFLAKE_AUDIENCE variable doesn't exactly match OIDC_AUDIENCE_LIST in setup.sql
  - The workflow ran from a branch other than main
  - setup.sql hasn't been run yet (expected on your very first run)
  - snowflake-connector-python is older than 3.17.0
"""

IDENTITY_CHECKS = [
    ("User", "SELECT CURRENT_USER()"),
    ("Role", "SELECT CURRENT_ROLE()"),
    ("Warehouse", "SELECT CURRENT_WAREHOUSE()"),
    ("Account", "SELECT CURRENT_ACCOUNT_NAME()"),
    ("Session ID", "SELECT CURRENT_SESSION()"),
    ("Snowflake version", "SELECT CURRENT_VERSION()"),
]

results = []  # (check, outcome) rows for the summary page


def record(check: str, outcome: str):
    results.append((check, outcome))
    print(f"  {check:<34} {outcome}")


def main():
    print("Step 3: handing the token to Snowflake...")
    try:
        conn = connect("snowflake-wif-test")
    except DatabaseError as err:
        print(f"\n{err}")
        print(LOGIN_HINTS)
        sys.exit(1)
    print("Steps 4-6: Snowflake verified the token and opened a session.\n")

    try:
        cur = conn.cursor()

        print("Authentication: who am I?")
        for label, sql in IDENTITY_CHECKS:
            cur.execute(sql)
            record(label, str(cur.fetchone()[0]))

        print("\nAuthorization: what can I do?")

        # Should succeed: the role has USAGE on the warehouse
        cur.execute("SELECT COUNT(*) FROM TABLE(GENERATOR(ROWCOUNT => 1000))")
        record("Run a query on the warehouse", f"OK ({cur.fetchone()[0]} rows generated)")

        # Should fail: the role has no CREATE DATABASE privilege
        try:
            cur.execute("CREATE DATABASE wif_test_should_not_exist")
            cur.execute("DROP DATABASE wif_test_should_not_exist")
            record("Create a database", "ALLOWED - this role has more access than it should!")
        except ProgrammingError:
            record("Create a database", "Blocked, as expected")
    finally:
        conn.close()

    summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary_path:
        with open(summary_path, "a", encoding="utf-8") as f:
            f.write("## Steps 3-6: Snowflake session\n\n| Check | Result |\n| --- | --- |\n")
            for check, outcome in results:
                f.write(f"| {check} | {outcome} |\n")

    print("\nSuccess: WIF login works end to end.")


if __name__ == "__main__":
    main()
