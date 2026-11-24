# Tutorial: GitHub Actions → Snowflake with Workload Identity Federation

Nov 6, 2026

## What you'll build

You'll build a tiny "hello world" pipeline in a sandbox GitHub org and a sandbox Snowflake database. It authenticates with no stored secrets, reads its settings from a config table, and writes one row per run. It's a miniature copy of your real orchestrator/pipeline setup, so every piece maps directly to what you'll run in production.

When a run connects, this is the handshake you're building:

1. The workflow asks GitHub's OIDC provider for a short-lived signed token (a JWT).
2. The token's claims say who is running: your org's ID and the branch (`main`).
3. The Python connector sends the token to Snowflake.
4. Snowflake checks GitHub's signature, the issuer, the audience and the subject.
5. If all four match the service user, Snowflake opens a session as that user, with its default role and warehouse.
6. From there, normal Snowflake permissions (grants) decide what the session can do.

The key lesson is that steps 1–5 are **authentication** (who you are) and step 6 is **authorization** (what you can do). Step 8 of this tutorial breaks each one on purpose so you can see the difference.

Everything lives in sandbox objects named `WIF_TUTORIAL…`, so nothing touches your production `governance` database. Plan for about 1–2 hours.

## Prerequisites

You need a Snowflake account where you can use ACCOUNTADMIN (or both SECURITYADMIN and SYSADMIN), a GitHub account, and these tools on your machine:

- [ ] `git`
- [ ] The GitHub CLI (`gh`), logged in with `gh auth login`
- [ ] Python 3.10+ (only needed if you want to test code locally; the runs happen on GitHub)

The org-level OIDC setting needs an extra token scope. Add it now:

```bash
gh auth refresh -h github.com -s admin:org
```

Decide these values up front and substitute them everywhere you see the placeholder:

| Placeholder | What it is | Example shape |
| --- | --- | --- |
| `<SANDBOX_ORG>` | A new GitHub org just for this tutorial | `yourname-wif-sandbox` |
| `<SF_ACCOUNT>` | Your Snowflake account identifier | `<orgname>-<account_name>` |
| `<SF_AUDIENCE>` | Your account URL, used as the token audience | `https://<orgname>-<account_name>.snowflakecomputing.com` |
| `<ORG_ID>` | Your sandbox org's numeric ID (found in Step 2) | a number like `123456789` |

To find `<SF_ACCOUNT>`, run this in a Snowsight worksheet:

```sql
SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME();
```

## Step 1: Create a sandbox GitHub org and repo

A separate org lets you experiment with org-wide settings without affecting your real repos.

1. On github.com, click your avatar → **Your organizations** → **New organization**, and pick the **Free** plan. Name it `<SANDBOX_ORG>`.
2. Create a private repo and clone it:

```bash
gh repo create <SANDBOX_ORG>/wif-hello-world --private --add-readme --clone
cd wif-hello-world
mkdir -p .github/workflows
```

**Checkpoint:** `gh repo view <SANDBOX_ORG>/wif-hello-world` shows the repo as private.

## Step 2: Customize the OIDC subject claim

By default, every repo's token has a different subject (`repo:<org>/<repo>:...`). Here you change it org-wide so every repo produces the same subject on `main`. That's what lets one Snowflake user serve your whole fleet.

Get your org's numeric ID and write it down as `<ORG_ID>`:

```bash
gh api /orgs/<SANDBOX_ORG> --jq .id
```

Set the org template to build the subject from the owner ID plus the context (the branch or environment):

```bash
gh api --method PUT /orgs/<SANDBOX_ORG>/actions/oidc/customization/sub --input - <<'EOF'
{"include_claim_keys": ["repository_owner_id", "context"]}
EOF
```

Confirm it saved:

```bash
gh api /orgs/<SANDBOX_ORG>/actions/oidc/customization/sub
```

**Checkpoint:** the output shows `"include_claim_keys":["repository_owner_id","context"]`.

The owner ID is used instead of the org name because IDs don't change if you rename the org. The context restricts which branch can authenticate.

## Step 3: See the token's claims and copy the subject

