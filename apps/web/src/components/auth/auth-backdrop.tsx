/**
 * The painted background behind every auth screen, porting the native
 * `_LoginBackdropPainter` (apps/native/lib/screens/login.dart).
 *
 * The grid and the two radial accents are CSS (see the `auth-backdrop`
 * utility); only the ribbon needs geometry CSS can't express, so it is an SVG
 * stretched over the viewport with a non-scaling 18px stroke — the same
 * constant width the painter uses.
 */
export function AuthBackdrop() {
    return (
        <div
            aria-hidden
            className="auth-backdrop pointer-events-none fixed inset-0 -z-10"
        >
            <svg
                aria-hidden="true"
                className="size-full"
                viewBox="0 0 100 100"
                preserveAspectRatio="none"
                focusable="false"
            >
                <path
                    d="M -5 68 Q 32 53 66 64 Q 86 71 105 56"
                    fill="none"
                    stroke="var(--md-sys-color-primary)"
                    strokeOpacity={0.12}
                    strokeWidth={18}
                    vectorEffect="non-scaling-stroke"
                />
            </svg>
        </div>
    )
}
