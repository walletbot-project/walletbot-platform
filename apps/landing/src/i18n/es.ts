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
 * Every product claim here is backed by shipped code (voice agent, sync engine,
 * local accounts, multi-currency, dashboard, saved filters). Claims about
 * local-only mode are deliberately scoped to *financial records*, matching
 * docs/legal — the app still sends usage/diagnostic telemetry.
 */
export const es = {
    meta: {
        title: 'Wallet Bot — Tus gastos, registrados con la voz',
        description:
            'Gestor de gastos personales simple, rápido y moderno. Hablá y tus gastos quedan registrados: sin planillas, sin formularios tediosos. Solo una conversación.',
    },

    nav: {
        skipToContent: 'Saltar al contenido',
        languageLabel: 'Idioma',
        features: 'Funciones',
        download: 'Descargar',
        openApp: 'Abrir la app web',
    },

    hero: {
        badge: 'Modo de voz en vivo',
        headline: 'Hablá. Ya quedó registrado.',
        subheadline:
            'Wallet Bot es un gestor de gastos personales con modo de voz en vivo: contale qué gastaste y el asistente lo anota por vos. Sin planillas. Sin formularios. Solo una conversación.',
        ctaWeb: 'Probar la beta web',
        ctaFeatures: 'Ver funciones',
    },

    // Static illustration of the real voice flow: the assistant registers the
    // movement and the chat shows an editable action card.
    demo: {
        listening: 'Escuchando',
        userSays: '«Pagué 8.500 pesos en el supermercado con la tarjeta»',
        actionType: 'Gasto',
        actionName: 'Supermercado',
        actionAccount: 'Tarjeta',
        actionAmount: '$8.500',
        logged: 'Registrado — tocá la tarjeta para corregir lo que sea',
    },

    features: {
        title: 'Simple a propósito',
        subtitle:
            'Lo que necesitás para saber en qué se va la plata — y nada más.',
        items: {
            voice: {
                title: 'Asistente de voz en vivo',
                body: 'Hablale y queda anotado: crea cuentas y categorías sobre la marcha, y cada acción aparece como una tarjeta editable para corregir al toque.',
                types: {
                    expense: 'Gastos',
                    income: 'Ingresos',
                    transfer: 'Transferencias',
                    adjustment: 'Ajustes de saldo',
                },
            },
            offline: {
                title: 'Funciona sin conexión',
                body: 'La app móvil guarda todo en tu teléfono y sincroniza sola entre tus dispositivos cuando volvés a tener red.',
            },
            local: {
                title: 'Modo local, sin cuenta',
                body: 'Usá la app móvil sin registrarte: tus registros financieros se quedan en tu dispositivo.',
            },
            fast: {
                title: 'Rápida de verdad',
                body: 'Sin recargas ni esperas: registrás algo — vos o el asistente — y aparece al instante en listas, saldos y gráficos.',
            },
            currencies: {
                title: 'Multi-moneda',
                body: 'Cuentas en más de 50 monedas, transferencias entre monedas con tipo de cambio, y totales siempre separados por moneda.',
            },
            dashboard: {
                title: 'Inicio a tu medida',
                body: 'Armá el inicio de la app móvil con widgets: estadísticas, listas y gráficos de torta, barras o líneas. El asistente también puede armarlo por vos.',
            },
            filters: {
                title: 'Filtros con memoria',
                body: 'Buscá por texto, combiná condiciones y guardá tus vistas favoritas para volver a ellas con un toque.',
            },
            bilingual: {
                title: 'Español e inglés',
                body: 'La app y el asistente hablan los dos idiomas. Cambiá cuando quieras, incluso en medio de una conversación.',
            },
        },
    },

    download: {
        title: 'Disponible donde estés',
        subtitle: 'Llevala en el teléfono o abrila en el navegador.',
        android: {
            lead: 'Disponible en',
            name: 'Google Play',
            note: 'App para Android',
            cta: 'Descargar',
        },
        ios: {
            lead: 'Próximamente en',
            name: 'App Store',
            note: 'App para iPhone',
            badge: 'Muy pronto',
        },
        web: {
            name: 'App web',
            note: 'app.walletbot.live',
            badge: 'Beta',
            cta: 'Abrir',
        },
    },

    footer: {
        tagline: 'Gestor de gastos personales, conversacional y simple.',
        privacy: 'Política de Privacidad',
        terms: 'Términos y Condiciones',
        copyright: (p: { year: number }) => `© ${p.year} Wallet Bot`,
    },

    legal: {
        privacy: {
            title: 'Política de Privacidad',
            description:
                'Cómo Wallet Bot recolecta, usa y protege tus datos personales.',
        },
        terms: {
            title: 'Términos y Condiciones',
            description: 'Condiciones de uso del servicio Wallet Bot.',
        },
        backHome: 'Volver al inicio',
    },
}

export type Messages = typeof es
