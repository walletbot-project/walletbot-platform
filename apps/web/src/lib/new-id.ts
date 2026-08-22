/**
 * Client-generated entity id, the app-wide convention for optimistic writes.
 * One definition — this used to be copy-pasted in six files, under two
 * different schemes.
 *
 * UUID v4, the same scheme native settled on (`apps/native/lib/data/ids.dart`)
 * and the one the backend generates server-side and documents in every schema
 * (`// client-side uuid`). These ids sync between clients, so both ends have to
 * agree on what they look like.
 */
export function newId(): string {
    return crypto.randomUUID()
}