This workflow asks GitHub for a token and prints its claims (never the token itself), so you can see exactly what Snowflake will receive. Create `.github/workflows/oidc-debug.yml`:

```yaml
name: oidc-debug
on: workflow_dispatch
permissions:
  id-token: write
  contents: read
jobs:
  claims:
    runs-on: ubuntu-latest
    steps:
      - name: Print OIDC claims
        env:
          AUD: <SF_AUDIENCE>
        run: |
          python3 - <<'EOF'
          import os, json, base64, urllib.request, urllib.parse
          url = os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"] + "&audience=" + urllib.parse.quote(os.environ["AUD"], safe="")
          req = urllib.request.Request(url, headers={"Authorization": "Bearer " + os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]})
          token = json.load(urllib.request.urlopen(req))["value"]
          payload = token.split(".")[1]
          payload += "=" * (-len(payload) % 4)
          claims = json.loads(base64.urlsafe_b64decode(payload))
          print(json.dumps(claims, indent=2, sort_keys=True))
          EOF
```

Commit, push and run it:

```bash
git add . && git commit -m "Add OIDC debug workflow" && git push
gh workflow run oidc-debug.yml --ref main
gh run watch
gh run view --log | grep -A 60 "Print OIDC claims"
```

In the output, check three claims:

| Claim | Expected value |
| --- | --- |
| `iss` | `https://token.actions.githubusercontent.com` |
| `aud` | your `<SF_AUDIENCE>` |
| `sub` | something like `repository_owner_id:<ORG_ID>:ref:refs/heads/main` |

**Copy the `sub` value exactly.** Snowflake compares it character for character in Step 5.

If `sub` still starts with `repo:`, this repo didn't pick up the org template. Apply it at the repo level, then rerun the workflow:

```bash
gh api --method PUT /repos/<SANDBOX_ORG>/wif-hello-world/actions/oidc/customization/sub --input - <<'EOF'
{"use_default": false, "include_claim_keys": ["repository_owner_id", "context"]}
EOF
```

While you're here, read the other claims too, such as `ref`, `workflow_ref`, `run_id`, `exp` and `runner_environment`. Note that `exp` is only minutes after `iat`: the token is short-lived by design.

## Step 4: Create the Snowflake sandbox objects

These objects mirror your real setup: a config table the pipeline reads, and a raw schema it writes to. Run this in a Snowsight worksheet:

```sql
-- Warehouse and database (owned by SYSADMIN)
USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS wif_tutorial_wh
  WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
CREATE DATABASE IF NOT EXISTS wif_tutorial;
CREATE SCHEMA IF NOT EXISTS wif_tutorial.ops;   -- like governance.operations
CREATE SCHEMA IF NOT EXISTS wif_tutorial.raw;   -- where pipelines land data
CREATE SCHEMA IF NOT EXISTS wif_tutorial.admin; -- holds the auth policy

-- A miniature pipeline_config with one row
CREATE TABLE IF NOT EXISTS wif_tutorial.ops.pipeline_config (
  pipeline_name STRING,
  target_table  STRING,
  max_retries   NUMBER
);
INSERT INTO wif_tutorial.ops.pipeline_config
  VALUES ('hello_world', 'WIF_TUTORIAL.RAW.HELLO_RUNS', 3);

-- The role the pipeline will use
USE ROLE SECURITYADMIN;
CREATE ROLE IF NOT EXISTS wif_tutorial_role;
GRANT ROLE wif_tutorial_role TO ROLE SYSADMIN;

GRANT USAGE ON WAREHOUSE wif_tutorial_wh TO ROLE wif_tutorial_role;
GRANT USAGE ON DATABASE wif_tutorial TO ROLE wif_tutorial_role;

-- Config: read-only
GRANT USAGE ON SCHEMA wif_tutorial.ops TO ROLE wif_tutorial_role;
GRANT SELECT ON TABLE wif_tutorial.ops.pipeline_config TO ROLE wif_tutorial_role;

-- Raw: can create tables (and will own the ones it creates)
GRANT USAGE, CREATE TABLE ON SCHEMA wif_tutorial.raw TO ROLE wif_tutorial_role;
```

Notice what the role *can't* do. It has no grants on the `admin` schema and can't modify `pipeline_config`. That separation keeps your config as a control plane only you can change.

