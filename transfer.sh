#!/usr/bin/env bash
##
##  Transfer GitHub labels, issues, PRs and their comments from one repository
##  to another
##
##  Assisted-by:  gemini/gemini-3.1-pro-preview
##  Date:         9 July 2026
##  License:      Zero-Clause BSD (basically public domain)
##
set -euo pipefail

# Cleanup temporary files on exit
trap 'rm -f issues.json prs.json all_items.json comments.json labels.json' EXIT

# Replace with your actual source repository
SOURCE_REPO=${SOURCE_REPO:?Need a SOURCE repo in user-or-org/repo-name form}
TARGET_REPO=${TARGET_REPO:?Need a TARGET repo in user-or-org/repo-name form}

# Array of issue numbers to skip (e.g., SKIP_THESE_ISSUES=(1 2 5))
SKIP_THESE_ISSUES=()

if [ -n "${DRY_RUN:-}" ]; then
    echo "=== DRY RUN MODE ENABLED ==="
    echo "No changes will be made to $TARGET_REPO"
    echo "============================"
fi

echo "Syncing labels from $SOURCE_REPO to $TARGET_REPO..."
# Fetch all labels from the source repo using the API
gh api "repos/$SOURCE_REPO/labels" --paginate > labels.json

jq -c '.[]' labels.json | while read -r label; do
    name=$(echo "$label" | jq -r '.name')
    color=$(echo "$label" | jq -r '.color')
    desc=$(echo "$label" | jq -r '.description // ""')

    echo "Syncing label: $name"
    if [ -n "${DRY_RUN:-}" ]; then
        echo " [DRY RUN] Would create/update label: $name (color: $color, desc: $desc)"
    else
        # Attempt to create the label. If it already exists, fall back to editing
        # it to ensure color/desc match.
        gh api --method POST "repos/$TARGET_REPO/labels" \
            -f name="$name" -f color="$color" -f description="$desc" --silent 2>/dev/null || \
        gh api --method PATCH "repos/$TARGET_REPO/labels/$name" \
            -f color="$color" -f description="$desc" --silent 2>/dev/null || true
    fi
done

echo "Fetching issues and PRs from $SOURCE_REPO..."
# Fetch issues and PRs
gh issue list -R "$SOURCE_REPO" --state all --json number,title,body,labels,assignees,state --limit 1000 > issues.json
gh pr list -R "$SOURCE_REPO" --state all --json number,title,body,labels,assignees,state --limit 1000 > prs.json

# Inject type, merge, and sort by number
jq '[.[] | . + {type: "issue"}]' issues.json > issues_typed.json
jq '[.[] | . + {type: "pr"}]' prs.json > prs_typed.json
jq -s '.[0] + .[1] | sort_by(.number)' issues_typed.json prs_typed.json > all_items.json

# Cleanup intermediate typed files
rm -f issues_typed.json prs_typed.json

jq -c '.[]' all_items.json | while read -r item; do
    number=$(echo "$item" | jq -r '.number')
    type=$(echo "$item" | jq -r '.type')

    # Check if the issue/PR should be skipped
    skip=false
    for skip_num in "${SKIP_THESE_ISSUES[@]}"; do
        if [[ "$number" == "$skip_num" ]]; then
            skip=true
            break
        fi
    done

    if [ "$skip" = true ]; then
        echo "Skipping $type #$number as requested."
        continue
    fi

    title=$(echo "$item" | jq -r '.title')
    body=$(echo "$item" | jq -r '.body')
    state=$(echo "$item" | jq -r '.state')

    if [ "$type" == "pr" ]; then
        title="[Original PR] $title"
        printf -v body "*Original PR: %s#%s*\n\n%s" "$SOURCE_REPO" "$number" "$body"
        echo "Transferring PR #$number as dummy issue: $title"
    else
        printf -v body "*Original issue: %s#%s*\n\n%s" "$SOURCE_REPO" "$number" "$body"
        echo "Transferring issue #$number: $title"
    fi

    labels=$(echo "$item" | jq -r '.labels[].name // empty' | paste -sd, -)
    assignees=$(echo "$item" | jq -r '.assignees[].login // empty' | paste -sd, -)

    # Build the create command
    cmd=(gh issue create -R "$TARGET_REPO" --title "$title" --body "$body")

    if [ -n "$labels" ]; then
        cmd+=(--label "$labels")
    fi

    if [ -n "$assignees" ]; then
        cmd+=(--assignee "$assignees")
    fi

    if [ -n "${DRY_RUN:-}" ]; then
        echo " [DRY RUN] Would execute: ${cmd[*]}"
        new_issue_number="DRY_RUN_ID"
    else
        # Create issue and extract the new issue number from the returned URL
        new_issue_url=$("${cmd[@]}")
        new_issue_number=$(echo "$new_issue_url" | awk -F'/' '{print $NF}')
        echo " -> Created as issue #$new_issue_number in target repo."
    fi

    # Fetch and transfer comments
    gh api "repos/$SOURCE_REPO/issues/$number/comments" > comments.json

    jq -c '.[]' comments.json | while read -r comment; do
        comment_body=$(echo "$comment" | jq -r '.body')
        comment_author=$(echo "$comment" | jq -r '.user.login')

        if [ "$comment_author" == "ernstki" ]; then
            new_comment_body="$comment_body"
        else
            printf -v new_comment_body "*Original comment by @%s:*\n\n%s" "$comment_author" "$comment_body"
        fi

        if [ -n "${DRY_RUN:-}" ]; then
            echo "   [DRY RUN] Would transfer comment by $comment_author"
        else
            gh issue comment "$new_issue_number" -R "$TARGET_REPO" --body "$new_comment_body"
            echo "   -> Transferred comment by $comment_author"
        fi
    done

    # Close the issue if it was closed or merged in the original repo
    if [[ "$state" == "CLOSED" || "$state" == "MERGED" ]]; then
        if [ -n "${DRY_RUN:-}" ]; then
            echo "   [DRY RUN] Would close issue #$new_issue_number"
        else
            gh issue close "$new_issue_number" -R "$TARGET_REPO"
            echo "   -> Closed issue #$new_issue_number"
        fi
    fi

    # Optional: sleep for a few seconds to avoid hitting GitHub API rate limits
    if [ -z "${DRY_RUN:-}" ]; then
        sleep 2
    fi
done

echo "Transfer complete!"
