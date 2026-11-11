# github-comment-u0080-repro

Checks whether an issue comment, and a discussion's title and body, holding `\u0080` as text are stored as they were sent.

```bash
./reproduce.sh OWNER/REPO ISSUE_NUMBER
```

It posts `sent-body.md`, which holds `\u0000`, `\u001f`, `\u0041`, `\u007f`, `\u0080`, `\u0081`, `\u009f`, `\u00a0`, `\u00ff`, `\u0100` and `\uffff` as text on its first line and once more one per line in a fenced code block:

- as a comment on the issue through `gh issue comment --body-file`, which posts with GraphQL's `addComment`;
- as a comment on the issue through the REST API's `POST /repos/{owner}/{repo}/issues/{issue_number}/comments`;
- where the repository has discussions on, as a discussion in its first category through GraphQL's `createDiscussion`, titled with the file's first line.

It reads each back, the comments with `GET /repos/{owner}/{repo}/issues/comments/{comment_id}` and the discussion through GraphQL, and prints every line stored other than as it was sent. It exits 1 while a post is stored with a line other than the one sent, 0 once every post is stored as sent, 2 when a step fails. It needs `gh` signed in with a token that can comment on the issue and start a discussion.

Issue #1 and the discussions of this repository hold what its runs posted.
