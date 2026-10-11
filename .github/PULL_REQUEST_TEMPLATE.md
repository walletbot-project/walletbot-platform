## Description

<!-- What changed and, more importantly, WHY. Include motivation, context, and any relevant trade-offs or decisions made. -->

## Screenshots / Demo

<!-- Add screenshots, screen recordings, or GIFs showing the feature or fix in action. For backend-only changes, show logs or API responses. -->

## Before Testing

<!-- List any setup steps the reviewer must complete before they can test this PR:
- Environment variables to set
- Seeds or migrations to run
- Feature flags to enable
- Dependencies to install
- etc. -->

<!-- Staging Google auth (delete when not applicable):
For Google sign-in to work on a staging/preview deployment, its redirect URI must be added to the
authorized redirect URIs of the OAuth client in Google Cloud Console:
https://console.cloud.google.com/auth/clients/885078793236-a9es85agobrqq27ft5o3ks9j66jnfnsg.apps.googleusercontent.com?authuser=1&project=wallet-bot-493021
Reviewer: if testing Google auth on staging, make sure the redirect URI is registered there first.
-->

<!-- SQLite / Drift checklist (delete when not applicable):
- Bump AppDatabase.schemaVersion for every schema change
- Add an explicit onUpgrade path that preserves existing local data
- Run dart run drift_dev make-migrations
- Regenerate test/generated_migrations/ from drift_schemas/app_database/
- Add migration schema + data-integrity tests
-->

## Acceptance Tests

<!-- Step-by-step instructions the reviewer should follow to verify the feature works correctly.
Be specific — include what to click, what to enter, and what the expected outcome is for each step. -->

- [ ] <!-- Step 1 -->
- [ ] <!-- Step 2 -->
- [ ] <!-- Step 3 -->