**Checkpoint:** `SHOW GRANTS TO ROLE wif_tutorial_role;` lists exactly the grants above.

## Step 5: Create the WIF service user and authentication policy

This is where you tell Snowflake which GitHub tokens to trust. The four values in the `WORKLOAD_IDENTITY` block are exactly what Snowflake checks against the token.

```sql
USE ROLE SECURITYADMIN;
CREATE USER IF NOT EXISTS svc_wif_tutorial
  TYPE = SERVICE                      -- no password, no interactive login
  DEFAULT_ROLE = wif_tutorial_role
  DEFAULT_WAREHOUSE = wif_tutorial_wh
  WORKLOAD_IDENTITY = (
    TYPE = OIDC
    ISSUER = 'https://token.actions.githubusercontent.com'
    SUBJECT = '<paste the sub from Step 3>'
    OIDC_AUDIENCE_LIST = ('<SF_AUDIENCE>')
  );
GRANT ROLE wif_tutorial_role TO USER svc_wif_tutorial;
```

Next, create an authentication policy so this user can *only* log in through GitHub's OIDC provider. Policies are schema objects, so it goes in the `admin` schema:

```sql
USE ROLE ACCOUNTADMIN;
CREATE AUTHENTICATION POLICY wif_tutorial.admin.github_wif_only
  AUTHENTICATION_METHODS = ('WORKLOAD_IDENTITY')
  WORKLOAD_IDENTITY_POLICY = (
    ALLOWED_PROVIDERS = (OIDC)
    ALLOWED_OIDC_ISSUERS = ('https://token.actions.githubusercontent.com')
  );
ALTER USER svc_wif_tutorial SET AUTHENTICATION POLICY wif_tutorial.admin.github_wif_only;
```

If the policy statement is rejected, check the `WORKLOAD_IDENTITY_POLICY` parameter names against Snowflake's current `CREATE AUTHENTICATION POLICY` reference. Attach it only to this user, never at the account level, or you can lock yourself out.

**Checkpoint:** both of these return results that match what you set:

```sql
SHOW USER WORKLOAD IDENTITY AUTHENTICATION METHODS FOR USER svc_wif_tutorial;
DESCRIBE AUTHENTICATION POLICY wif_tutorial.admin.github_wif_only;
```

## Step 6: Write the hello-world pipeline

You'll add four files to the repo. Together they're the same shape as one of your real pipelines.

**`requirements.txt`** — WIF needs connector version 3.17.0 or later:

```text
snowflake-connector-python>=3.17.0
```

**`snowflake_conn.py`** — the shared connection module. In production, this lives in your pipeline template repo:

```python
import json, os, urllib.parse, urllib.request
import snowflake.connector

SNOWFLAKE_ACCOUNT = "<SF_ACCOUNT>"
SNOWFLAKE_AUDIENCE = "<SF_AUDIENCE>"

def _github_oidc_token(audience: str) -> str:
    """Ask GitHub's OIDC provider for a short-lived token for this run."""
    url = os.environ["ACTIONS_ID_TOKEN_REQUEST_URL"] + "&audience=" + urllib.parse.quote(audience, safe="")
    req = urllib.request.Request(
        url, headers={"Authorization": "Bearer " + os.environ["ACTIONS_ID_TOKEN_REQUEST_TOKEN"]}
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.load(r)["value"]

def connect(pipeline_name: str):
    """Open a fresh connection. No user, password or role: the token decides who you are."""
    return snowflake.connector.connect(
        account=SNOWFLAKE_ACCOUNT,
        authenticator="WORKLOAD_IDENTITY",
        workload_identity_provider="OIDC",
        token=_github_oidc_token(SNOWFLAKE_AUDIENCE),
        application=pipeline_name,
        session_parameters={"QUERY_TAG": pipeline_name},
    )
```

**`main.py`** — the pipeline. It reads its config row, then writes to the target table that row names:

