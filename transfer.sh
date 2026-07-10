#!/usr/bin/env bash
REPO=destination/repo

jq -c '.[]' issues.json | while read -r issue; do
    label=$(echo "$issue" | jq -r '.[].name' | paste -sd, -)
    gh issue create -R $REPO \
        --title "$(echo "$issue" | jq -r .title)" \
        --body "$(echo "$issue" | jq -r .body)" \
        --label "$(echo "$issue" | jq -r '.[].name' | paste -sd, -)"
    break
done
