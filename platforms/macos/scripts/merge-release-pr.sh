#!/usr/bin/env bash
set -euo pipefail

: "${GH_REPO:?GH_REPO is required}"
: "${RELEASE_PR:?RELEASE_PR is required}"

write_output() {
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        printf '%s\n' "$1" >> "$GITHUB_OUTPUT"
    fi
}

pr_number=$(jq -er '.number | select(type == "number")' <<< "$RELEASE_PR")
expected_head_branch=$(jq -er '.headBranchName | select(type == "string" and length > 0)' <<< "$RELEASE_PR")
if [[ "$expected_head_branch" != release-please--* ]]; then
    printf '%s\n' "Refusing to merge a non-Release-Please branch: $expected_head_branch" >&2
    exit 1
fi

pr_json=$(gh pr view "$pr_number" --repo "$GH_REPO" \
    --json number,state,isDraft,headRefName,headRefOid,baseRefName,baseRefOid,title)
state=$(jq -er .state <<< "$pr_json")
is_draft=$(jq -r .isDraft <<< "$pr_json")
head_branch=$(jq -er .headRefName <<< "$pr_json")
head_sha=$(jq -er .headRefOid <<< "$pr_json")
base_branch=$(jq -er .baseRefName <<< "$pr_json")
base_sha=$(jq -er .baseRefOid <<< "$pr_json")
title=$(jq -er .title <<< "$pr_json")

if [[ "$state" != OPEN || "$is_draft" != false || "$head_branch" != "$expected_head_branch" || "$base_branch" != main ]]; then
    printf '%s\n' "Release PR #$pr_number is not an open, mergeable Release Please PR against main." >&2
    exit 1
fi
if [[ ! "$head_sha" =~ ^[0-9a-f]{40}$ || ! "$base_sha" =~ ^[0-9a-f]{40}$ ]]; then
    printf '%s\n' "Release PR #$pr_number returned invalid commit metadata." >&2
    exit 1
fi

gh workflow run ci-macos.yml --repo "$GH_REPO" --ref "$head_branch"

max_polls=${METASEQUOIA_RELEASE_CI_MAX_POLLS:-150}
poll_interval=${METASEQUOIA_RELEASE_CI_POLL_INTERVAL:-2}
run_id=""
for ((attempt = 1; attempt <= max_polls; ++attempt)); do
    run_id=$(gh run list --repo "$GH_REPO" --workflow ci-macos.yml --branch "$head_branch" \
        --event workflow_dispatch --limit 20 --json databaseId,headSha \
        --jq "map(select(.headSha == \"$head_sha\")) | first | .databaseId // empty")
    if [[ -n "$run_id" ]]; then
        break
    fi
    sleep "$poll_interval"
done
if [[ -z "$run_id" ]]; then
    printf '%s\n' "Timed out waiting for CI to start for release PR #$pr_number at $head_sha." >&2
    exit 1
fi

gh run watch "$run_id" --repo "$GH_REPO" --exit-status --interval 10

current_base_sha=$(gh api "repos/$GH_REPO/git/ref/heads/$base_branch" --jq .object.sha)
if [[ "$current_base_sha" != "$base_sha" ]]; then
    printf '%s\n' "main advanced while release PR #$pr_number was being tested; leaving it open for the next release run."
    write_output "merged=false"
    exit 0
fi

current_pr_json=$(gh pr view "$pr_number" --repo "$GH_REPO" \
    --json state,isDraft,headRefName,headRefOid,baseRefName)
if [[ "$(jq -er .state <<< "$current_pr_json")" != OPEN || \
      "$(jq -r .isDraft <<< "$current_pr_json")" != false || \
      "$(jq -er .headRefName <<< "$current_pr_json")" != "$head_branch" || \
      "$(jq -er .headRefOid <<< "$current_pr_json")" != "$head_sha" || \
      "$(jq -er .baseRefName <<< "$current_pr_json")" != "$base_branch" ]]; then
    printf '%s\n' "Release PR #$pr_number changed after CI completed; refusing to merge it." >&2
    exit 1
fi

# The dispatched run above proves this commit builds, but main requires the pull_request checks
# specifically, and those are a separate set of runs started when the release pull request opened.
# They normally finish first; wait rather than letting a slow queue abort the release.
for ((attempt = 1; attempt <= max_polls; ++attempt)); do
    rollup=$(gh pr view "$pr_number" --repo "$GH_REPO" --json statusCheckRollup \
        --jq '[.statusCheckRollup[] | select(.conclusion != null or .status != null)]')
    pending=$(jq -r '[.[] | select((.conclusion // .status) as $s | $s == "QUEUED" or $s == "IN_PROGRESS" or $s == "PENDING" or $s == null)] | length' <<< "$rollup")
    failed=$(jq -r '[.[] | select((.conclusion // "") as $c | $c == "FAILURE" or $c == "TIMED_OUT" or $c == "CANCELLED" or $c == "ACTION_REQUIRED")] | length' <<< "$rollup")
    if [[ "$failed" != 0 ]]; then
        printf '%s\n' "Release PR #$pr_number has a failing check; refusing to merge it." >&2
        exit 1
    fi
    if [[ "$pending" == 0 ]]; then
        break
    fi
    sleep "$poll_interval"
done

gh pr merge "$pr_number" --repo "$GH_REPO" --squash --delete-branch \
    --match-head-commit "$head_sha" --subject "$title" \
    --body "Automated release PR merge after CI passed."
write_output "merged=true"