```python
import os
from snowflake_conn import connect

PIPELINE = "hello_world"

def main():
    conn = connect(PIPELINE)
    try:
        cur = conn.cursor()

        cur.execute("SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE()")
        print("Connected as (user, role, warehouse):", cur.fetchone())

        cur.execute(
            "SELECT target_table, max_retries FROM wif_tutorial.ops.pipeline_config WHERE pipeline_name = %s",
            (PIPELINE,),
        )
        row = cur.fetchone()
        if row is None:
            raise SystemExit(f"No config row for {PIPELINE}")
        target_table, max_retries = row
        print(f"Config: target_table={target_table}, max_retries={max_retries}")

        # IDENTIFIER(%s) binds the table name safely instead of pasting it into the SQL
        cur.execute(
            "CREATE TABLE IF NOT EXISTS IDENTIFIER(%s) (run_at TIMESTAMP_NTZ, github_run_id STRING, message STRING)",
            (target_table,),
        )
        cur.execute(
            "INSERT INTO IDENTIFIER(%s) VALUES (CURRENT_TIMESTAMP(), %s, %s)",
            (target_table, os.environ.get("GITHUB_RUN_ID"), "hello from GitHub Actions"),
        )
        print("Wrote 1 row.")
    finally:
        conn.close()

if __name__ == "__main__":
    main()
```

**`.github/workflows/run-pipeline.yml`** — the workflow your orchestrator would trigger:

```yaml
name: run-pipeline
on:
  workflow_dispatch:
permissions:
  id-token: write   # lets the job request an OIDC token
  contents: read
jobs:
  run:
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v4      # pin to a commit SHA in production
      - uses: actions/setup-python@v5  # pin to a commit SHA in production
        with:
          python-version: "3.12"
      - run: pip install -r requirements.txt
      - run: python main.py
```

Commit and push:

```bash
git add . && git commit -m "Add hello-world pipeline" && git push
```

Notice that nothing secret is in the repo. The account identifier and audience aren't secrets, and there's nothing to put in GitHub Secrets.

## Step 7: Run it and verify

Trigger the pipeline the same way your orchestrator will, by dispatching it on `main`:

```bash
gh workflow run run-pipeline.yml --ref main
gh run watch
gh run view --log | grep -E "Connected as|Config:|Wrote"
```

**Checkpoint:** the log shows lines like these:

```text
Connected as (user, role, warehouse): ('SVC_WIF_TUTORIAL', 'WIF_TUTORIAL_ROLE', 'WIF_TUTORIAL_WH')
Config: target_table=WIF_TUTORIAL.RAW.HELLO_RUNS, max_retries=3
Wrote 1 row.
```

Now look at it from the Snowflake side. Run these in Snowsight:

```sql
-- 1. The data the pipeline wrote
SELECT * FROM wif_tutorial.raw.hello_runs ORDER BY run_at DESC;

-- 2. How it logged in (look for WORKLOAD_IDENTITY as the auth factor)
SELECT event_timestamp, user_name, first_authentication_factor, is_success, error_message
FROM TABLE(wif_tutorial.information_schema.login_history_by_user(USER_NAME => 'SVC_WIF_TUTORIAL'))
ORDER BY event_timestamp DESC;

-- 3. What it ran, tagged by pipeline
SELECT start_time, query_tag, query_text
FROM TABLE(wif_tutorial.information_schema.query_history_by_user(USER_NAME => 'SVC_WIF_TUTORIAL'))
ORDER BY start_time DESC;
```

Run the workflow two or three more times and watch new rows appear. Each row's `github_run_id` matches the run in the GitHub Actions tab, which links every Snowflake write back to the exact run that made it.

## Step 8: Break it on purpose

This step is where the understanding comes from. Run each experiment, note the exact error, then undo it before the next one. Except for experiment 1, make the change on `main`, run the workflow, and undo it with `git revert HEAD && git push`.

