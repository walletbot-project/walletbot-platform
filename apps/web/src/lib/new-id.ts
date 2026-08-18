/**
 * Client-generated entity id, the app-wide convention for optimistic writes:
 * time-ordered with a short random suffix. One definition — this used to be
 * copy-pasted in six files.
 */
export function newId(): string {
    return `${Date.now()}${Math.random().toString(36).slice(2, 8)}`
}
