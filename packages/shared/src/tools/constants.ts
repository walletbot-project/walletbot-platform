// Single source of truth for the Live session constants shared by the token
// mint (packages/backend/convex/live/createToken.ts) and the native client's
// setup frame (via the generated apps/native/lib/voice/agent_generated.dart —
// run `pnpm run generate:agent` after changing these).
//
// This is the default for capable clients. The token mint also preserves
// older client compatibility and applies the server-side 3.1 rollback flag.
// Current clients use the model returned with their token for setup.

export const AGENT_MODEL = 'gemini-3.8-live'

export const AGENT_VOICE_NAME = 'Rasalgethi' // Enceladus
