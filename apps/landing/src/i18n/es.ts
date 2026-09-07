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
 * local accounts, multi-currency, dashboard). Claims about local-only mode are
 * deliberately scoped to *financial records*, matching docs/legal — the app
 * still sends usage/diagnostic telemetry. The assistant's language claim is
 * deliberately hedged to "most languages": the UI ships es/en, but the agent
 * understands far more.
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
        requestAccess: 'Pedir acceso',
    },

    hero: {
        // Read by screen readers in place of the live-ledger pill; the amounts
        // are the rows scrolling through it, formatted for this locale.
        liveLedger: {
            label: 'Modo de voz en vivo, registrando gastos',
            amounts: [
                '−$8.500',
                '−$2.300',
                '−$15.900',
                '−$420.000',
                '+$1.500.000',
                '−$6.200',
            ],
        },
        headline: 'Hablá. Ya quedó registrado.',
        // Split so the middle part can be bolded. No part carries leading or
        // trailing spaces; Astro drops the whitespace around an expression, so
        // the markup puts the one space back explicitly.
        subheadline: {
            lead: 'Wallet Bot es un',
            highlight: 'gestor de gastos personales con modo de voz en vivo',
            rest: ': contale qué gastaste y el asistente lo anota por vos. Sin planillas. Sin formularios. Solo una conversación.',
        },
        ctaFeatures: 'Ver funciones',
    },

    // Verified numbers only: 52 currencies in the catalog, 4 movement types in
    // the transactions schema, es/en app UI (the assistant understands most
    // languages), offline-first native data layer.
    stats: {
        currencies: { value: '50+', label: 'monedas soportadas' },
        types: { value: '4', label: 'tipos de movimiento' },
        languages: { value: '2', label: 'idiomas en la app' },
        offline: { value: '100%', label: 'offline-first en el celular' },
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
                chip: 'Cero spinners',
            },
            currencies: {
                title: 'Multi-moneda',
                body: 'Cuentas en más de 50 monedas, transferencias entre monedas con tipo de cambio, y totales siempre separados por moneda.',
            },
            dashboard: {
                title: 'Inicio a tu medida',
                body: 'Armá el inicio de la app móvil con widgets: estadísticas, listas y gráficos de torta, barras o líneas. El asistente también puede armarlo por vos.',
            },
            // Not shipped. The card is on the page anyway because it is
            // labelled "próximamente" and styled as unavailable, the same
            // treatment the App Store badge gets — a stated roadmap item, not
            // a claim about what the app does today.
            whatsapp: {
                title: 'Registrá por WhatsApp',
                body: 'Mandá un mensaje o un audio por WhatsApp y el gasto queda anotado, sin abrir la app.',
                chip: 'Próximamente',
            },
            // The filters card is hidden on the home page for now — saved
            // filters aren't shipped in the app yet. Kept so the card can be
            // re-enabled without rewriting the copy.
            filters: {
                title: 'Filtros con memoria',
                body: 'Buscá por texto, combiná condiciones y guardá tus vistas favoritas para volver a ellas con un toque.',
            },
            bilingual: {
                title: 'Español, inglés y más',
                body: 'La app está en español e inglés, y el asistente entiende la mayoría de los idiomas: hablale en el tuyo. Cambiá cuando quieras, incluso en medio de una conversación.',
                chipMore: '+ muchos más',
            },
        },
    },

    // The service is free of charge per T&C §2. The three surfaces sit at the
    // same level even though only the web app is open: Android is a closed
    // test and iOS is not submitted yet, so both stores route to the beta form.
    download: {
        title: 'Probala gratis',
        subtitle:
            'La app web ya está abierta. Android está en beta cerrada y iPhone llega muy pronto.',
        android: {
            lead: 'Beta cerrada en',
            name: 'Google Play',
        },
        ios: {
            lead: 'Próximamente en',
            name: 'App Store',
        },
        web: {
            lead: 'Beta abierta',
            name: 'App web',
        },
    },

    // Landing page for both store badges: the tester list for Android today,
    // the launch list for iPhone later. The form itself is not built yet.
    beta: {
        meta: {
            title: 'Wallet Bot — Pedí acceso a la beta',
            description:
                'Sumate a la beta cerrada de Wallet Bot en Android y enterate primero cuando salga la app de iPhone.',
        },
        chip: {
            android: 'Android en beta cerrada',
            ios: 'iPhone próximamente',
        },
        heading: 'Pedí acceso a la beta',
        body: 'Android está en beta cerrada: dejanos tu mail y te sumamos a la lista de testers.',
        formCta: {
            title: 'Completá el formulario',
            body: 'Son un par de preguntas. Te escribimos por mail cuando te sumemos a la lista.',
        },
        iosNote:
            'Si tenés iPhone, completalo igual: usamos la misma lista para avisarte apenas la app esté disponible en el App Store.',
        webHeading: 'O usala ahora mismo desde el navegador',
        webNotice:
            'No hace falta esperar: la app web está abierta para cualquiera.',
        webCta: 'Abrir la app web',
        backHome: 'Volver al inicio',
    },

    // Apple wants a working support URL on the App Store listing
    // (docs/appstore-readiness.md), and there is nothing to put behind it
    // beyond the mailbox: no form, no ticket system.
    support: {
        meta: {
            title: 'Wallet Bot — Soporte',
            description:
                'Escribinos por mail: la dirección de soporte de Wallet Bot.',
        },
        heading: 'Soporte',
        body: 'Cualquier duda, problema con la app o pedido sobre tu cuenta, escribinos por mail.',
        emailLabel: 'Escribinos a',
        // Localizada a propósito, igual que `feedback.supportEmail` en
        // apps/web y `feedbackSupportEmail` en la app nativa: el catálogo en
        // inglés muestra support@. Las dos direcciones llegan a la misma
        // bandeja, así que esto no es una frase para traducir libremente.
        email: 'soporte@walletbot.live',
        emailSubject: 'Soporte de Wallet Bot',
        backHome: 'Volver al inicio',
    },

    footer: {
        tagline: 'Gestor de gastos personales, conversacional y simple.',
        support: 'Soporte',
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
