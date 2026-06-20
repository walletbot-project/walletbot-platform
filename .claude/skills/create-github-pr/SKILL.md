---
name: create-github-pr
description: Creates a GitHub Pull Request from the changes on the current branch. Analyzes commits and diffs, fills in all sections of the PULL_REQUEST_TEMPLATE.md (Description, Screenshots/Demo, Before Testing, Acceptance Tests), and opens the PR via gh CLI. Use when the user says "create a PR", "open a pull request", "ship this", or similar.
---

# Create GitHub PR

Analyze the current branch and create a well-crafted GitHub Pull Request that fills every section of the project's PR template.

## Workflow

### 1. Gather context

Run these in parallel:

```bash
git status
git log main..HEAD --oneline
git diff main..HEAD
cat .github/PULL_REQUEST_TEMPLATE.md
```

Also check if the branch name contains a Linear ticket ID (e.g. `WAL-123`) — if so, use it to enrich the description.

### 2. Confirm screenshots

**Always ask the user** before creating the PR:

> "Do you have screenshots or a screen recording to include in the PR? If yes, paste them now. If this is a backend-only change with no visual output, just say so."

Wait for the answer. Do not skip this step — the Screenshots / Demo section must be filled meaningfully, not left as a placeholder.

### 3. Draft the PR body

Write the entire PR body in **Spanish**.

Fill every section of `.github/PULL_REQUEST_TEMPLATE.md` as follows:

#### Description
- Concisely state **what** changed — a few short bullet points is enough.
- Do not explain motivation, context, or reasoning. Just describe the changes.
- If the branch name contains a Linear ticket ID, mention it (e.g. "Parte de WAL-123").

#### Screenshots / Demo
- If the user provided screenshots/recordings: embed them.
- If it's a backend-only or non-visual change: write a short note explaining why there is no screenshot (e.g. "Backend-only change — no UI affected.") and show relevant log output or a curl/API response if helpful.
- Never leave the section empty or with the original comment placeholder.

#### Before Testing
Derive from the diff what a reviewer needs to set up:
- New environment variables → list them and where to find the values
- Database migrations or Convex schema changes → list the command to run
- New dependencies → note `pnpm install`
- Seed data or fixtures needed → describe them
- Feature flags or config to enable
- If none of the above apply, write "No special setup required — standard `pnpm dev` is enough."

#### Acceptance Tests
Write a concrete, checkbox-style test plan derived from the actual changes. Each item should:
- Name a specific user action or system behavior
- State the expected outcome
- Cover the happy path AND at least one error/edge case if applicable

Example format:
```
- [ ] Navigate to X → Y screen loads without errors
- [ ] Submit form with valid data → success toast appears and record is saved
- [ ] Submit form with missing required field → inline validation error shown
- [ ] Reload the page → state is preserved / data is still visible
```

Do not write vague items like "Feature works correctly." Be specific.

### 4. Determine the base branch

- Default base: `main`
- If the branch was cut from another feature branch and that branch is still open, use it as the base instead. Check with `git log --oneline main..HEAD` to understand the commit history.

### 5. Push and create the PR

```bash
git push -u origin HEAD
gh pr create \
  --title "<concise title under 70 chars>" \
  --base main \
  --body "$(cat <<'EOF'
<filled PR body>
EOF
)"
```

Title rules:
- Under 70 characters
- Use imperative mood: "Add X", "Fix Y", "Refactor Z"
- Include the Linear ticket ID as a prefix if applicable: `WAL-123: Add expense categories`
- Do not use "feat:", "fix:" prefixes (those belong in commit messages, not PR titles)

### 6. Return the PR URL

After creation, output the PR URL so the user can open it immediately.

## Rules

- **Never create the PR without confirming screenshots** with the user first.
- **Never leave template sections with their original comment placeholders** — every section must have real content.
- **Never push to `main` directly** — always create a PR.
- If `gh` CLI is not authenticated, tell the user to run `gh auth login` before proceeding.
- If there are uncommitted changes, warn the user and ask whether to commit them first or proceed without them.
- Keep the PR title short and human-readable — no auto-generated noise.
