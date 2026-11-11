#!/usr/bin/env bash
# Posts sent-body.md as a comment on an issue with `gh issue comment`, reads the comment back with curl and jq, which
# show what GitHub returns, and with `gh api`, and prints every line gh reads other than GitHub returns it.
# Exit 1 while gh reads a line other than the one GitHub returns, 0 once gh reads the comment as GitHub returns it, 2 when
# a step fails or GitHub returns the comment other than as it was sent.
set -u

usage="usage: ./reproduce.sh OWNER/REPO ISSUE_NUMBER, a public repository's issue, which curl reads without a token"
repository="${1:?${usage}}"
issue="${2:?${usage}}"
# gh is handed a path relative to the reproducer, which reads the same on every system.
cd "$(dirname "$0")" || exit 2
sent_file="sent-body.md"

if ! gh_version="$(gh --version 2>&1)" || ! curl_version="$(curl --version 2>&1)" || ! jq_version="$(jq --version 2>&1)"; then
    echo "step failed: gh, curl or jq is missing"
    exit 2
fi
system="$(uname -sm)"
curl_version="${curl_version%%$'\n'*}"
echo "${system}, ${gh_version%%$'\n'*}, ${curl_version%% (*}, ${jq_version}"
if ! sent="$(cat "${sent_file}")"; then
    echo "step failed: reading ${sent_file}"
    exit 2
fi

echo "== gh issue comment ${issue} --repo ${repository} --body-file sent-body.md"
if ! url="$(gh issue comment "${issue}" --repo "${repository}" --body-file "${sent_file}" 2>&1)"; then
    echo "step failed: gh issue comment: ${url}"
    exit 2
fi
url="${url##*$'\n'}"
echo "${url}"
if [[ ! "${url}" =~ \#issuecomment-([0-9]+)$ ]]; then
    echo "step failed: no comment address in: ${url}"
    exit 2
fi
id="${BASH_REMATCH[1]}"

echo "== curl -fsSL https://api.github.com/repos/${repository}/issues/comments/${id} | jq -r .body"
if ! response="$(curl -fsSL "https://api.github.com/repos/${repository}/issues/comments/${id}" 2>&1)"; then
    echo "step failed: reading comment ${id} with curl: ${response}"
    exit 2
fi
if ! returned="$(jq -r .body <<<"${response}" 2>&1)"; then
    echo "step failed: reading the body from what curl returned: ${returned}"
    exit 2
fi
returned="${returned//$'\r'/}"
if [[ "${returned}" != "${sent}" ]]; then
    printf '%s\n' "${returned}"
    echo "SUMMARY: GitHub returns the comment other than as it was sent"
    exit 2
fi
sent_lines="$(wc -l <<<"${sent}")"
echo "  GitHub returns the comment as sent: ${sent_lines// /} lines, ${#sent} characters"

echo "== gh api repos/${repository}/issues/comments/${id} --jq .body"
if ! read_back="$(gh api "repos/${repository}/issues/comments/${id}" --jq .body 2>&1)"; then
    echo "step failed: reading comment ${id} with gh: ${read_back}"
    exit 2
fi
read_back="${read_back//$'\r'/}"
changed=0
line_number=0
while IFS= read -r returned_line <&3 && IFS= read -r read_line <&4; do
    line_number=$((line_number + 1))
    if [[ "${returned_line}" != "${read_line}" ]]; then
        echo "  line ${line_number} GitHub: ${returned_line}"
        echo "  line ${line_number} gh:     ${read_line}"
        changed=$((changed + 1))
    fi
done 3<<<"${returned}" 4<<<"${read_back}"
echo "  ${changed} of ${sent_lines// /} lines read other than GitHub returns them; ${#returned} characters returned, ${#read_back} read"

if [[ "${changed}" -eq 0 && "${#returned}" -eq "${#read_back}" ]]; then
    echo "SUMMARY: gh reads the comment as GitHub returns it"
    exit 0
fi
echo "SUMMARY: gh reads ${changed} of ${sent_lines// /} lines of the comment other than GitHub returns them"
exit 1
