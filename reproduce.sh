#!/usr/bin/env bash
# Posts sent-body.md as a comment on an issue twice, through `gh issue comment` (GraphQL addComment) and through the
# REST API, reads each comment back through the REST API and prints every line stored other than as it was sent.
# Exit 1 while a comment is stored with a line other than the one sent, 0 once both are stored as sent, 2 when a step fails.
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

changed_paths=0

comment_id() {
    local url="$1"
    if [[ "${url}" =~ \#issuecomment-([0-9]+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

compare() {
    local url="$1" id stored sent_line stored_line line_number=0 changed=0 sent_lines stored_lines
    if ! id="$(comment_id "${url}")"; then
        echo "step failed: no comment address in: ${url}"
        exit 2
    fi
    if ! stored="$(gh api "repos/${repository}/issues/comments/${id}" --jq .body 2>&1)"; then
        echo "step failed: reading comment ${id}: ${stored}"
        exit 2
    fi
    stored="${stored//$'\r'/}"
    while IFS= read -r sent_line <&3 && IFS= read -r stored_line <&4; do
        line_number=$((line_number + 1))
        if [[ "${sent_line}" != "${stored_line}" ]]; then
            echo "  line ${line_number} sent:   ${sent_line}"
            echo "  line ${line_number} stored: ${stored_line}"
            changed=$((changed + 1))
        fi
    done 3<<<"${sent}" 4<<<"${stored}"
    sent_lines="$(wc -l <<<"${sent}")"
    stored_lines="$(wc -l <<<"${stored}")"
    echo "  ${changed} of ${sent_lines// /} lines stored other than sent; ${#sent} characters sent, ${#stored} stored, ${stored_lines// /} lines"
    if [[ "${changed}" -gt 0 || "${#sent}" -ne "${#stored}" ]]; then
        changed_paths=$((changed_paths + 1))
    fi
}

echo "== gh issue comment ${issue} --repo ${repository} --body-file sent-body.md, which posts through GraphQL addComment"
if ! graphql_url="$(gh issue comment "${issue}" --repo "${repository}" --body-file "${sent_file}" 2>&1)"; then
    echo "step failed: gh issue comment: ${graphql_url}"
    exit 2
fi
graphql_url="${graphql_url##*$'\n'}"
echo "${graphql_url}"
compare "${graphql_url}"

echo "== gh api -X POST repos/${repository}/issues/${issue}/comments -f body=\"\$(cat sent-body.md)\", the REST API"
if ! rest_url="$(gh api -X POST "repos/${repository}/issues/${issue}/comments" -f body="${sent}" --jq .html_url 2>&1)"; then
    echo "step failed: POST issues/${issue}/comments: ${rest_url}"
    exit 2
fi
echo "${rest_url}"
compare "${rest_url}"

if [[ "${changed_paths}" -eq 0 ]]; then
    echo "SUMMARY: both comments are stored as sent"
    exit 0
fi
echo "SUMMARY: ${changed_paths} of 2 comments are stored other than sent"
exit 1
