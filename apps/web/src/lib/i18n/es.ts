/**
 * Spanish catalog — the reference locale. Its shape defines `Messages`, so
 * every other locale is checked against it at compile time: a missing key, an
 * extra key, or a mismatched parameter list is a type error, not a runtime
 * fallback.
 *
 * Entries that take values are functions, which keeps the parameter names and
 * types checked at the call site.
 */
export const es = {
    common: {
        appName: 'Wallet Bot',
        save: 'Guardar',
        saved: 'Guardado',
        saving: 'Guardando…',
        cancel: 'Cancelar',
        create: 'Crear',
        delete: 'Eliminar',
        edit: 'Editar',
        done: 'Listo',
        apply: 'Aplicar',
        clear: 'Limpiar',
        close: 'Cerrar',
        notFoundTitle: 'Esto ya no existe',
        notFoundDescription:
            'Puede que se haya eliminado desde otro dispositivo. Volvé a la lista para continuar.',
        backToList: 'Volver a la lista',
        name: 'Nombre',
        description: 'Descripción',
        color: 'Color',
        icon: 'Ícono',
        iconAndColor: 'Ícono y color',
        currency: 'Moneda',
        date: 'Fecha',
        account: 'Cuenta',
        home: 'Inicio',
        goBack: 'Volver',
        chooseIcon: 'Elegir ícono',
        colorSwatch: (p: { color: string }) => `Color ${p.color}`,
        nameCannotBeEmpty: 'El nombre no puede estar vacío',
        saveFailed: 'Error al guardar',
        hour: 'Hora',
        minute: 'Minutos',
        noResults: 'Sin resultados',
    },

    nav: {
        actions: 'Acciones',
        home: 'Inicio',
        activity: 'Actividad',
        accounts: 'Cuentas',
        insights: 'Organización',
        addWithGasti: 'Añadir con Gasti',
        addManually: 'Añadir manualmente',
        futureMovements: 'Movimientos futuros',
        sendFeedback: 'Enviar comentarios',
        signOut: 'Cerrar sesión',
        language: 'Idioma',
    },

    assistantBanner: {
        title: 'Conocé a Gaston',
        message: 'Estoy acá para ayudarte con tus gastos',
        action: 'Hablar con Gaston',
    },

    whatsapp: {
        title: 'WhatsApp',
        subtitle: 'Registrá gastos chateando con Gaston',
        loadFailed: 'No pudimos cargar el estado de WhatsApp',
        retry: 'Tocá para reintentar',
        unavailableTitle: 'Todavía no está disponible',
        unavailableBody:
            'WhatsApp no está habilitado para tu cuenta. Te avisamos cuando se active.',
        notConnectedTitle: 'Sin conectar',
        notConnectedBody:
            'Vinculá tu número para registrar gastos chateando con Gaston por WhatsApp.',
        connect: 'Conectar WhatsApp',
        codeLabel: 'Tu código de vinculación',
        codeExpiryHint: 'Vale 10 minutos y se usa una sola vez.',
        openWhatsapp: 'Abrir WhatsApp',
        copyCode: 'Copiar código',
        codeCopied: 'Código copiado',
        copyFailed:
            'No pudimos copiar el código. Seleccionalo y copialo a mano.',
        codeFailed: 'No pudimos crear el código',
        openFailed:
            'No pudimos abrir WhatsApp. Copiá el código y mandalo a mano.',
        connectedTitle: 'Conectado',
        connectedBody:
            'Escribile a Gaston por WhatsApp y va a registrar tus movimientos.',
        linkedOn: (p: { date: string }) => `Vinculado el ${p.date}`,
        disconnect: 'Desconectar',
        disconnectConfirm:
            'Gaston va a dejar de responderle a este número hasta que lo vincules de nuevo.',
        disconnectFailed: 'No pudimos desconectar el número',
        disconnected: 'Número desconectado',
    },

    feedback: {
        title: 'Enviar comentarios',
        subtitle:
            'Contanos qué salió mal o qué te gustaría ver. Podés adjuntar capturas o archivos.',
        messageLabel: 'Tu comentario',
        messagePlaceholder: '¿Qué querés contarnos?',
        attach: 'Adjuntar archivos',
        attachmentsCount: (p: {
            count: number
            max: number
            maxSize: string
        }) => `Adjuntos: ${p.count}/${p.max} · hasta ${p.maxSize} cada uno`,
        removeAttachment: 'Quitar adjunto',
        send: 'Enviar',
        sending: 'Enviando comentarios…',
        sent: '¡Gracias! Recibimos tus comentarios',
        sendFailed: 'No se pudieron enviar tus comentarios',
        messageRequired: 'Escribí un comentario antes de enviar',
        tooManyFiles: (p: { max: number }) =>
            `Podés adjuntar hasta ${p.max} archivos`,
        fileTooLarge: (p: { name: string; max: string }) =>
            `"${p.name}" supera el máximo de ${p.max}`,
        rateLimited:
            'Ya enviaste varios comentarios. Probá de nuevo más tarde.',
        attachmentRejected:
            'No pudimos procesar los adjuntos. Quitalos e intentá de nuevo.',
        uploading: (p: { current: number; total: number }) =>
            `Subiendo archivo ${p.current} de ${p.total}…`,
        offline:
            'Sin conexión. Revisá tu internet e intentá de nuevo, o escribinos por email.',
        errorDismiss: 'Cerrar este mensaje',
        emailInstead: 'Enviar un email en su lugar',
        emailTitle: 'Escribir a soporte',
        emailBody:
            'Mandanos un email y te respondemos. Lo que ya escribiste va dentro del mensaje.',
        // Localizada a propósito: el catálogo en inglés muestra support@. Las
        // dos direcciones llegan a la misma bandeja, así que esto no es una
        // frase para traducir libremente.
        supportEmail: 'soporte@walletbot.live',
        emailOpen: 'Abrir app de email',
        emailCopy: 'Copiar dirección',
        emailCopied: 'Dirección copiada',
        emailCopyFailed:
            'No se pudo copiar. Seleccioná la dirección y copiala a mano.',
        emailSubject: 'Comentarios de Wallet Bot',
        emailBodyFooter: (p: { client: string }) =>
            `Enviado desde Wallet Bot ${p.client}`,
    },

    settings: {
        title: 'Configuración',
        account: 'Cuenta',
        language: 'Idioma',
        languageDescription:
            'Elegí el idioma que se usa en toda la aplicación.',
        theme: 'Tema',
        themeDescription: 'Elegí cómo se ve la aplicación en este dispositivo.',
        systemDefault: 'Predeterminado del sistema',
        lightTheme: 'Claro',
        darkTheme: 'Oscuro',
        english: 'Inglés',
        spanish: 'Español',
    },

    deleteAccount: {
        // Settings tile — same copy as the native tile
        // (`deleteUserAccount*` in apps/native/lib/l10n/app_es.arb).
        tile: 'Eliminar mi cuenta',
        tileDescription: 'Eliminá tu cuenta y todos tus datos para siempre',

        // Request page (/delete-account)
        title: 'Eliminar tu cuenta',
        subtitle:
            'Ingresá tu correo y te enviamos un enlace para confirmar la eliminación.',
        warning:
            'Se van a borrar tu cuenta y todos tus datos de forma permanente. Esta acción no se puede deshacer.',
        emailLabel: 'Correo',
        submit: 'Enviar enlace de eliminación',
        sendFailed:
            'No pudimos enviar el correo. Probá de nuevo en unos minutos.',

        // Sólo se muestra cuando el servidor confirmó el envío, así que la
        // copia es afirmativa. Todo otro resultado es un error de abajo.
        sentTitle: 'Revisá tu correo',
        sentDefinite: (p: { email: string }) =>
            `Te enviamos un enlace a ${p.email} para eliminar tu cuenta.`,
        sentHint: 'El enlace vence en 24 horas.',
        backHome: 'Volver al inicio',

        accountNotFound: (p: { email: string }) =>
            `No existe una cuenta para ${p.email}, así que no hay nada que eliminar.`,
        alreadyDeleted: 'Esa cuenta ya fue eliminada.',
        rateLimited:
            'Ya pediste varios enlaces de eliminación. Esperá una hora y probá de nuevo.',

        // Confirmation page (/delete-account/confirm)
        // Typed by the user, so it has to be a word in their own language.
        confirmWord: 'ELIMINAR',
        confirmTitle: '¿Eliminar tu cuenta definitivamente?',
        confirmSubtitle: 'Esta acción es permanente y no se puede deshacer.',
        willDeleteTitle: 'Se va a borrar para siempre:',
        willDeleteTransactions: 'Todas tus transacciones',
        willDeleteAccounts: 'Tus cuentas y saldos',
        willDeleteCategories: 'Categorías, etiquetas y configuración',
        willDeleteUser: 'Tu usuario y acceso a Wallet Bot',
        confirmPrompt: 'Para confirmar, escribí',
        confirmSubmit: 'Eliminar mi cuenta definitivamente',
        deleteFailed: 'No se pudo eliminar la cuenta',

        doneTitle: 'Tu cuenta fue eliminada',
        doneBody:
            'Estamos borrando todos tus datos de forma permanente. Gracias por haber usado Wallet Bot.',

        invalidTitle: 'Enlace no válido',
        invalidBody:
            'El enlace no es válido, ya venció o ya fue usado. Si todavía querés eliminar tu cuenta, pedí un enlace nuevo.',
        requestNewLink: 'Pedir un enlace nuevo',
    },

    auth: {
        signInToContinue: 'Iniciá sesión para continuar',
        withAccount: 'Con cuenta',
        withAccountDescription:
            'Usá correo o Google para sincronizar tus gastos.',
        signIn: 'Iniciar sesión',
        signUp: 'Crear cuenta',
        name: 'Nombre',
        namePlaceholder: 'Tu nombre',
        email: 'Correo',
        password: 'Contraseña',
        or: 'o',
        continueWithGoogle: 'Continuar con Google',
        signingIn: 'Iniciando sesión...',
        authFailed: 'No se pudo autenticar',

        // El servidor de auth responde siempre en inglés y no conoce el
        // idioma del cliente, así que `error.message` no se puede mostrar:
        // interpolarlo dejaba frases mitad inglés ("Invalid email or
        // password. Si te registraste con Google…"). Cada pantalla arma el
        // texto a partir del `code`, que sí es estable.
        invalidCredentials: 'Correo o contraseña incorrectos',
        invalidEmail: 'El correo no es válido',
        signUpFailed:
            'No pudimos crear tu cuenta. Revisá los datos e intentá de nuevo.',
        connectionFailed:
            'No pudimos conectarnos con el servidor. Revisá tu conexión e intentá de nuevo.',

        googleHint: (p: { message: string }) =>
            `${p.message}. Si te registraste con Google, usá "Continuar con Google".`,
        forgotPassword: '¿Olvidaste tu contraseña?',
        needAccountSignUp: '¿Necesitás una cuenta? Registrate',
        haveAccountSignIn: '¿Ya tenés cuenta? Iniciá sesión',
        verifyEmailTitle: 'Verificá tu correo',
        verifyEmailSent: (p: { email: string }) =>
            `Te enviamos un enlace de verificación a ${p.email}.`,
        verifyEmailInstructions:
            'Abrí el enlace para verificar tu cuenta y después volvé acá a iniciar sesión.',
        verifyEmailDone: 'Ya verifiqué',
        resendVerificationEmail: 'Reenviar correo',
        resendVerificationCooldown: (p: { seconds: number }) =>
            `Reenviar en ${p.seconds}s`,
        resendingVerificationEmail: 'Enviando…',
        verificationEmailResent: 'Te reenviamos el correo de verificación.',
        resendVerificationFailed: 'No se pudo reenviar el correo.',
        backToSignIn: 'Volver a iniciar sesión',

        // Resultados que el servidor ahora nombra, para que ninguna pantalla
        // diga que mandó un correo que nunca salió.
        accountExists:
            'Ya existe una cuenta con ese correo. Iniciá sesión con tu contraseña o con Google.',
        accountNotFound: (p: { email: string }) =>
            `No existe una cuenta para ${p.email}.`,
        emailAlreadyVerified:
            'Ese correo ya está verificado. Iniciá sesión con tu cuenta.',
        rateLimited: 'Demasiados intentos. Esperá un minuto y probá de nuevo.',
        emailSendFailed:
            'No pudimos enviar el correo. Probá de nuevo en unos minutos.',

        resetPasswordTitle: 'Restablecer contraseña',
        resetPasswordSubtitle:
            'Ingresá tu correo y te enviamos un enlace para restablecerla.',
        sendResetLink: 'Enviar enlace',
        sendResetLinkFailed: 'No se pudo enviar el correo',
        resetEmailSent: (p: { email: string }) =>
            `Te enviamos un enlace a ${p.email} para restablecer tu contraseña.`,
        resetEmailSentReturnHint:
            'Cuando la restablezcas, volvé acá e iniciá sesión con tu contraseña nueva.',

        newPasswordTitle: 'Nueva contraseña',
        newPasswordSubtitle: 'Elegí una contraseña nueva para tu cuenta.',
        newPassword: 'Nueva contraseña',
        repeatPassword: 'Repetir contraseña',
        passwordsDoNotMatch: 'Las contraseñas no coinciden',
        resetPasswordAction: 'Restablecer contraseña',
        resetPasswordFailed: 'No se pudo restablecer la contraseña',
        passwordUpdated:
            'Contraseña actualizada. Iniciá sesión con tu nueva contraseña.',

        invalidLinkTitle: 'Enlace no válido',
        invalidLinkDescription:
            'El enlace no es válido o ya venció. Pedí uno nuevo para restablecer tu contraseña.',
        requestNewLink: 'Pedir un enlace nuevo',

        emailVerifiedTitle: '¡Listo! Tu correo fue verificado',
        emailVerifiedDescription: 'Ya podés iniciar sesión con tu cuenta.',
        linkExpiredTitle: 'El enlace venció',
        linkExpiredDescription:
            'Iniciá sesión y te enviamos un enlace nuevo automáticamente.',
        verifyFailedTitle: 'No pudimos verificar tu correo',
        verifyFailedDescription:
            'El enlace no es válido. Volvé a iniciar sesión para recibir un enlace nuevo.',
    },

    // Aceptación de Términos y Condiciones y Política de Privacidad. Los
    // documentos se publican en www.walletbot.live (apps/landing renderiza
    // docs/legal/*.md), así que acá solo va la interfaz de aceptación.
    legal: {
        firstTitle: 'Antes de empezar',
        firstSubtitle:
            'Necesitamos tu aceptación para crear tu cuenta y darte el servicio.',
        // Una sola cosa cambió: nombrala, para no pedir de nuevo lo que ya
        // aceptaste.
        updatedTermsTitle: 'Actualizamos los Términos',
        updatedPrivacyTitle: 'Actualizamos la Política de Privacidad',
        updatedBothTitle: 'Actualizamos los Términos y la Privacidad',
        updatedSubtitle:
            'Revisá los cambios y aceptalos para seguir usando Wallet Bot.',
        updatedSubtitleGrace:
            'Podés seguir usando la app por ahora, pero vamos a necesitar tu aceptación.',

        ageConfirm: 'Tengo 18 años o más',

        // `[[terms]]` y `[[privacy]]` se reemplazan por enlaces al documento
        // publicado (ver `components/auth/legal-consent.tsx`). Van dentro de la
        // frase, no en una lista aparte, para no gastar alto en la tarjeta —
        // y así cada idioma acomoda artículos y orden a su manera.
        acceptTerms: 'Acepto los [[terms]]',
        acceptPrivacy: 'Acepto la [[privacy]]',
        acceptBoth: 'Acepto los [[terms]] y la [[privacy]]',
        termsName: 'Términos y Condiciones',
        privacyName: 'Política de Privacidad',

        acceptAction: 'Aceptar y continuar',
        later: 'Más tarde',
        acceptFailed:
            'No pudimos registrar tu aceptación. Revisá tu conexión e intentá de nuevo.',
        acceptRequired: 'Marcá las dos casillas para continuar.',
    },

    dashboard: {
        widget: 'Widget',
        editDashboard: 'Editar tablero',
        addWidget: 'Agregar widget',
        addWidgetHere: 'Agregar un widget acá',
        editWidget: 'Editar widget',
        removeWidget: 'Quitar widget',
        removeWidgetConfirmation: (p: { title: string }) =>
            `¿Quitar «${p.title}» del tablero?`,
        emptyTitle: 'Tu tablero está vacío',
        emptyDescription: 'Agregá un widget para empezar.',
        saveFailed: 'No se pudo guardar el widget',
        deleteFailed: 'No se pudo quitar el widget',
        layoutSaveFailed: 'No se pudo actualizar el tablero',
        noMovementsYet: 'Sin movimientos todavía',
        partialResult: 'Resultado parcial',

        widgetType: 'Tipo',
        widgetTitle: 'Título',
        typeStat: 'Valor',
        typeList: 'Movimientos',
        typeBalance: 'Saldo',
        typeChart: 'Gráfico',
        typeBalanceComparison: 'Comparación de saldo',
        // Balance comparison rows: last month's close, now, and the change.
        lastMonthBalance: 'Saldo del mes pasado',
        currentBalance: 'Saldo actual',
        balanceDifference: 'Diferencia',

        aggregation: 'Agregación',
        aggregationSum: 'Suma',
        aggregationNet: 'Neto',
        aggregationCount: 'Cantidad',
        rowLimit: 'Cantidad de filas',

        accounts: 'Cuentas',
        accountsAllHint: 'Todas las cuentas de esta moneda.',
        accountsScopedHint: 'Solo las cuentas seleccionadas.',

        groupBy: 'Agrupar por',
        groupByCategory: 'Categoría',
        groupByAccount: 'Cuenta',
        groupByMonth: 'Mes',
        chartKind: 'Tipo de gráfico',
        chartPie: 'Torta',
        chartBar: 'Barras',
        chartLine: 'Líneas',

        filter: 'Filtro',
        filterConfigured: 'Filtro configurado',
        noFilter: 'Sin filtro',
        filterRequired: 'Elegí un filtro para este widget',
        titleRequired: 'Ingresá un título para este widget',

        width: 'Ancho',
        widthThird: '1/3',
        widthHalf: '1/2',
        widthTwoThirds: '2/3',
        widthFull: '1/1',
        moveUp: 'Mover arriba',
        moveDown: 'Mover abajo',
        moveLeft: 'Mover a la izquierda',
        moveRight: 'Mover a la derecha',

        background: 'Fondo',
        backgroundNone: 'Sin fondo',
        backgroundFixed: 'Fijo',
        backgroundValue: 'Por valor',
        thresholdLow: 'Umbral bajo',
        thresholdHigh: 'Umbral alto',
        belowLow: 'Debajo del umbral bajo',
        betweenThresholds: 'Entre umbrales',
        aboveHigh: 'Encima del umbral alto',

        defaultExpensesMonth: 'Gastos del mes',
        defaultIncomeMonth: 'Ingresos del mes',
        defaultMovementsMonth: 'Movimientos del mes',
        defaultMovements: 'Movimientos',
        defaultRecentMovements: 'Movimientos recientes',
        defaultTotalBalance: (p: { currency: string }) =>
            `Saldo total (${p.currency})`,
    },

    // The filter editor, shared by the activity list and the dashboard widget
    // sheet. Wording follows native's `filter_sheet.dart` and its arb entries so
    // the same control reads the same on both platforms.
    filters: {
        title: 'Filtros',
        simple: 'Simple',
        advanced: 'Avanzado',
        reset: 'Limpiar filtros',
        close: 'Cerrar',

        type: 'Tipo',
        status: 'Estado',
        date: 'Fecha',
        currency: 'Moneda',
        amount: 'Monto',
        text: 'Texto',
        subtags: 'Subetiquetas',

        any: 'Cualquiera',
        statusPending: 'Pendiente',
        statusCleared: 'Liquidado',

        presetToday: 'Hoy',
        presetThisWeek: 'Esta semana',
        presetThisMonth: 'Este mes',
        presetLastMonth: 'Mes pasado',
        presetThisYear: 'Este año',
        customRange: 'Rango personalizado',
        rangeStart: 'Desde',
        rangeEnd: 'Hasta',
        chooseRange: 'Elegir rango',

        transferDirection: 'Dirección (para transferencias)',
        direction: 'Dirección',
        directionSource: 'Origen',
        directionDestination: 'Destino',
        directionEither: 'Cualquiera',

        match: 'Coincidencia',
        matchAny: 'Cualquiera',
        matchAll: 'Todas',
        includeSubtags: 'Incluir subetiquetas',

        minimum: 'Mín',
        maximum: 'Máx',
        selectCurrencyForAmount: 'Elegí una moneda para filtrar por monto.',
        searchHint: 'Buscar por nombre o descripción…',

        noAccountsYet: 'Todavía no hay cuentas.',
        noCategoriesYet: 'Todavía no hay categorías.',
        noTagsYet: 'Todavía no hay etiquetas.',
        noCurrenciesYet: 'Todavía no hay monedas.',
        showLess: 'Ver menos',
        showMore: (p: { count: number }) => `Ver ${p.count} más`,

        advancedNotice: 'Este filtro usa reglas avanzadas.',
        advancedWarning:
            'La vista simple no puede editar OR, NOT o grupos anidados sin cambiar el significado del filtro.',
        editAdvanced: 'Editar avanzado',
        createSimpleFilter: 'Crear filtro simple',
        addConditionToStart: 'Agregá una condición para empezar.',
        condition: 'Condición',
        group: 'Grupo',
        deleteGroup: 'Eliminar grupo',
        deleteCondition: 'Eliminar condición',
        field: 'Campo',
        operator: 'Operador',
        chooseField: 'Elegí un campo',
        chooseOperator: 'Elegí un operador',
        combinatorAnd: 'Y',
        combinatorOr: 'O',
        negate: 'NO',
        operatorIncludes: 'incluye',
        operatorExcludes: 'excluye',
        operatorRelative: 'relativa',
        operatorBetween: 'entre',
        operatorGreaterEqual: 'mayor o igual',
        operatorLessEqual: 'menor o igual',
        operatorContains: 'contiene',
        operatorNotContains: 'no contiene',
        unsupportedField: 'Campo no soportado.',
    },

    errors: {
        pageNotFound: 'Página no encontrada',
        pageNotFoundDescription: 'La página que buscás no existe o fue movida.',
        somethingWentWrong: 'Algo salió mal',
        unexpectedError:
            'Ocurrió un error inesperado. Probá recargar la página o volver.',
        refreshPage: 'Recargar página',
        viewErrorDetails: 'Ver detalles del error',
        sessionEndedTitle: 'Tu sesión terminó',
        sessionEndedDescription:
            'Esta sesión ya no es válida. Te llevamos a iniciar sesión de nuevo.',
    },

    reorder: {
        roleDescription: 'elemento reordenable',
        reorderAccounts: 'Ordenar cuentas',
        reorderCategories: 'Ordenar categorías',
        accountsFailed: 'No se pudo guardar el nuevo orden de tus cuentas',
        categoriesFailed: 'No se pudo guardar el nuevo orden de tus categorías',
        reorderTags: 'Ordenar etiquetas',
        tagsFailed: 'No se pudo guardar el nuevo orden de tus etiquetas',
        dragHandle: (p: { name: string }) => `Mover ${p.name}`,
        instructions:
            'Para mover un elemento, presioná espacio o enter, movelo con las flechas y presioná espacio o enter de nuevo para soltarlo. Escape cancela.',
        picked: (p: { name: string; position: number; total: number }) =>
            `Agarraste ${p.name}, en la posición ${p.position} de ${p.total}.`,
        moved: (p: { name: string; position: number; total: number }) =>
            `${p.name} está en la posición ${p.position} de ${p.total}.`,
        dropped: (p: { name: string; position: number; total: number }) =>
            `Soltaste ${p.name} en la posición ${p.position} de ${p.total}.`,
        cancelled: (p: { name: string }) =>
            `Movimiento cancelado. ${p.name} volvió a su lugar.`,
    },

    accounts: {
        accountDetails: 'Detalle de cuenta',
        newAccount: 'Nueva cuenta',
        createAccount: 'Crear cuenta',
        emptyTitle: 'No tenés cuentas aún',
        emptyDescription:
            'Creá tu primera cuenta para empezar a registrar tus gastos.',
        namePlaceholder: 'Ej: Efectivo, Banco Nación…',
        suggestions: 'Sugerencias',
        suggestionCash: 'Efectivo',
        suggestionBank: 'Banco',
        suggestionCard: 'Tarjeta',
        chooseCurrency: 'Elegí una moneda',
        searchCurrency: 'Buscar moneda…',
        initialBalance: 'Balance inicial (opcional)',
        invalidAmount: 'Ingresá un monto válido',
        creating: 'Creando cuenta…',
        created: 'Cuenta creada',
        createFailed: 'No se pudo crear la cuenta',
        duplicateNameCurrency: 'Ya existe una cuenta con ese nombre y moneda',
        saving: 'Guardando cuenta…',
        saved: 'Cuenta guardada',
        saveFailed: 'No se pudo guardar la cuenta',
        deleting: 'Eliminando cuenta…',
        deleted: 'Cuenta eliminada',
        deleteFailed: 'No se pudo eliminar la cuenta',
        balance: 'Saldo',
        adjustBalance: 'Ajustar saldo',
        newBalance: 'Nuevo saldo',
        adjusting: 'Ajustando saldo…',
        adjusted: 'Saldo ajustado',
        adjustFailed: 'No se pudo ajustar el saldo',
        deleteTitle: 'Eliminar cuenta',
        deleteConfirm: (p: { name: string }) =>
            `¿Seguro que querés eliminar "${p.name}"? Dejará de aparecer en tus cuentas.`,
        selectDetail: 'Seleccioná una cuenta para ver su detalle',
        lastTransactions: 'Últimas transacciones',
        viewAll: 'Ver todas',
    },

    activity: {
        search: 'Buscar',
        filters: 'Filtros',
        accounts: 'Cuentas',
        categories: 'Categorías',
        tags: 'Etiquetas',
        rangeFrom: (p: { date: string }) => `Desde ${p.date}`,
        rangeTo: (p: { date: string }) => `Hasta ${p.date}`,
        removeFilter: (p: { label: string }) => `Quitar filtro ${p.label}`,
        // Fallbacks for a chip whose entities all resolved to nothing.
        fallbackAccounts: 'cuentas',
        fallbackCategories: 'categorías',
        fallbackTags: 'etiquetas',
        typeAll: 'Todos',
        typeIncome: 'Ingresos',
        typeExpense: 'Gastos',
        typeTransfer: 'Transferencias',
        typeBalanceAdjustment: 'Ajustes',
        noTransactions: 'No hay transacciones',
        addTransaction: 'Agregar transacción',
        viewFutureMovements: 'Ver movimientos futuros',
        selectDetail: 'Seleccioná una transacción para ver su detalle',
        today: 'Hoy',
        yesterday: 'Ayer',
        estimatedDay: (p: { weekday: string }) => `${p.weekday} (estimado)`,
        transferSent: 'Transferencia enviada',
        transferReceived: 'Transferencia recibida',
        accountIdentity: (p: { name: string }) => `Cuenta: ${p.name}`,
        categoryIdentity: (p: { name: string }) => `Categoría: ${p.name}`,
        estimatedDateOrTime: 'Fecha u horario estimado',
        summaryIncome: 'Ingresos',
        summaryExpenses: 'Gastos',
        summaryBalance: 'Balance',
        noMovementsYet: 'Sin movimientos todavía',
    },

    transaction: {
        // The two auto-generated names, localized at render time by
        // `generated-names.ts`. The persisted value stays canonical Spanish.
        balanceAdjustment: 'Ajuste de saldo',
        initialBalance: 'Balance inicial',

        gone: 'La actividad ya no existe',
        detail: 'Detalle',
        editActivity: 'Editar actividad',
        amount: 'Monto',
        noDescription: 'Sin descripción',
        date: 'Fecha',
        estimatedDate: 'Fecha estimada',
        time: 'Horario',
        estimatedTime: 'Horario estimado',
        account: 'Cuenta',
        sourceAccount: 'Cuenta origen',
        destinationAccount: 'Cuenta destino',
        exchangeRate: 'Tipo de cambio',
        deletedAccount: 'Cuenta eliminada',
        category: 'Categoría',
        tags: 'Etiquetas',
        noTags: 'Sin etiquetas',
        balanceUnavailable: 'Saldo no disponible',
        // A balance adjustment: what the user declared, and what the app had
        // computed for the account just before it (it moves as the past does).
        declaredBalance: 'Saldo declarado',
        platformBalance: 'Saldo calculado',
        chooseAccount: 'Elegí una cuenta',
        sameAccounts: 'La cuenta origen y destino deben ser distintas',
        amountGreaterThanZero: 'Ingresá un monto mayor a cero',
        updated: 'Actividad actualizada',
        updateFailed: 'No se pudo guardar la actividad',
        deleteTitle: 'Eliminar actividad',
        deleteConfirm: (p: { name: string }) =>
            `¿Seguro que querés eliminar “${p.name}”?`,
        deleted: 'Actividad eliminada',
        deleteFailed: 'No se pudo eliminar la actividad',
    },

    insights: {
        categories: 'Categorías',
        tags: 'Etiquetas',
        spentThisMonth: 'Gastado este mes',
        noSpendThisMonth: 'Sin gastos este mes',
        otherCurrencies: (p: { count: number }) =>
            p.count === 1 ? '+ 1 otra moneda' : `+ ${p.count} otras monedas`,
        movementCount: (p: { count: number }) =>
            p.count === 0
                ? 'Sin movimientos'
                : p.count === 1
                  ? '1 movimiento'
                  : `${p.count} movimientos`,
        selectCategoryDetail: 'Seleccioná una categoría para ver su detalle',
        selectTagDetail: 'Seleccioná una etiqueta para ver su detalle',
        categoryDetails: 'Detalle de categoría',
        tagDetails: 'Detalle de etiqueta',
        lastMovements: 'Últimos movimientos',
        viewAll: 'Ver todos',

        noCategoriesYet: 'No tenés categorías aún.',
        newCategory: 'Nueva categoría',
        categoryNamePlaceholder: 'Ej: Supermercado, Transporte…',
        categoryDescriptionOptional: 'Descripción (opcional)',
        categorySuggestionGroceries: 'Supermercado',
        categorySuggestionTransport: 'Transporte',
        categorySuggestionUtilities: 'Servicios',
        categoryCreating: 'Creando categoría…',
        categoryCreated: 'Categoría creada',
        categoryCreateFailed: 'No se pudo crear la categoría',
        categorySaving: 'Guardando categoría…',
        categorySaved: 'Categoría guardada',
        categorySaveFailed: 'No se pudo guardar la categoría',
        categoryDeleting: 'Eliminando categoría…',
        categoryDeleted: 'Categoría eliminada',
        categoryDeleteFailed: 'No se pudo eliminar la categoría',
        categoryDeleteTitle: 'Eliminar categoría',
        categoryDeleteConfirm: (p: { name: string }) =>
            `¿Seguro que querés eliminar "${p.name}"? Dejará de aparecer en tus categorías.`,

        noTagsYet: 'No tenés etiquetas aún.',
        newTag: 'Nueva etiqueta',
        tagCreating: 'Creando etiqueta…',
        tagCreated: 'Etiqueta creada',
        tagCreateFailed: 'No se pudo crear la etiqueta',
        tagSaving: 'Guardando etiqueta…',
        tagSaved: 'Etiqueta guardada',
        tagSaveFailed: 'No se pudo guardar la etiqueta',
        tagDeleting: 'Eliminando etiqueta…',
        tagDeleted: 'Etiqueta eliminada',
        tagDeleteFailed: 'No se pudo eliminar la etiqueta',
        tagDeleteTitle: 'Eliminar etiqueta',
        tagDeleteConfirm: (p: { name: string }) =>
            `¿Seguro que querés eliminar "${p.name}"? Dejará de aparecer en tus etiquetas.`,
        tagDeleteWithChildrenTitle: 'Eliminar etiqueta con subetiquetas',
        // Rendered right after the bold tag name, so it starts mid-sentence.
        tagDeleteWithChildrenPrompt: (p: { count: number }) =>
            p.count === 1
                ? 'tiene 1 subetiqueta. ¿Qué hacemos con ella?'
                : `tiene ${p.count} subetiquetas. ¿Qué hacemos con ellas?`,
        keepSubtags: 'Conservar subetiquetas',
        deleteEverything: 'Eliminar todo',
        createSubtag: 'Crear subetiqueta',
        parentTag: 'Etiqueta padre',
        selectParentTag: 'Elegí la etiqueta padre',
        searchTags: 'Buscar etiquetas…',
        noTagsAvailable: 'No hay etiquetas disponibles',
    },

    voice: {
        title: 'Habla con Gaston',
        speaking: 'Hablando',
        you: 'Vos',
        agent: 'Gaston',
        interrupted: '(interrumpido)',
        tool: 'Herramienta',
        toolRunning: 'Ejecutando',
        toolDone: 'Listo',
        toolCancelled: 'Cancelado',
        microphone: 'Micrófono',
        connect: 'Conectar',
        disconnect: 'Desconectar',
        endSession: 'Finalizar sesión',
        typeMessage: 'Escribí un mensaje…',
        send: 'Enviar',
        welcomeTitle: '¿En qué te ayudo?',
        welcome: 'Contame un gasto o preguntame por tus cuentas',
        startTalking: 'Iniciar llamada',
        liveHint: 'Modo manos libres',
        exitLive: 'Terminar llamada',
        recordVoiceNote: 'Grabar un audio',
        discardVoiceNote: 'Descartar audio',
        noteLimit: 'Límite de 5 minutos',
        onCall: 'En llamada',
        recordHint: 'Tocá o mantené apretado para grabar un audio',
        preparingMic: 'Preparando el micrófono',
        listening: 'Te escucho',
        micPaused: 'Micrófono en pausa',
        slideToLock: 'Deslizá para bloquear',
        pause: 'Pausar',
        resume: 'Continuar',
        suggestions: {
            logExpense: (p: { amount: string; category: string }) =>
                `Gasté ${p.amount} en ${p.category}`,
            logExpenseWithAccount: (p: {
                amount: string
                category: string
                account: string
            }) => `Gasté ${p.amount} en ${p.category} con ${p.account}`,
            spentInCategoryThisMonth: (p: { category: string }) =>
                `¿Cuánto gasté en ${p.category} este mes?`,
            accountBalance: (p: { account: string }) =>
                `¿Cuánto tengo en ${p.account}?`,
            topSpendingThisMonth: '¿En qué gasté más este mes?',
            compareCategoryLastMonth: (p: { category: string }) =>
                `¿Gasté más en ${p.category} que el mes pasado?`,
            transfer: (p: {
                amount: string
                account: string
                toAccount: string
            }) => `Pasé ${p.amount} de ${p.account} a ${p.toAccount}`,
            logIncome: (p: { amount: string; account: string }) =>
                `Cobré ${p.amount} en ${p.account}`,
            spentWithTag: (p: { tag: string }) =>
                `¿Cuánto gasté con la etiqueta ${p.tag}?`,
            recentExpenses: '¿Cuáles fueron mis últimos gastos?',
            whatCanYouDo: '¿Qué podés hacer?',
            createCashAccount: 'Creá una cuenta de efectivo',
            setupCategories: 'Ayudame a armar mis categorías',
            howToLogExpense: '¿Cómo anoto un gasto?',
            homeWidget: 'Agregá un widget en Inicio con mis gastos del mes',
            homeWidgetForCategory: (p: { category: string }) =>
                `Agregá un widget en Inicio con mis gastos en ${p.category}`,
        },
        systemConnecting: 'Conectando…',
        systemTokenReceived: (p: { model: string }) =>
            `Token recibido para ${p.model}`,
        systemSocketError: 'Error de WebSocket',
        systemDisconnected: 'Desconectado',
        systemConnected: 'Conectado. Podés hablar.',
        systemConnectedTyping: 'Conectado. Enviando tu mensaje…',
        startupAudioTimeout:
            'La conexión tardó demasiado. Tocá el micrófono para volver a intentar.',
        systemConnectionFailed: (p: { error: string }) =>
            `Falló la conexión: ${p.error}`,
        systemUnavailable:
            'Gastón no está disponible en este momento. Probá de nuevo en unos minutos.',
        systemMicOpenFailed: (p: { error: string }) =>
            `No se pudo abrir el micrófono: ${p.error}`,
        systemReconnecting: (p: { seconds: number }) =>
            `Se cortó la conexión. Reintentando en ${p.seconds}s… La conversación continúa donde quedó.`,
    },

    agentReport: {
        moreOptions: 'Más opciones',
        action: 'Reportar esta respuesta',
        menuItem: 'Reportar una respuesta',
        badge: 'Reportada',
        title: 'Reportar una respuesta',
        subtitle:
            'Contanos qué estuvo mal con lo que respondió Gaston. Lo revisamos para corregir el asistente.',
        sessionSubtitle:
            'Reportá esta conversación cuando la respuesta fue solo por voz o ya quedó demasiado arriba.',
        reasonLabel: 'Motivo',
        reasonOffensive: 'Ofensiva, agresiva o violenta',
        reasonSexual: 'Contenido sexual',
        reasonDangerous: 'Peligrosa o ilegal',
        reasonMisleading: 'Información financiera falsa',
        reasonPrivacy: 'Mostró datos que no correspondían',
        reasonOther: 'Otro',
        reasonRequired: 'Elegí un motivo antes de enviar',
        noteLabel: 'Detalle (opcional)',
        notePlaceholder: '¿Qué pasó?',
        reportedTextLabel: 'Respuesta reportada',
        sessionNotice: 'Se envía la conversación de esta sesión, sin el audio.',
        privacyNotice:
            'Enviamos el texto de arriba junto con el modelo y la versión de la app. El audio nunca sale de tu dispositivo.',
        send: 'Enviar reporte',
        sending: 'Enviando reporte…',
        sent: 'Gracias. Vamos a revisar esta respuesta',
        failed: 'No pudimos enviar el reporte',
        rateLimited: 'Ya enviaste varios reportes. Probá de nuevo más tarde.',
        offline: 'Sin conexión. Revisá tu internet y probá de nuevo.',
        errorDismiss: 'Descartar este mensaje',
        noResponseYet: 'Todavía no hay ninguna respuesta para reportar',
    },

    adminReports: {
        title: 'Respuestas reportadas',
        subtitle:
            'Reportes de respuestas del asistente enviados desde la app. Requerido por la política de contenido generado con IA de Google Play.',
        empty: 'No hay reportes con este estado',
        statusPending: 'Pendientes',
        statusReviewed: 'Revisados',
        statusActioned: 'Con acción',
        statusDismissed: 'Descartados',
        loadMore: 'Cargar más',
        reportedText: 'Respuesta reportada',
        precedingUserText: 'Lo que dijo la persona antes',
        note: 'Detalle',
        reviewNote: 'Nota de revisión',
        reviewNotePlaceholder: 'Qué hicimos con este reporte',
        session: 'Sesión',
        model: 'Modelo',
        reporterAccount: 'Cuenta',
        reporterDevice: 'Dispositivo',
        scopeResponse: 'Una respuesta',
        scopeSession: 'Conversación entera',
        save: 'Guardar',
        saved: 'Reporte actualizado',
        saveFailed: 'No se pudo actualizar el reporte',
    },

    admin: {
        title: 'Back office',
        exit: 'Salir del back office',
        sections: 'Secciones del back office',
        notAdmin: 'No tenés permisos para ver esta página',
        loadMore: 'Cargar más',
        navFlags: 'Feature flags',
        navFeedback: 'Feedback',
        navReports: 'Reportes',
        navMetrics: 'Métricas',
        navUsers: 'Usuarios',
        navTranscripts: 'Transcripciones',
        navUsability: 'Usabilidad',
        account: 'Cuenta',
        device: 'Dispositivo',
        flags: {
            overrides: 'Excepciones por usuario',
            noOverrides: 'Todavía no hay excepciones.',
            remove: 'Quitar',
            userId: 'Id de usuario',
            addOverride: 'Agregar excepción',
            removing: 'Quitando…',
            defaultUpdated: 'Valor por defecto actualizado',
            defaultFailed: 'No se pudo actualizar el valor por defecto',
            overrideUpdated: 'Excepción actualizada',
            overrideFailed: 'No se pudo actualizar la excepción',
            overrideRemoved: 'Excepción quitada',
            overrideRemoveFailed: 'No se pudo quitar la excepción',
            overrideAdded: 'Excepción agregada',
            overrideAddFailed: 'No se pudo agregar la excepción',
        },
        feedback: {
            subtitle:
                'Mensajes que la gente envió desde la app, los más nuevos primero.',
            empty: 'Todavía no hay feedback',
            attachments: 'Adjuntos',
            anonymous: 'Cuenta local (sin email)',
        },
        users: {
            subtitle: 'Cuentas, las más nuevas primero.',
            searchPlaceholder: 'Buscar una cuenta por email exacto',
            search: 'Buscar',
            clearSearch: 'Limpiar',
            notFound: 'No hay ninguna cuenta con ese email',
            empty: 'Todavía no hay cuentas',
            admin: 'Admin',
            verified: 'Verificada',
            unverified: 'Sin verificar',
            joined: 'Alta',
            userId: 'Id de usuario',
            unnamed: 'Sin nombre',
        },
        transcripts: {
            subtitle:
                'Sesiones de voz y chat, las más nuevas primero. Son conversaciones privadas: abrí una sólo cuando haga falta.',
            empty: 'Todavía no hay sesiones',
            unknownUser: 'Cuenta eliminada',
            started: 'Inicio',
            ended: 'Fin',
            open: 'Abrir',
            back: 'Volver a las sesiones',
            noLines: 'No hay texto de conversación en lo cargado hasta ahora.',
            speakerUser: 'Persona',
            speakerAgent: 'Asistente',
            model: 'Modelo',
        },
        metrics: {
            subtitle:
                'Las métricas de negocio viven en Grafana. Abrí los dashboards desde acá.',
            dashboardsTitle: 'Cuentas creadas por método de autenticación',
            dashboardsDescription:
                'Altas por método de autenticación en producción. Requiere acceso a la organización de Grafana.',
            open: 'Abrir en Grafana',
        },
    },

    usability: {
        title: 'Sesiones de usabilidad',
        newSession: 'Nueva sesión',
        empty: 'Todavía no hay sesiones',
        emptyDetail:
            'Creá una sesión para generar los usuarios de prueba de un participante.',
        loadMore: 'Cargar más',
        groupLabel: (p: { group: number }) => `Grupo ${p.group}`,
        group: 'Grupo',
        group1: 'Grupo 1: nunca usaron la app',
        group2: 'Grupo 2: ya usan la app',
        statusProvisioning: 'Generando usuarios',
        statusReady: 'Lista',
        statusFailed: 'Falló la generación',
        hasRecording: 'Con grabación',
        sessionDay: 'Día de la sesión',
        sessionDayHint:
            'Las fechas de los escenarios 0 y 2 se calculan desde este día.',
        sessionTitle: 'Título (opcional)',
        editTitle: 'Editar título',
        titleDialog: 'Título de la sesión',
        titleDialogHint:
            'Dejalo vacío para ver solo el código del participante.',
        titleSaved: 'Título actualizado',
        titleSaveFailed: 'No se pudo actualizar el título',
        createDescription:
            'Se crean tres usuarios con el email verificado y los términos aceptados: el del escenario 0 con tres cuentas, el del escenario 1 vacío y el del escenario 2 con seis meses de historial.',
        create: 'Crear sesión',
        creating: 'Creando sesión…',
        created: 'Sesión creada',
        createFailed: 'No se pudo crear la sesión',
        notFound: 'Esta sesión no existe',
        backToList: 'Volver a las sesiones',
        provisioningTitle: 'Generando usuarios y datos…',
        provisioningDetail:
            'Tarda unos segundos. Mientras tanto podés revisar el guion.',
        failedTitle: 'No se pudieron generar los usuarios',
        retry: 'Reintentar',
        retrying: 'Reintentando…',
        retried: 'Generación reiniciada',
        retryFailed: 'No se pudo reintentar',
        credentials: 'Usuarios de prueba',
        scenarioUser: (p: { scenario: number }) =>
            `Usuario del escenario ${p.scenario}`,
        email: 'Email',
        password: 'Contraseña',
        copy: 'Copiar',
        copied: 'Copiado',
        copyFailed: 'No se pudo copiar',
        userPending: 'Generándose…',
        userFailed: 'No se generó. Reintentá desde la sesión.',
        openAssistant: 'Abrir el guion',
        stepProgress: (p: { done: number; total: number }) =>
            `${p.done} de ${p.total} completados`,
        started: 'Inicio',
        ended: 'Fin',
        duration: 'Duración',
        notStarted: 'Sin empezar',
        noValue: 'Sin dato',
        stepOf: (p: { current: number; total: number }) =>
            `Paso ${p.current} de ${p.total}`,
        stepNotFound: 'Este paso no existe',
        previous: 'Anterior',
        next: 'Siguiente',
        finish: 'Volver a la sesión',
        sessionTime: 'Tiempo de sesión',
        startSession: 'Empezar la sesión',
        endSession: 'Terminar la sesión',
        startedAt: (p: { time: string }) => `Empezó a las ${p.time}`,
        startedAndEnded: (p: { start: string; end: string }) =>
            `De ${p.start} a ${p.end}`,
        scenarioTimer: (p: { scenario: number }) =>
            `Tiempo del escenario ${p.scenario}`,
        startScenario: 'Empezar escenario',
        endScenario: 'Terminar escenario',
        resetTimer: 'Reiniciar',
        markStart: 'Marcar inicio',
        clearTime: 'Borrar hora',
        readAloud: 'Leer',
        yes: 'Sí',
        no: 'No',
        saveFailed: 'No se pudo guardar el cambio',
        expectedAnswer: 'Respuesta esperada',
        probableErrors: 'Errores probables',
        answersPending:
            'Aparece cuando terminan de generarse los datos del escenario 2.',
        showMaterial: 'Ver',
        hideMaterial: 'Ocultar',
        susScore: 'Puntaje SUS',
        susPending: 'Completá las diez afirmaciones para ver el puntaje.',
        susReference:
            'El promedio de referencia ronda 68. Con pocas personas sirve para comparar grupos y rondas.',
        summaryTitle: 'Resumen',
        difficulty: (p: { scenario: number }) =>
            `Dificultad escenario ${p.scenario}`,
        hintsGiven: 'Pistas anotadas en la planilla',
        noHints: 'No se anotó ninguna pista.',
        recording: 'Grabación',
        recordingNoConsent: 'La persona no dio permiso de grabación.',
        noRecording: 'Todavía no se subió la grabación.',
        uploadRecording: 'Subir grabación',
        replaceRecording: 'Reemplazar grabación',
        uploading: (p: { percent: number }) =>
            `Subiendo grabación… ${p.percent}%`,
        uploaded: 'Grabación subida',
        uploadFailed: 'No se pudo subir la grabación',
        uploadTimeoutHint:
            'La subida se corta a los 2 minutos. Si el archivo es grande, subilo con wifi.',
        recordingMeta: (p: { size: string; date: string }) =>
            `${p.size}, subida el ${p.date}`,
        download: 'Descargar',
        viewScript: 'Ver guion',
        printMaterials: 'Imprimir materiales',
        scriptTitle: 'Guion completo',
        scriptStep: (p: { number: number }) => `Paso ${p.number}`,
        scriptScale: 'Del 1 al 5',
        scriptRecord: (p: { fields: string }) => `Se anota: ${p.fields}.`,
        scriptExpectedAnswer:
            'La respuesta esperada depende del día de cada sesión y se ve dentro de la sesión.',
        scriptCredentials: (p: { scenario: number }) =>
            `Loguear el usuario del escenario ${p.scenario}. Se genera con cada sesión.`,
        scriptScenarioTimer: 'Marcar el inicio y el fin del escenario.',
        scriptSessionStart: 'Empezar el reloj de la sesión.',
        scriptSessionEnd: 'Terminar el reloj de la sesión.',
        scriptRecording: 'Subir la grabación de la sesión.',
        susStatements: 'Afirmaciones',
        printTitle: 'Materiales para imprimir',
        print: 'Imprimir',
        printHint:
            'Imprimí una copia por participante. En el diálogo de impresión elegí A4 y desactivá encabezados y pies de página.',
    },

    actionWidget: {
        expense: 'Gasto',
        income: 'Ingreso',
        transfer: 'Transferencia',
        balanceAdjustment: 'Ajuste de saldo',
        transactionRecorded: (p: { type: string }) => `${p.type} registrado`,
        transactionUpdated: (p: { type: string }) => `${p.type} actualizado`,
        accountDetail: (p: { currency: string; updated: boolean }) =>
            `Cuenta ${p.updated ? 'actualizada' : 'creada'} · ${p.currency}`,
        categoryDetail: (p: { updated: boolean }) =>
            `Categoría ${p.updated ? 'actualizada' : 'creada'}`,
        tagDetail: (p: { updated: boolean }) =>
            `Etiqueta ${p.updated ? 'actualizada' : 'creada'}`,
        editAccount: 'Editar cuenta',
        editCategory: 'Editar categoría',
        editTag: 'Editar etiqueta',
        accountSaved: 'Cuenta actualizada',
        categorySaved: 'Categoría actualizada',
        tagSaved: 'Etiqueta actualizada',
        parentTag: 'Etiqueta padre',
        noParentTag: 'Sin etiqueta padre',
    },

    addManual: {
        incomeLabel: 'Ingreso',
        incomeTitle: 'Añadir ingreso',
        incomeDescription:
            'Carga manualmente el dinero que entra a una cuenta.',
        expenseLabel: 'Gasto',
        expenseTitle: 'Añadir gasto',
        expenseDescription:
            'Carga manualmente el dinero que sale de una cuenta.',
        transferLabel: 'Transferencia',
        transferTitle: 'Añadir transferencia',
        transferDescription: 'Mueve dinero entre dos cuentas propias.',
        amount: 'Monto',
        outgoing: 'Sale',
        incoming: 'Entra',
        swapSides: 'Invertir origen y destino',
        account: 'Cuenta',
        recurringExpense: 'Gasto recurrente',
        recurringIncome: 'Ingreso recurrente',
        frequency: 'Frecuencia',
        recurrenceDaily: 'Diario',
        recurrenceWeekly: 'Semanal',
        recurrenceMonthly: 'Mensual',
        recurrenceYearly: 'Anual',
        recurrenceCustomDays: 'Cada X días',
        recurrenceEveryNDays: (days: number) => `Cada ${days} días`,
        recurrenceRepeatEvery: 'Repetir cada',
        recurrenceDaysUnit: 'días',
        recurrenceEndDateOptional: 'Fecha de fin (opcional)',
        recurrenceNoEndDate: 'Sin fecha de fin',
        recurrenceSpanDays: (value: number) => `${value} días`,
        recurrenceSpanMonths: (value: number) => `${value} meses`,
        recurrenceSpanYears: (value: number) => `${value} años`,
        recurrenceOpenEndedNote: (count: number, span: string) =>
            `Sin fecha de fin no es para siempre: se crean ${count} movimientos, que cubren unos ${span}. Podés agregar más cuando quieras.`,
        recurrenceTooLong: (max: number) =>
            `Esa fecha de fin crearía demasiados movimientos. El máximo para esta frecuencia es ${max}.`,
        newTransaction: 'Añadir movimiento',
        select: 'Seleccionar',
        newAccount: 'Nueva cuenta',
        date: 'Fecha',
        timeOptional: 'Hora (opcional)',
        noTime: 'Sin hora',
        removeTime: 'Quitar hora',
        title: 'Título',
        transferTitleFallback: 'Transferencia',
        titlePlaceholderIncome: 'Salario, devolución, intereses',
        titlePlaceholderExpense: 'Supermercado, taxi, alquiler',
        description: 'Descripción',
        descriptionPlaceholder: 'Detalle opcional',
        category: 'Categoría',
        newCategory: 'Nueva categoría',
        tags: 'Etiquetas',
        addTag: 'Agregar etiqueta',
        tagColorTitle: (p: { name: string }) => `Color de "${p.name}"`,
        submit: 'Anotar',
        saved: 'Movimiento anotado',
        saveFailed: 'No se pudo anotar el movimiento',
        selectAccount: 'Selecciona una cuenta',
        selectCategory: 'Selecciona una categoria',
        amountGreaterThanZero: 'El monto debe ser mayor a 0',
        titleRequired: 'El titulo es obligatorio',
        selectDestinationAccount: 'Selecciona una cuenta destino',
        distinctAccounts: 'Origen y destino deben ser cuentas distintas',
        destinationAmountGreaterThanZero: 'El monto destino debe ser mayor a 0',
        duplicateAccount: 'Ya existe una cuenta con ese nombre y moneda',
        duplicateCategory: 'Ya existe una categoría con ese nombre',
        accountAdded: 'Cuenta agregada al formulario',
        categoryAdded: 'Categoría agregada al formulario',
        accountNamePlaceholder: 'Ej: Efectivo, Banco Nación',
        categoryNamePlaceholder: 'Ej: Comida, Regalo, Freelance',
    },

    futureMovements: {
        selectDetail: 'Elegí un movimiento para ver su detalle',
        title: 'Movimientos futuros',
        info: 'Estos son tus movimientos futuros: los que todavía no ocurrieron. No aparecen en Actividad hasta que suceden.',
        empty: 'No tenés movimientos futuros programados',
        detail: 'Detalle',
        editMovement: 'Editar movimiento',
        edit: 'Editar',
        delete: 'Eliminar',
        close: 'Cerrar',
        titlePlaceholder: 'Título',
        amount: 'Monto',
        frequency: 'Frecuencia',
        date: 'Fecha',
        account: 'Cuenta',
        category: 'Categoría',
        description: 'Descripción',
        descriptionPlaceholder: 'Detalle opcional',
        noDescription: 'Sin descripción',
        seriesPosition: (p: { index: number; total: number }) =>
            `${p.index}/${p.total}`,
        coveredThrough: (date: string) => `hasta ${date}`,
        addMore: (p: { count: number }) => `Añadir ${p.count} más`,
        addMoreHint:
            'Los nuevos movimientos continúan a partir del último de la serie, no de este.',
        addingMore: 'Añadiendo movimientos…',
        addedMore: (p: { count: number }) =>
            `Se añadieron ${p.count} movimientos`,
        addMoreFailed: 'No se pudieron añadir los movimientos',
        saveChanges: 'Guardar cambios',
        deleteRecurring: 'Eliminar movimiento recurrente',
        titleRequired: 'El título es obligatorio',
        amountGreaterThanZero: 'El monto debe ser mayor a 0',
        savedOnlyThis: 'Cambios aplicados a este movimiento',
        savedAllFuture: 'Cambios aplicados a este y los futuros',
        deletedOnlyThis: 'Movimiento eliminado',
        deletedAllFuture: 'Movimiento y sus futuros eliminados',
        scopeEditDescription:
            '¿Aplicar los cambios solo a este movimiento o también a los futuros?',
        scopeDeleteDescription: (name: string) =>
            `¿Querés eliminar “${name}” solo esta vez o también los futuros?`,
        scopeOnlyThisUnavailable:
            'Cambiar la frecuencia siempre afecta a los movimientos futuros.',
        scopeOnlyThis: 'Solo este movimiento',
        scopeAllFuture: 'Este y los futuros',
        cancel: 'Cancelar',
        accountIdentity: (name: string) => `Cuenta: ${name}`,
        categoryIdentity: (name: string) => `Categoría: ${name}`,
    },
}

export type Messages = typeof es
