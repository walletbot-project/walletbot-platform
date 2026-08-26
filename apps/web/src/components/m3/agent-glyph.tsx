import { useId } from 'react'
import { cn } from '@/lib/utils'

type AgentGlyphProps = {
    /** Box size in pixels. */
    size?: number
    className?: string
}

/**
 * The voice-agent glyph: a speech bubble with a microphone overlapping its
 * lower-right corner. Mirrors native's `_VoiceFabIcon`
 * (apps/native/lib/main.dart), which draws the same artwork from
 * `assets/agent-glyph.svg`.
 *
 * Purely decorative: label the interactive element that contains it.
 */
export function AgentGlyph({ size = 24, className }: AgentGlyphProps) {
    // Unique per instance, so two glyphs on a page can't punch each other's
    // holes. Colons are legal in an id but break `querySelector`.
    const maskId = `agent-glyph-cut-${useId().replace(/:/g, '')}`

    return (
        <svg
            aria-hidden="true"
            focusable="false"
            width={size}
            height={size}
            /* Cropped to the drawing's bounds, so it renders centred. */
            viewBox="90.5 -871 723 640"
            fill="currentColor"
            className={cn('shrink-0', className)}
        >
            <mask id={maskId}>
                {/* The stroke widens the mic into a ~1px gap in the bubble. */}
                <rect x="0" y="-960" width="960" height="960" fill="#fff" />
                <g transform="translate(396 -166) scale(0.55)">
                    <path
                        d="M480-400q-50 0-85-35t-35-85v-240q0-50 35-85t85-35q50 0 85 35t35 85v240q0 50-35 85t-85 35Zm-40 240v-83q-92-13-157.5-78T203-479q-2-17 9-29t28-12q17 0 28.5 11.5T284-480q14 70 69.5 115T480-320q72 0 127-45.5T676-480q4-17 15.5-28.5T720-520q17 0 28 12t9 29q-14 91-79 157t-158 79v83q0 17-11.5 28.5T480-120q-17 0-28.5-11.5T440-160Z"
                        fill="#000"
                        stroke="#000"
                        strokeWidth={146}
                        strokeLinejoin="round"
                        strokeLinecap="round"
                    />
                </g>
            </mask>

            {/* Material Symbols Rounded — chat_bubble (outlined) */}
            <g mask={`url(#${maskId})`}>
                <g transform="translate(31.5 -210) scale(0.75)">
                    <path d="m240-240-92 92q-19 19-43.5 8.5T80-177v-623q0-33 23.5-56.5T160-880h640q33 0 56.5 23.5T880-800v480q0 33-23.5 56.5T800-240H240Zm-34-80h594v-480H160v525l46-45Zm-46 0v-480 480Z" />
                </g>
            </g>

            {/* Material Symbols Rounded — mic (fill 1) */}
            <g transform="translate(396 -166) scale(0.55)">
                <path d="M480-400q-50 0-85-35t-35-85v-240q0-50 35-85t85-35q50 0 85 35t35 85v240q0 50-35 85t-85 35Zm-40 240v-83q-92-13-157.5-78T203-479q-2-17 9-29t28-12q17 0 28.5 11.5T284-480q14 70 69.5 115T480-320q72 0 127-45.5T676-480q4-17 15.5-28.5T720-520q17 0 28 12t9 29q-14 91-79 157t-158 79v83q0 17-11.5 28.5T480-120q-17 0-28.5-11.5T440-160Z" />
            </g>
        </svg>
    )
}
