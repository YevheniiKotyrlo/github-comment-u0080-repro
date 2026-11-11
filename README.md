# github-comment-u0080-repro

Checks whether `gh` reads an issue comment holding `\u0080` and other backslash-u text as GitHub returns it.

```bash
./reproduce.sh OWNER/REPO ISSUE_NUMBER
```

It posts `sent-body.md`, which holds `\u0000`, `\u001f`, `\u0041`, `\u007f`, `\u0080`, `\u0081`, `\u009f`, `\u00a0`, `\u00ff`, `\u0100` and `\uffff` as text on its first line and once more one per line in a fenced code block, as a comment on the issue with `gh issue comment --body-file`. It reads the comment back from `GET /repos/{owner}/{repo}/issues/comments/{comment_id}` with `curl` and `jq`, checks that GitHub returns it as sent, reads it again with `gh api`, and prints every line `gh` reads other than GitHub returns it. It exits 1 while `gh` reads a line other than GitHub returns, 0 once it reads the comment as GitHub returns it, 2 when a step fails or GitHub returns the comment other than as it was sent. The repository must be public, since `curl` reads it without a token, and `gh` signed in with a token that can comment on the issue.

Issue #1 of this repository holds the comments its runs posted.
