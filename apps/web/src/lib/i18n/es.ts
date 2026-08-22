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
        insights: 'Análisis',
        addWithGasti: 'Añadir con Gasti',
        addManually: 'Añadir manualmente',
        signOut: 'Cerrar sesión',
        language: 'Idioma',
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
        featureFlags: 'Feature flags',
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

        aggregation: 'Agregación',
        aggregationSum: 'Suma',
        aggregationNet: 'Neto',
        aggregationCount: 'Cantidad',
        rowLimit: 'Cantidad de filas',

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
        title: 'Voz en vivo',
        statusIdle: 'inactivo',
        statusConnecting: 'conectando',
        statusConnected: 'conectado',
        speaking: 'Hablando',
        you: 'Vos',
        agent: 'WalletBot',
        interrupted: '(interrumpido)',
        tool: 'Herramienta',
        toolRunning: 'Ejecutando',
        toolDone: 'Listo',
        toolCancelled: 'Cancelado',
        connectingEllipsis: 'Conectando…',
        tapToStart: 'Tocá el micrófono o escribí un mensaje para empezar',
        microphone: 'Micrófono',
        mute: 'Silenciar',
        unmute: 'Activar micrófono',
        connect: 'Conectar',
        disconnect: 'Desconectar',
        startConversation: 'Iniciar una conversación',
        endSession: 'Finalizar sesión',
        typeMessage: 'Escribí un mensaje…',
        send: 'Enviar',
        systemConnecting: 'Conectando…',
        systemTokenReceived: (p: { model: string }) =>
            `Token recibido para ${p.model}`,
        systemSocketError: 'Error de WebSocket',
        systemDisconnected: 'Desconectado',
        systemConnected: 'Conectado. Podés hablar.',
        systemConnectedTyping: 'Conectado. Enviando tu mensaje…',
        systemConnectionFailed: (p: { error: string }) =>
            `Falló la conexión: ${p.error}`,
        systemMicOpenFailed: (p: { error: string }) =>
            `No se pudo abrir el micrófono: ${p.error}`,
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
}

export type Messages = typeof es
