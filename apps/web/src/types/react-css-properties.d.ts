/**
 * Lets `style={{ '--md-icon-size': '20px' }}` type-check.
 *
 * The Material 3 components are driven by CSS custom properties (the same
 * `--md-*` token names the native app's theme sets), so setting them from a
 * `style` prop is routine here. React models `CSSProperties` as a closed set,
 * and merging into it is the supported way to open it up — the alternative
 * would be casting every style object.
 */
import 'react'

declare module 'react' {
    interface CSSProperties {
        [customProperty: `--${string}`]: string | number | undefined
    }
}
