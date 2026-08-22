import { useState } from 'react'
import { toast } from 'sonner'

type ToastCopy = {
    loading: string
    success: string
    error: string | ((error: unknown) => string)
}

/**
 * Runs a mutation behind a `toast.promise`, tracking its in-flight state.
 * `onSuccess` runs only when the promise resolves; a rejection is fully owned
 * by the toast — the old inline pattern re-`await`ed the promise without a
 * catch and leaked every failure as an unhandled rejection.
 */
export function useToastMutation() {
    const [pending, setPending] = useState(false)

    const run = async (
        promise: Promise<unknown>,
        copy: ToastCopy,
        onSuccess?: () => void,
    ) => {
        setPending(true)
        toast.promise(promise, copy)
        try {
            await promise
        } catch {
            // toast.promise owns the user-facing error state.
            return
        } finally {
            setPending(false)
        }
        onSuccess?.()
    }

    return { pending, run }
}
