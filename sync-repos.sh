#!/usr/bin/env bash
set -euo pipefail

local_branches=$(git branch --format='%(refname:strip=2)')

while IFS= read -r full_branch_name; do
    [[ "$full_branch_name" == */* ]] || continue

    repo="${full_branch_name%%/*}"
    branch_name="${full_branch_name#*/}"

    printf 'Syncing %s from %s/%s\n' "$full_branch_name" "$repo" "$branch_name"
    git switch "$full_branch_name"
    git pull "$repo" "$branch_name"
    git push
done <<< "$local_branches"
