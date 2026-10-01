const STORAGE_KEY = 'voice_microphone_device'

/** Browser/device preference; never restores recording or permission. */
export function readMicrophonePreference(): string {
    try {
        return localStorage.getItem(STORAGE_KEY) ?? ''
    } catch {
        return ''
    }
}

export function writeMicrophonePreference(deviceId: string): void {
    try {
        localStorage.setItem(STORAGE_KEY, deviceId)
    } catch {
        // Restricted storage must not prevent microphone selection.
    }
}
