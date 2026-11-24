# snowflake-wif-test

A small repo for learning how GitHub Actions logs in to Snowflake with
**workload identity federation (WIF)**, with no passwords, keys or secrets.

It uses its own Snowflake test user (`svc_wif_test`), so it never touches
your production `svc_operations_user`.

Everything below uses the GitHub website and Snowsight, with one exception
in step 5 that only applies in a specific case.

> **This repo is set up for GitHub Enterprise Cloud with data residency.**
> Your GitHub lives at `https://flyontario-emu.ghe.com`, and its tokens are issued by
> `https://token.actions.flyontario-emu.ghe.com` rather than github.com's
> `https://token.actions.githubusercontent.com`. Snowflake must be told the
> GHE.com issuer, which `setup.sql` already does.

## What's in here

| File | What it does |
| --- | --- |
| `.github/workflows/test-wif.yml` | The workflow. Grants `id-token: write` and runs the two scripts |
| `snowflake_conn.py` | Gets a token from GitHub (steps 1-2) and logs in to Snowflake with it (step 3) |
| `show_claims.py` | Prints what's written on the token, including the `sub` to paste into Snowflake |
| `test_connection.py` | Logs in, shows who you are, and tests what you can and can't do |
| `requirements.txt` | Installs the Snowflake connector (version 3.17.0 or newer) |
| `setup.sql` | Creates the Snowflake test user, role, warehouse and auth policy |
| `check_logins.sql` | Shows the login and queries from Snowflake's side |
| `cleanup.sql` | Removes everything `setup.sql` created |

## Before you start: two values

Open a Snowsight worksheet and run:

```sql
SELECT CURRENT_ORGANIZATION_NAME() || '-' || CURRENT_ACCOUNT_NAME();
```

Write down the result and build the audience from it. For example:

| Value | Example |
| --- | --- |
| Account identifier | `ACME-DATA01` |
| Audience | `https://ACME-DATA01.snowflakecomputing.com` |

## Setup

### 1. Create the repo

1. On `https://flyontario-emu.ghe.com`, click **+** (top right) → **New repository**.
2. **Owner:** your org. **Repository name:** `snowflake-wif-test`.
3. Select **Private**. Leave **Add a README file** unchecked.
4. Click **Create repository**.

### 2. Upload the files

On the empty repo's page, click the **uploading an existing file** link.

1. Unzip `snowflake-wif-test.zip` on your computer.
2. Open the unzipped folder and drag in every file **except** the `.github`
   folder: `README.md`, `requirements.txt`, the three `.py` files, the
   three `.sql` files and `.gitignore`.
3. Click **Commit changes**.

The workflow file goes in separately, because GitHub needs it in a specific
folder:

1. Click **Add file** → **Create new file**.
2. In the name box, type `.github/workflows/test-wif.yml`. Each `/` you type
   turns the part before it into a folder.
3. Open `.github\workflows\test-wif.yml` from the unzipped folder in a text
   editor (such as Notepad), copy everything, and paste it into the editor.
4. Click **Commit changes...** → **Commit changes**.

**Check:** the repo's file list shows a `.github` folder, and the **Actions**
tab lists a workflow called **test-wif-connection**.

### 3. Add the two repository variables

1. In the repo, go to **Settings** → **Secrets and variables** → **Actions**.
2. Click the **Variables** tab (not Secrets: neither value is sensitive).
3. Click **New repository variable** and add each one:

| Name | Value |
| --- | --- |
| `SNOWFLAKE_ACCOUNT` | your account identifier, e.g. `ACME-DATA01` |
| `SNOWFLAKE_AUDIENCE` | your audience, e.g. `https://ACME-DATA01.snowflakecomputing.com` |

### 4. First run: read the token (the login will fail, which is expected)

1. Go to the **Actions** tab.
2. Click **test-wif-connection** in the left sidebar.
3. Click **Run workflow** (right side), keep **Branch: main**, and click the
   green **Run workflow** button.
4. After a few seconds, a new run appears. Click it, then click the **test** job.
5. Expand the step **Steps 1-2: get a token from GitHub and show its claims**.
6. Copy the `sub` value it prints, and check the `iss` line. It should be
   `https://token.actions.flyontario-emu.ghe.com`, the same issuer `setup.sql` uses.
   If it's different (for example, with an extra path at the end because
   your enterprise customized it), use exactly what's printed.

