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

To run the tests locally, use `tests/run.sh` for the unit tests, or
`RUN_NETWORK_TESTS=1 tests/run.sh` to add the real-TruffleHog tests (needs network).
