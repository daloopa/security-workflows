# security-workflows

Org-wide **required** security workflows for daloopa (EI-2229). The repo is public on
purpose: a ruleset can only require a public workflow on public repos. It holds workflow
definitions only, never secrets.

## secret-scan (TruffleHog)

The org ruleset `Secret scan - TruffleHog` (managed in `daloopa-terraform-live`,
`github/org-ruleset/`) enforces this check on every pull request to a default branch,
in every daloopa repo. It scans only the commits your PR adds.

| Result | Meaning | Merge |
|---|---|---|
| ❌ Verified credential | TruffleHog confirmed the credential works | **blocked** |
| ⚠️ Possible credential | Looks like a credential but could not be verified | allowed |
| ⚠️ Suppressed verified credential | A working credential on a `trufflehog:ignore` line | allowed; the reviewer decides |
| ❌ Scan inconclusive | The scan could not complete. This is **not** a finding | blocked; re-run the job |

The job summary lists every finding. Inline annotations are capped by GitHub, so the
summary is the complete list. The check never prints a secret's value.

### I was blocked. What now?

1. **Rotate the credential first.** It is already on a pushed branch, so treat it as leaked
   even if the PR is never merged.
2. Remove it from the branch **history**, not just the latest commit, because the scan
   checks every commit in the PR. Use an interactive rebase or a squash, then force-push
   the branch.
3. Load the value from the environment or the secret store instead.

### False positive?

- Add `trufflehog:ignore` in a comment on the line. The check passes, but the finding is
  listed for your reviewer, so expect to justify it.
- If a path legitimately holds credential-shaped test data, ask DevOps to add a regex to
  `EXCLUDE_PATHS` in `secret-scan.yml`. There is no per-repo exclude file, by design.
- If an outage blocks you ("inconclusive") and the merge is urgent, an org admin can merge
  through the ruleset bypass. The bypass is audit-logged.

### Public repos: push protection

Public daloopa repos also have GitHub push protection, which rejects a `git push` that
contains a known credential pattern before the credential becomes public. GitHub offers
anyone with write access a link to "allow" the secret. That makes push protection a speed
bump, not a gate. This check is the enforced control.

## jira-traceability

Required on the default branch of `daloopa-terraform-live` and `daloopa-infra-addons` (org ruleset
"Jira traceability (EI-1686 D18)", EI-2451). Every PR must derive from an existing Jira item:

- Start the **PR title** with the key, `KEY-123: what changes`, or the **branch** with it,
  `KEY-123/short-desc`. Any Jira project counts. Keys are case-sensitive: `ei-123` does not count.
- The canonical key (from the title if present, otherwise from the branch) must exist and **must not
  be Done**. A second, different key in the branch must also exist.
- No exceptions, automation included: automated PRs carry a standing ticket key.

### I was blocked. What now?

| Message | Fix |
|---|---|
| `no Jira key` | Edit the PR title to start with `KEY-123:`. The check re-runs on edit. |
| `KEY-123 not found` | Check the key. It may also be in a project the traceability account cannot see; ask DevOps. |
| `KEY-123 is Done` | Reopen the ticket, or create a follow-up ticket and use its key. |
| `inconclusive` | Jira was unreachable, or the credentials failed. This is not your PR: re-run the job, and ask DevOps if it persists. |

The job never checks out your code. It reads only the PR title and branch, and queries Jira with a
read-only service account. Its secrets are the org secrets `JIRA_TRACEABILITY_USER` and
`JIRA_TRACEABILITY_TOKEN`, visible only to the gated repos, plus two optional org variables:
`JIRA_TRACEABILITY_BASE_URL` and `JIRA_TRACEABILITY_AUTH_SCHEME` (`basic` or `bearer`). An Atlassian
service account only gets scoped tokens, and those go through the gateway
`https://api.atlassian.com/ex/jira/<cloudId>`.

## Changing a workflow

1. Open a PR here. `test.yml` must pass (`tests/run.sh`, actionlint, shellcheck).
2. After merge, create a new release branch `release/vN` at the merged commit, and
   optionally tag it `vX.Y.Z` for reference. `release/*` branches are frozen by the
   repo ruleset "Frozen release branches": they cannot be updated, force-pushed or
   deleted, so a published version never changes.
3. Open a PR to `daloopa-terraform-live` that changes `ref` in
   `github/org-ruleset/secret-scan.tf` to `refs/heads/release/vN`.

The org ruleset pins a **branch**, not a tag, because a ruleset pointed at a tag
ref never dispatches the workflow.

To run the tests locally, use `tests/run.sh` (secret-scan) and `tests/run_jira.sh` (jira-traceability) for the unit tests, or
`RUN_NETWORK_TESTS=1 tests/run.sh` to add the real-TruffleHog tests (needs network).
