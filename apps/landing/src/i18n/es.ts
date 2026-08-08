/**
 * Spanish catalog — the reference locale, mirroring
 * `apps/web/src/lib/i18n/es.ts`. Its shape defines `Messages`, so every other
 * catalog is checked against it at compile time: a missing key, a stray key, or
 * a value function whose parameters drifted is a type error, not a runtime
 * fallback.
 *
 * Entries that take values are functions, which keeps the parameter names and
 * types checked at the call site.
 *
 * Placeholder copy only — this exists to prove the i18n wiring end to end.
 */
export const es = {
    meta: {
        title: 'Wallet Bot',
        description: 'Llevá el control de tus gastos personales.',
    },

    nav: {
        skipToContent: 'Saltar al contenido',
        languageLabel: 'Idioma',
    },

    home: {
        headline: 'Wallet Bot',
        subheadline: 'Llevá el control de tus gastos personales.',
        setupNotice: (p: { locale: string }) =>
            `Andamio listo. Locale activo: ${p.locale}.`,
    },
}

export type Messages = typeof es
