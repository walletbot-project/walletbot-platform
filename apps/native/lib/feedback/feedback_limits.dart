/// Feedback limits, mirroring `packages/shared/src/feedback.ts`.
///
/// A bundled copy, exactly like `legal/legal_versions.dart`: the server enforces
/// the real thing (it reads each upload's `_storage` metadata), these values
/// only stop the app from starting an upload that is going to be rejected.
/// Change them together with the TypeScript ones.
library;

/// Attachments allowed on a single submission.
const int feedbackMaxAttachments = 10;

/// Largest single attachment, in bytes (100 MB).
const int feedbackMaxAttachmentBytes = 100 * 1024 * 1024;

/// Longest feedback message, in characters.
const int feedbackMaxMessageLength = 4000;
