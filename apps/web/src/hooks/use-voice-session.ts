import { useContext } from 'react'
import type { VoiceSession } from '@/hooks/use-voice'
import { VoiceSessionContext } from '@/lib/voice-context'

/**
 * The account's Live session. Throws if used outside VoiceProvider.
 */
export function useVoiceSession(): VoiceSession {
    const ctx = useContext(VoiceSessionContext)
    if (!ctx) {
        throw new Error(
            'useVoiceSession must be used within a VoiceProvider (inside AuthGuard)',
        )
    }
    return ctx
}
