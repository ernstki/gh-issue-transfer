#!/usr/bin/env bash
set -euo pipefail

# Replace with your actual source repository
SOURCE_REPO="source/repo"
TARGET_REPO="destination/repo"

echo "Syncing labels from $SOURCE_REPO to $TARGET_REPO..."
# Fetch all labels from the source repo using the API
gh api "repos/$SOURCE_REPO/labels" --paginate > labels.json

jq -c '.[]' labels.json | while read -r label; do
    name=$(echo "$label" | jq -r '.name')
    color=$(echo "$label" | jq -r '.color')
    desc=$(echo "$label" | jq -r '.description // ""')
    
    echo "Syncing label: $name"
    # Attempt to create the label. If it already exists, fall back to editing it to ensure color/desc match.
    gh api --method POST "repos/$TARGET_REPO/labels" \
        -f name="$name" -f color="$color" -f description="$desc" --silent 2>/dev/null || \
    gh api --method PATCH "repos/$TARGET_REPO/labels/$name" \
        -f color="$color" -f description="$desc" --silent 2>/dev/null || true
done

echo "Fetching issues from $SOURCE_REPO..."
# Fetch up to 1000 issues (adjust limit if needed)
gh issue list -R "$SOURCE_REPO" --state all --json number,title,body,labels,assignees --limit 1000 > issues.json

# Reverse the array to create oldest issues first, helping to align issue numbers
jq -c 'reverse | .[]' issues.json | while read -r issue; do
    number=$(echo "$issue" | jq -r '.number')
    title=$(echo "$issue" | jq -r '.title')
    body=$(echo "$issue" | jq -r '.body')
    
    # Prepend original issue number to the body to preserve the reference
    printf -v body "*Original issue: %s#%s*\n\n%s" "$SOURCE_REPO" "$number" "$body"
    
    labels=$(echo "$issue" | jq -r '.labels[].name // empty' | paste -sd, -)
    assignees=$(echo "$issue" | jq -r '.assignees[].login // empty' | paste -sd, -)
    
    echo "Transferring issue #$number: $title"
    
    # Build the create command
    cmd=(gh issue create -R "$TARGET_REPO" --title "$title" --body "$body")
    
    if [ -n "$labels" ]; then
        cmd+=(--label "$labels")
    fi
    
    if [ -n "$assignees" ]; then
        cmd+=(--assignee "$assignees")
    fi
    
    # Create issue and extract the new issue number from the returned URL
    new_issue_url=$("${cmd[@]}")
    new_issue_number=$(echo "$new_issue_url" | awk -F'/' '{print $NF}')
    
    echo " -> Created as issue #$new_issue_number in target repo."
    
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
        
        gh issue comment "$new_issue_number" -R "$TARGET_REPO" --body "$new_comment_body"
        echo "   -> Transferred comment by $comment_author"
    done
    
    # Optional: sleep for a few seconds to avoid hitting GitHub API rate limits
    sleep 2
done

# Cleanup temporary files
rm -f issues.json comments.json labels.json
echo "Transfer complete!"
