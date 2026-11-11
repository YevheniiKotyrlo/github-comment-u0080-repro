#!/usr/bin/env bash
# Posts sent-body.md as a comment on an issue twice, through `gh issue comment` (GraphQL addComment) and through the
# REST API, and, where the repository has discussions on, as a discussion titled with its first line; reads each back
# and prints every line stored other than as it was sent.
# Exit 1 while a post is stored with a line other than the one sent, 0 once every post is stored as sent, 2 when a step fails.
set -u

usage="usage: ./reproduce.sh OWNER/REPO ISSUE_NUMBER"
repository="${1:?${usage}}"
issue="${2:?${usage}}"
# gh is handed a path relative to the reproducer, which reads the same on every system.
cd "$(dirname "$0")" || exit 2
sent_file="sent-body.md"

if ! gh_version="$(gh --version 2>&1)"; then
    echo "step failed: gh --version: ${gh_version}"
    exit 2
fi
system="$(uname -sm)"
echo "${system}, ${gh_version%%$'\n'*}"
if ! sent="$(cat "${sent_file}")"; then
    echo "step failed: reading ${sent_file}"
    exit 2
fi
title="${sent%%$'\n'*}"

posts=0
changed_posts=0

# Prints each line of the second argument that differs from the same line of the first, and counts the post as changed.
compare() {
    local expected="$1" stored="${2//$'\r'/}" expected_line stored_line line_number=0 changed=0 expected_lines stored_lines
    while IFS= read -r expected_line <&3 && IFS= read -r stored_line <&4; do
        line_number=$((line_number + 1))
        if [[ "${expected_line}" != "${stored_line}" ]]; then
            echo "  line ${line_number} sent:   ${expected_line}"
            echo "  line ${line_number} stored: ${stored_line}"
            changed=$((changed + 1))
        fi
    done 3<<<"${expected}" 4<<<"${stored}"
    expected_lines="$(wc -l <<<"${expected}")"
    stored_lines="$(wc -l <<<"${stored}")"
    echo "  ${changed} of ${expected_lines// /} lines stored other than sent; ${#expected} characters sent, ${#stored} stored, ${stored_lines// /} lines"
    posts=$((posts + 1))
    if [[ "${changed}" -gt 0 || "${#expected}" -ne "${#stored}" ]]; then
        changed_posts=$((changed_posts + 1))
    fi
}

compare_comment() {
    local url="$1" id stored
    if [[ ! "${url}" =~ \#issuecomment-([0-9]+)$ ]]; then
        echo "step failed: no comment address in: ${url}"
        exit 2
    fi
    id="${BASH_REMATCH[1]}"
    if ! stored="$(gh api "repos/${repository}/issues/comments/${id}" --jq .body 2>&1)"; then
        echo "step failed: reading comment ${id}: ${stored}"
        exit 2
    fi
    compare "${sent}" "${stored}"
}

echo "== gh issue comment ${issue} --repo ${repository} --body-file sent-body.md, which posts through GraphQL addComment"
if ! graphql_url="$(gh issue comment "${issue}" --repo "${repository}" --body-file "${sent_file}" 2>&1)"; then
    echo "step failed: gh issue comment: ${graphql_url}"
    exit 2
fi
graphql_url="${graphql_url##*$'\n'}"
echo "${graphql_url}"
compare_comment "${graphql_url}"

echo "== gh api -X POST repos/${repository}/issues/${issue}/comments -f body=\"\$(cat sent-body.md)\", the REST API"
if ! rest_url="$(gh api -X POST "repos/${repository}/issues/${issue}/comments" -f body="${sent}" --jq .html_url 2>&1)"; then
    echo "step failed: POST issues/${issue}/comments: ${rest_url}"
    exit 2
fi
echo "${rest_url}"
compare_comment "${rest_url}"

echo "== GraphQL createDiscussion, titled with sent-body.md's first line, its body the whole file"
if ! target="$(gh api graphql -f owner="${repository%%/*}" -f name="${repository#*/}" -f query="query(\$owner: String!, \$name: String!) { repository(owner: \$owner, name: \$name) { id hasDiscussionsEnabled discussionCategories(first: 1) { nodes { id } } } }" --jq '.data.repository | "\(.hasDiscussionsEnabled) \(.id) \(.discussionCategories.nodes[0].id // "none")"' 2>&1)"; then
    echo "step failed: reading ${repository}'s discussion categories: ${target}"
    exit 2
fi
read -r discussions_on repository_id category_id <<<"${target}"
if [[ "${discussions_on}" != true || "${category_id}" == none ]]; then
    echo "  skipped: ${repository} has discussions off"
else
    if ! number="$(gh api graphql -f repository="${repository_id}" -f category="${category_id}" -f title="${title}" -f body="${sent}" -f query="mutation(\$repository: ID!, \$category: ID!, \$title: String!, \$body: String!) { createDiscussion(input: {repositoryId: \$repository, categoryId: \$category, title: \$title, body: \$body}) { discussion { number } } }" --jq .data.createDiscussion.discussion.number 2>&1)"; then
        echo "step failed: createDiscussion: ${number}"
        exit 2
    fi
    echo "https://github.com/${repository}/discussions/${number}"
    if ! stored_title="$(gh api graphql -f owner="${repository%%/*}" -f name="${repository#*/}" -F number="${number}" -f query="query(\$owner: String!, \$name: String!, \$number: Int!) { repository(owner: \$owner, name: \$name) { discussion(number: \$number) { title } } }" --jq .data.repository.discussion.title 2>&1)" ||
        ! stored_body="$(gh api graphql -f owner="${repository%%/*}" -f name="${repository#*/}" -F number="${number}" -f query="query(\$owner: String!, \$name: String!, \$number: Int!) { repository(owner: \$owner, name: \$name) { discussion(number: \$number) { body } } }" --jq .data.repository.discussion.body 2>&1)"; then
        echo "step failed: reading discussion ${number}"
        exit 2
    fi
    echo "  title:"
    compare "${title}" "${stored_title}"
    echo "  body:"
    compare "${sent}" "${stored_body}"
fi

if [[ "${changed_posts}" -eq 0 ]]; then
    echo "SUMMARY: all ${posts} posts are stored as sent"
    exit 0
fi
echo "SUMMARY: ${changed_posts} of ${posts} posts are stored other than sent"
exit 1