The step **Steps 3-6: log in to Snowflake with the token** fails because
Snowflake doesn't know this subject yet.

### 5. Check the subject

Look at the `sub` you copied:

- **If it starts with `repo:`**, for example
  `repo:your-org/snowflake-wif-test:ref:refs/heads/main`, it's unique to this
  repo. Go to step 6.
- **If it starts with `repository_owner_id:`**, your org has a custom subject
  rule. If you've already given that subject to `svc_operations_user`,
  this repo would match production. GitHub has no website setting for
  this, so run these commands (PowerShell, with the GitHub CLI), then
  repeat step 4. The `--hostname` flag points the CLI at your GHE.com
  instance instead of github.com:

  ```powershell
  gh auth login --hostname flyontario-emu.ghe.com
  '{"use_default": false, "include_claim_keys": ["repository_owner_id", "repository_id", "context"]}' |
    gh api --hostname flyontario-emu.ghe.com --method PUT /repos/<ORG>/snowflake-wif-test/actions/oidc/customization/sub --input -
  ```

  On an Enterprise Managed Users (EMU) setup, an enterprise admin may need
  to run this for you.

  The new `sub` includes this repo's ID, so it can never match production.

### 6. Create the Snowflake side

1. In Snowsight, open a new SQL worksheet.
2. Paste in the contents of `setup.sql`.
3. Replace the two placeholders (the issuer is already set to `https://token.actions.flyontario-emu.ghe.com`):
   - `SUBJECT`: your `sub` from step 4 (or 5)
   - `OIDC_AUDIENCE_LIST`: exactly the same audience as the `SNOWFLAKE_AUDIENCE` variable
4. Click the arrow next to **Run** → **Run All**.

**Check:** the last statement's results show your issuer and subject.

### 7. Second run: it should work

1. Go back to **Actions** → **test-wif-connection** → **Run workflow** on `main`.
2. When the run finishes (green check), click it.

The run's **Summary** page shows two tables: the token's claims, and the
Snowflake session (user `SVC_WIF_TEST`, role `WIF_TEST_ROLE`, and the
authorization checks).

Then paste `check_logins.sql` into a Snowsight worksheet and run it to see
the same login from Snowflake's side. Look for `WORKLOAD_IDENTITY` in
`first_authentication_factor`.

## Experiments to try

Run each one, look at the error, then undo it before the next.

| Experiment | How (on GitHub or in Snowsight) | Undo | What you'll learn |
| --- | --- | --- | --- |
| Run from a branch | On the **Code** tab, click the **main** dropdown, type `test`, and click **Create branch: test from main**. Then **Run workflow** with **Branch: test** | Delete the branch on the **Branches** page | The `sub` ends in `refs/heads/test`, so Snowflake refuses. Only `main` gets in. |
| Wrong audience | **Settings** → **Secrets and variables** → **Actions** → **Variables** → edit `SNOWFLAKE_AUDIENCE` to `snowflakecomputing.com` | Edit it back | Tokens are bound to one account. |
| No token permission | Open `.github/workflows/test-wif.yml`, click the pencil icon, delete the `id-token: write` line, commit | Edit the file and add it back | GitHub won't issue a token at all. |
| Remove a key | In Snowsight: `REVOKE USAGE ON WAREHOUSE wif_test_wh FROM ROLE wif_test_role;` | `GRANT USAGE ON WAREHOUSE wif_test_wh TO ROLE wif_test_role;` | Login still works, but queries fail. Authentication and authorization are separate. |

## If the login fails

Snowflake's error message names the token's issuer and subject. Compare them
with what you put in `setup.sql`:

| Error mentions | Fix |
| --- | --- |
| issuer `https://token.actions.githubusercontent.com` in `setup.sql`, but `https://token.actions.flyontario-emu.ghe.com` in the error | You ran an older `setup.sql`. Run `cleanup.sql`, then this repo's `setup.sql` |
| A subject that differs from `SUBJECT` in `setup.sql` | Copy the subject from the error or the run log exactly, run `cleanup.sql`, then `setup.sql` again |
| Issuer and subject both match | Check the audience: `SNOWFLAKE_AUDIENCE` must equal `OIDC_AUDIENCE_LIST` exactly |

## Cleanup

1. In Snowsight, run `cleanup.sql`.
2. On GitHub, go to the repo's **Settings**, scroll to the **Danger Zone**,
   click **Delete this repository**, and follow the prompts.