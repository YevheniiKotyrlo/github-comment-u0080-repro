# github-comment-u0080-repro

Checks whether an issue comment whose body holds `\u0080` as text is stored as it was sent.

```bash
./reproduce.sh OWNER/REPO ISSUE_NUMBER
```

It posts `sent-body.md`, which holds `\u0000`, `\u001f`, `\u0041`, `\u007f`, `\u0080`, `\u0081`, `\u009f`, `\u00a0`, `\u00ff`, `\u0100` and `\uffff` as text on one line and once more one per line in a fenced code block, as a comment on the issue twice: through `gh issue comment --body-file`, which posts with GraphQL's `addComment`, and through the REST API's `POST /repos/{owner}/{repo}/issues/{issue_number}/comments`. It reads each comment back with `GET /repos/{owner}/{repo}/issues/comments/{comment_id}` and prints every line stored other than as it was sent. It exits 1 while a comment is stored with a line other than the one sent, 0 once both are stored as sent, 2 when a step fails. It needs `gh` signed in with a token that can comment on the issue.

Issue #1 of this repository holds the comments its runs posted.