| # | Experiment | How | What you'll see | Lesson |
| --- | --- | --- | --- | --- |
| 1 | Run from another branch | `git checkout -b experiment && git push -u origin experiment`, then `gh workflow run run-pipeline.yml --ref experiment` | Snowflake rejects the login | The token's `sub` now ends in `refs/heads/experiment`, so it doesn't match the user. Only `main` can authenticate. |
| 2 | Remove the token permission | Delete the `id-token: write` line from `run-pipeline.yml` | `KeyError: 'ACTIONS_ID_TOKEN_REQUEST_URL'` before Snowflake is ever contacted | GitHub only issues tokens to jobs that ask for the permission. |
| 3 | Use the wrong audience | Change `SNOWFLAKE_AUDIENCE` in `snowflake_conn.py` to `snowflakecomputing.com` | Snowflake rejects the login | The audience must match `OIDC_AUDIENCE_LIST`. This check stops a token minted for another account from working on yours. |
| 4 | Revoke config access | In Snowflake: `REVOKE SELECT ON TABLE wif_tutorial.ops.pipeline_config FROM ROLE wif_tutorial_role;` | "Connected as" prints, then the config query fails | Authentication succeeded but authorization failed. Who you are and what you can do are separate checks. |
| 5 | Try to change config | Add `cur.execute("DELETE FROM wif_tutorial.ops.pipeline_config")` to `main.py` | Insufficient privileges error | The pipeline can read its control plane but not rewrite it. |

After experiment 4, restore the grant:

```sql
USE ROLE SECURITYADMIN;
GRANT SELECT ON TABLE wif_tutorial.ops.pipeline_config TO ROLE wif_tutorial_role;
```

For experiments 1 and 3, also check `login_history_by_user` from Step 7. The failed logins appear with an error message, which shows you what a real attack attempt would look like in your monitoring.

When you're done, run the workflow on `main` once more to confirm everything works again.

## Step 9: Clean up

Drop the user first, because a policy can't be dropped while it's attached to someone:

```sql
USE ROLE ACCOUNTADMIN;
DROP USER IF EXISTS svc_wif_tutorial;
DROP AUTHENTICATION POLICY IF EXISTS wif_tutorial.admin.github_wif_only;
DROP DATABASE IF EXISTS wif_tutorial;
DROP WAREHOUSE IF EXISTS wif_tutorial_wh;
DROP ROLE IF EXISTS wif_tutorial_role;
```

On GitHub, delete the repo (this needs one more token scope):

```bash
gh auth refresh -h github.com -s delete_repo
gh repo delete <SANDBOX_ORG>/wif-hello-world --yes
```

You can keep the sandbox org for future experiments, or delete it under the org's **Settings** → **Danger zone**.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `KeyError: 'ACTIONS_ID_TOKEN_REQUEST_URL'` | The workflow lacks `id-token: write` | Add it under `permissions` |
| Login rejected on `main` | `SUBJECT` doesn't exactly match the token's `sub` | Rerun Step 3 and copy `sub` again. Look for spaces or a missing prefix. |
| Login rejected, `sub` is correct | Audience mismatch | Make code and `OIDC_AUDIENCE_LIST` identical, including any trailing slash |
| `sub` starts with `repo:` | The repo didn't inherit the org template | Run the repo-level command in Step 3 |
| Unknown authenticator error | Connector is older than 3.17.0 | Check `pip show snowflake-connector-python` in the run log |
| Connected, but "object does not exist" | Missing grant (authorization, not authentication) | Compare against `SHOW GRANTS TO ROLE wif_tutorial_role` |
| Auth policy statement fails | Parameter names differ from the current docs | Check the `CREATE AUTHENTICATION POLICY` reference |

## From tutorial to production

Each tutorial object has a production counterpart: `svc_wif_tutorial` becomes `svc_operations_user`, `wif_tutorial.ops.pipeline_config` becomes `governance.operations.pipeline_config`, and `wif-hello-world` becomes your pipeline template repo. The production steps are the same as Steps 2–6, run against your real org and database.

The one piece this tutorial skips is the orchestrator triggering other repos with a GitHub App. Once this tutorial works, that's the natural next exercise.

## Sources

- [Snowflake: Workload identity federation](https://docs.snowflake.com/en/user-guide/workload-identity-federation)
- [Snowflake: Configure CI/CD integrations quickstart](https://www.snowflake.com/en/developers/guides/configure-cicd-integrations-with-snowflake)
- [GitHub: OpenID Connect reference](https://docs.github.com/en/actions/reference/security/oidc)
- [GitHub: REST API for Actions OIDC](https://docs.github.com/en/rest/actions/oidc)