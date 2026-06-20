// Tag color helpers. The palette is now unified across all entities — see
// entity-colors.ts. These re-exports keep the existing tag call sites working.
import {
    COLOR_OPTIONS,
    normalizeColor,
    TAG_DEFAULT_COLOR,
} from './entity-colors'

export { TAG_DEFAULT_COLOR }

export const TAG_COLOR_OPTIONS = COLOR_OPTIONS

export function normalizeTagColor(color: string | null | undefined): string {
    return normalizeColor(color, TAG_DEFAULT_COLOR)
}
