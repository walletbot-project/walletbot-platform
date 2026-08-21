import { createContext } from 'react'
import type { VoiceSession } from '@/hooks/use-voice'

/**
 * The one Live session for the signed-in account, shared by every route.
 *
 * It is a context rather than page state because the assistant conversation
 * has to outlive the `/add` route — see `VoiceProvider`.
 */
export const VoiceSessionContext = createContext<VoiceSession | null>(null)
