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
        getTheApp: 'Conseguí la app',
    },

    hero: {
        // The tape under the hero. `label` is read by screen readers in place
        // of the scrolling list; `chip` is the fixed pill that frames the
        // quotes as complaints about tracking expenses today, so they can't be
        // misread as reviews of the app.
        //
        // The quotes are verbatim open-text answers from the project's own
        // research survey (207 responses, April 6–12 2026), across its three
        // free-text questions: what bothers you most about logging expenses,
        // why you don't, and what put you off. Nothing is edited — no fixed
        // spelling, no trimmed clauses, no composites — beyond stripping a
        // trailing space. R35 keeps its full stop because the respondent
        // typed one. The survey collected no names, emails or phone numbers,
        // and respondents were told their answers could be used anonymously.
        //
        // Order alternates long and short so the tape never runs several wide
        // rows together.
        quoteTape: {
            label: 'Motivos por los que se deja de registrar gastos',
            chip: 'Por qué se deja de anotar',
            quotes: [
                '«Me lleva mucho tiempo registrar cada uno»',
                '«No duré ni medio día»',
                '«La fricción de tener que recordar, categorizar y anotar cada gasto»',
                '«Cargarlos en la hoja»',
                '«Me olvido, no tengo un lugar para anotarlo rápido»',
                '«Porque consume mucho tiempo el hacerlo en el momento»',
                '«A veces pago en efectivo o tiro el ticket y no tengo registro de lo que gasté»',
                '«Tener que ingresarlos y clasificarlos manualmente»',
                '«El tiempo que tengo que invertir en escribir los detalles del gasto.»',
                '«Que siento que debería ser automático»',
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

    // Replaces the old stats strip. Those were four spec counters ("50+
    // monedas", "2 idiomas") — facts about the build, not reasons to care.
    // This states the problem instead, and it is the only place on the page
    // that argues rather than describes.
    problem: {
        title: 'Entender en qué se va la plata es mucho más fácil cuando ya está todo anotado.',
        body: 'El tema es que anotarlo cuesta. Comprar algo lleva diez segundos; registrarlo bien lleva más — abrir la app, elegir la categoría, escribir el número, elegir la cuenta, guardar.',
        close: 'De esa parte se encarga Wallet Bot. Le contás el gasto, queda anotado, y a fin de mes está todo junto para mirarlo.',
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
            'Lo que necesitás para entender en qué se va la plata — y nada más.',
        items: {
            voice: {
                title: 'Le contás y lo anota',
                body: 'Decís «pagué 8.500 en el super con la tarjeta» y listo. Sin campos, sin listas, sin elegir categoría: el asistente crea la cuenta y la categoría sobre la marcha, y deja una tarjeta editable por si entendió mal.',
                types: {
                    expense: 'Gastos',
                    income: 'Ingresos',
                    transfer: 'Transferencias',
                    adjustment: 'Ajustes de saldo',
                },
            },
            offline: {
                title: 'También sin internet',
                body: 'En el celular queda guardado igual, y se pone al día solo cuando volvés a tener señal.',
            },
            local: {
                title: 'Sin crear una cuenta',
                body: 'La app del celular funciona sin que te registres, y lo que anotás se queda en el dispositivo. La cuenta hace falta sólo si querés sincronizarlo.',
            },
            fast: {
                title: 'Los números se actualizan solos',
                body: 'Registrás algo — vos o el asistente — y ya está en las listas, los saldos y los gráficos. Sin recargas ni esperas.',
                chip: 'Cero spinners',
            },
            crossDevice: {
                title: 'En el celu y en la compu',
                body: 'Lo que anotás en el teléfono aparece en la computadora, y al revés. Se sincroniza solo entre tus dispositivos.',
            },
            dashboard: {
                title: 'Preguntale cómo venís',
                body: 'Cuánto llevás gastado, en qué, cuánto queda. Armás el inicio con los widgets que quieras — estadísticas, listas, gráficos de torta, barras o líneas — o se lo pedís al asistente y lo arma él.',
            },
            // Not shipped. The card is on the page anyway because it is
            // labelled "próximamente" and styled as unavailable. It is a stated
            // roadmap item, not a claim about what the app does today.
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
        },
    },

    // The service is free of charge per T&C §2. All three are public, but both
    // store badges route to the beta form first; see `beta` below.
    download: {
        title: 'Probala gratis',
        subtitle: 'Ya está en Android, iPhone y la web.',
        android: {
            lead: 'Disponible en',
            name: 'Google Play',
        },
        ios: {
            lead: 'Disponible en el',
            name: 'App Store',
        },
        web: {
            lead: 'Beta abierta',
            name: 'App web',
        },
    },

    // Landing page for both store badges. Both apps are public, but the Google
    // Form is the way in: its confirmation message holds the two store links,
    // so the copy has to make clear that the links come after the form.
    beta: {
        meta: {
            title: 'Wallet Bot — Descargá la app',
            description:
                'Wallet Bot ya está en Android y iPhone. Completá un formulario corto y accedé a los links de descarga.',
        },
        chip: {
            android: 'Disponible en Android',
            ios: 'Disponible en iPhone',
        },
        heading: 'Descargá la app',
        body: 'Ya está en Google Play y en el App Store. Para descargarla, completá este formulario corto. Los links de descarga están al final.',
        formCta: {
            title: 'Completá el formulario',
            body: 'Son un par de preguntas. Cuando lo envíes, vas a ver los links para Android y iPhone.',
        },
        webHeading: 'O usala ahora mismo desde el navegador',
        webNotice:
            'Sin instalar nada. La app web está abierta para cualquiera.',
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
