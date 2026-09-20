// Single source of truth for the Live session constants shared by the token
// mint (packages/backend/convex/live/createToken.ts) and the native client's
// setup frame (via the generated apps/native/lib/voice/agent_generated.dart —
// run `pnpm run generate:agent` after changing these).
//
// Bumping the model or voice here propagates to both sides in one change,
// instead of silently desyncing the backend mint from native's setup frame.

export const AGENT_MODEL = 'gemini-3.8-live'

export const AGENT_VOICE_NAME = 'Rasalgethi' // Enceladus
