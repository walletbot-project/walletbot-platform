// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Wallet Bot';

  @override
  String get home => 'Inicio';

  @override
  String get activity => 'Actividad';

  @override
  String get accounts => 'Cuentas';

  @override
  String get insights => 'Organización';

  @override
  String get categories => 'Categorías';

  @override
  String get tags => 'Etiquetas';

  @override
  String get cancel => 'Cancelar';

  @override
  String get accept => 'Aceptar';

  @override
  String get apply => 'Aplicar';

  @override
  String get save => 'Guardar';

  @override
  String get add => 'Agregar';

  @override
  String get create => 'Crear';

  @override
  String get delete => 'Eliminar';

  @override
  String get remove => 'Quitar';

  @override
  String get edit => 'Editar';

  @override
  String get done => 'Listo';

  @override
  String get retry => 'Reintentar';

  @override
  String get reconnect => 'Reconectar';

  @override
  String get clear => 'Limpiar';

  @override
  String get select => 'Seleccionar';

  @override
  String get any => 'Cualquiera';

  @override
  String get all => 'Todos';

  @override
  String get viewAll => 'Ver todos';

  @override
  String get name => 'Nombre';

  @override
  String get nameRequiredLabel => 'Nombre *';

  @override
  String get enterName => 'Ingresá un nombre';

  @override
  String get description => 'Descripción';

  @override
  String get descriptionOptional => 'Descripción (opcional)';

  @override
  String get noDescription => 'Sin descripción';

  @override
  String get color => 'Color';

  @override
  String get icon => 'Ícono';

  @override
  String get iconAndColor => 'Ícono y color';

  @override
  String get chooseColor => 'Elegir color';

  @override
  String get chooseIcon => 'Elegir ícono';

  @override
  String get currency => 'Moneda';

  @override
  String get amount => 'Monto';

  @override
  String get time => 'Horario';

  @override
  String get date => 'Fecha';

  @override
  String get category => 'Categoría';

  @override
  String get account => 'Cuenta';

  @override
  String get exchangeRate => 'Tipo de cambio';

  @override
  String accountIdentity(String name) {
    return 'Cuenta: $name';
  }

  @override
  String categoryIdentity(String name) {
    return 'Categoría: $name';
  }

  @override
  String get detail => 'Detalle';

  @override
  String get editActivity => 'Editar actividad';

  @override
  String get activityGone => 'La actividad ya no existe';

  @override
  String get estimatedDate => 'Fecha estimada';

  @override
  String get estimatedTime => 'Horario estimado';

  @override
  String get sourceAccount => 'Cuenta origen';

  @override
  String get destinationAccount => 'Cuenta destino';

  @override
  String get noTags => 'Sin etiquetas';

  @override
  String get noCategory => 'Sin categoría';

  @override
  String get balanceUnavailable => 'Saldo no disponible';

  @override
  String get declaredBalance => 'Saldo declarado';

  @override
  String get platformBalance => 'Saldo calculado';

  @override
  String get sameAccounts => 'La cuenta origen y destino deben ser distintas';

  @override
  String get invalidAmount => 'El monto no es válido';

  @override
  String get noOtherAccount => 'No hay otra cuenta disponible';

  @override
  String get amountNotEditable =>
      'El monto de ajustes de saldo y balances iniciales no son editables.';

  @override
  String get change => 'Cambiar';

  @override
  String get activityUpdateFailed => 'No se pudo guardar la actividad';

  @override
  String get activityDeleteTitle => 'Eliminar actividad';

  @override
  String activityDeleteConfirm(String name) {
    return '¿Seguro que querés eliminar “$name”?';
  }

  @override
  String get activityDeleteFailed => 'No se pudo eliminar la actividad';

  @override
  String get status => 'Estado';

  @override
  String get type => 'Tipo';

  @override
  String get text => 'Texto';

  @override
  String get minimum => 'Mín';

  @override
  String get maximum => 'Máx';

  @override
  String get error => 'Error';

  @override
  String get optional => 'Opcional';

  @override
  String get timeOptional => 'Hora (opcional)';

  @override
  String get noTime => 'Sin hora';

  @override
  String get search => 'Buscar';

  @override
  String get loadingFailed => 'No se pudo cargar';

  @override
  String get voiceCommands => 'Comandos de voz';

  @override
  String get syncPaused =>
      'La sincronización está pausada — iniciá sesión de nuevo para reconectar';

  @override
  String reconnectFailed(Object error) {
    return 'No se pudo reconectar: $error';
  }

  @override
  String get sync => 'Sincronizar';

  @override
  String get syncing => 'Sincronizando…';

  @override
  String get synced => 'Sincronizado';

  @override
  String get syncError => 'Error de sincronización';

  @override
  String get tapToSync => 'Tocá para sincronizar';

  @override
  String get syncInProgress => 'Sincronización en curso';

  @override
  String get syncedTapAgain => 'Sincronizado. Tocá para volver a sincronizar.';

  @override
  String lastSynced(String time) {
    return 'Última sincronización hace $time. Tocá para volver a sincronizar.';
  }

  @override
  String get syncErrorRetry => 'Error de sincronización. Tocá para reintentar.';

  @override
  String syncErrorDetails(Object error) {
    return 'Error de sincronización: $error. Tocá para reintentar.';
  }

  @override
  String durationSeconds(int count) {
    return '$count s';
  }

  @override
  String durationMinutes(int count) {
    return '$count min';
  }

  @override
  String durationHours(int count) {
    return '$count h';
  }

  @override
  String durationDays(int count) {
    return '$count d';
  }

  @override
  String get yourAccounts => 'Tus cuentas';

  @override
  String get currentAccount => 'Cuenta actual';

  @override
  String get otherAccounts => 'Otras cuentas';

  @override
  String get chooseAccountToContinue =>
      'Elegí una cuenta para continuar, o agregá otra.';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get deleteLocalAccount => 'Eliminar esta cuenta';

  @override
  String signOutConfirmTitle(String name) {
    return '¿Cerrar sesión en «$name»?';
  }

  @override
  String get signOutConfirmBody =>
      'Se quitan de este dispositivo los datos de la cuenta. Tus datos siguen en tu cuenta: volvé a iniciar sesión para recuperarlos.';

  @override
  String get signOutUnsyncedWarning =>
      'Hay cambios que todavía no se sincronizaron. Si cerrás sesión ahora, se pierden para siempre.';

  @override
  String deleteLocalAccountConfirmTitle(String name) {
    return '¿Eliminar «$name»?';
  }

  @override
  String get deleteLocalAccountConfirmBody =>
      'Esta cuenta solo existe en este dispositivo. Al eliminarla, sus datos se borran para siempre: no hay copia en ningún otro lado.';

  @override
  String get settings => 'Configuración';

  @override
  String get language => 'Idioma';

  @override
  String get languageDescription =>
      'Elegí el idioma que se usa en toda la aplicación.';

  @override
  String get systemDefault => 'Predeterminado del sistema';

  @override
  String get english => 'Inglés';

  @override
  String get spanish => 'Español';

  @override
  String get theme => 'Tema';

  @override
  String get themeDescription =>
      'Elegí cómo se ve la aplicación en este dispositivo.';

  @override
  String get lightTheme => 'Claro';

  @override
  String get darkTheme => 'Oscuro';

  @override
  String get settingsSaveFailed =>
      'No se pudo guardar la configuración. Intentá de nuevo.';

  @override
  String get deleteUserAccount => 'Eliminar mi cuenta';

  @override
  String get deleteUserAccountDescription =>
      'Eliminá tu cuenta y todos tus datos para siempre';

  @override
  String get deleteUserAccountConfirmTitle => '¿Eliminar tu cuenta?';

  @override
  String deleteUserAccountConfirmBody(String email) {
    return 'Te vamos a enviar un enlace de confirmación a $email. Eliminar tu cuenta es permanente y no se puede deshacer.';
  }

  @override
  String get deleteUserAccountSend => 'Enviar enlace';

  @override
  String get deleteUserAccountEmailSent =>
      'Revisá tu correo: te enviamos un enlace para confirmar la eliminación.';

  @override
  String get deleteUserAccountFailed =>
      'No pudimos enviar el correo. Probá de nuevo en unos minutos.';

  @override
  String get deleteUserAccountAlreadyDeleted => 'Esa cuenta ya fue eliminada.';

  @override
  String get deleteUserAccountRateLimited =>
      'Ya pediste varios enlaces de eliminación. Esperá una hora y probá de nuevo.';

  @override
  String get accountDeletedBanner => 'Esta cuenta fue eliminada';

  @override
  String get accountDeletedRemove => 'Quitar';

  @override
  String get accountDeletedConfirmTitle =>
      '¿Quitar esta cuenta del dispositivo?';

  @override
  String get accountDeletedConfirmBody =>
      'La cuenta ya fue eliminada en el servidor. Esto borra también sus datos de este dispositivo, que son la última copia.';

  @override
  String get accountDeletedRemoveConfirm => 'Quitar';

  @override
  String get updateRequiredTitle => 'Actualización obligatoria';

  @override
  String get updateRequiredMessage =>
      'Actualizá la aplicación para seguir sincronizando tus datos.';

  @override
  String get updateAvailableTitle => 'Nueva versión disponible';

  @override
  String get updateAvailableMessage =>
      'Actualizá cuando puedas para recibir **las últimas mejoras**.';

  @override
  String get updateApp => 'Actualizar';

  @override
  String get openLinkFailed => 'No se pudo abrir el enlace';

  @override
  String get noName => 'Sin nombre';

  @override
  String get localAccount => 'Cuenta local';

  @override
  String get syncedAccount => 'Cuenta sincronizada';

  @override
  String get removeAccount => 'Quitar cuenta';

  @override
  String get addAccount => 'Agregar cuenta';

  @override
  String get thisAccount => 'esta cuenta';

  @override
  String removeAccountConfirmation(String name) {
    return 'Se eliminarán los datos de «$name» de este dispositivo. Esta acción no se puede deshacer.';
  }

  @override
  String removeAccountFailed(Object error) {
    return 'No se pudo quitar la cuenta: $error';
  }

  @override
  String get addWidget => 'Agregar widget';

  @override
  String get editWidget => 'Editar widget';

  @override
  String get editDashboard => 'Editar tablero';

  @override
  String get actions => 'Acciones';

  @override
  String get addManually => 'Agregar a mano';

  @override
  String get sendFeedback => 'Enviar comentarios';

  @override
  String get feedbackTitle => 'Enviar comentarios';

  @override
  String get feedbackSubtitle =>
      'Contanos qué salió mal o qué te gustaría ver. Podés adjuntar capturas o archivos.';

  @override
  String get feedbackMessageLabel => 'Tu comentario';

  @override
  String get feedbackMessageHint => '¿Qué querés contarnos?';

  @override
  String get feedbackAttach => 'Adjuntar archivos';

  @override
  String feedbackAttachmentsCount(int count, int max, String max_size) {
    return 'Adjuntos: $count/$max · hasta $max_size cada uno';
  }

  @override
  String get feedbackRemoveAttachment => 'Quitar adjunto';

  @override
  String get feedbackSend => 'Enviar';

  @override
  String get feedbackSending => 'Enviando comentarios…';

  @override
  String feedbackUploading(int current, int total) {
    return 'Subiendo archivo $current de $total…';
  }

  @override
  String get feedbackSent => '¡Gracias! Recibimos tus comentarios';

  @override
  String get feedbackSendFailed => 'No se pudieron enviar tus comentarios';

  @override
  String get feedbackMessageRequired => 'Escribí un comentario antes de enviar';

  @override
  String feedbackTooManyFiles(int max) {
    return 'Podés adjuntar hasta $max archivos';
  }

  @override
  String feedbackFileTooLarge(String name, String max_size) {
    return '“$name” supera el máximo de $max_size';
  }

  @override
  String get feedbackRateLimited =>
      'Ya enviaste varios comentarios. Probá de nuevo más tarde.';

  @override
  String get feedbackAttachmentRejected =>
      'No pudimos procesar los adjuntos. Quitalos e intentá de nuevo.';

  @override
  String get feedbackOffline =>
      'Sin conexión. Revisá tu internet e intentá de nuevo, o escribinos por email.';

  @override
  String get feedbackEmailInstead => 'Enviar un email en su lugar';

  @override
  String get feedbackEmailTitle => 'Escribir a soporte';

  @override
  String get feedbackEmailBody =>
      'Mandanos un email y te respondemos. Lo que ya escribiste va dentro del mensaje.';

  @override
  String get feedbackSupportEmail => 'soporte@walletbot.live';

  @override
  String get feedbackEmailOpen => 'Abrir app de email';

  @override
  String get feedbackEmailCopy => 'Copiar dirección';

  @override
  String get feedbackEmailCopied => 'Dirección copiada';

  @override
  String get feedbackEmailNoApp =>
      'No hay una app de email en este dispositivo. Copiá la dirección y escribinos desde donde quieras.';

  @override
  String get feedbackEmailSubject => 'Comentarios de Wallet Bot';

  @override
  String feedbackEmailBodyFooter(String client) {
    return 'Enviado desde Wallet Bot $client';
  }

  @override
  String get feedbackErrorDismiss => 'Cerrar este mensaje';

  @override
  String get addTransaction => 'Añadir movimiento';

  @override
  String get viewFutureMovements => 'Ver movimientos futuros';

  @override
  String transactionsLoadFailed(Object error) {
    return 'No se pudieron cargar las transacciones: $error';
  }

  @override
  String get noTransactions => 'No hay transacciones';

  @override
  String get noTransactionsYet => 'Sin transacciones todavía';

  @override
  String get selectTransactionDetail =>
      'Seleccioná una transacción para ver su detalle';

  @override
  String get selectAccountDetail => 'Seleccioná una cuenta para ver su detalle';

  @override
  String get selectCategoryDetail =>
      'Seleccioná una categoría para ver su detalle';

  @override
  String get selectTagDetail => 'Seleccioná una etiqueta para ver su detalle';

  @override
  String get accountDetails => 'Detalle de cuenta';

  @override
  String get categoryDetails => 'Detalle de categoría';

  @override
  String get tagDetails => 'Detalle de etiqueta';

  @override
  String get today => 'Hoy';

  @override
  String get yesterday => 'Ayer';

  @override
  String estimated(String date) {
    return '$date (estimado)';
  }

  @override
  String get transferSent => 'Transferencia enviada';

  @override
  String get transferReceived => 'Transferencia recibida';

  @override
  String get income => 'Ingreso';

  @override
  String get incomes => 'Ingresos';

  @override
  String get expense => 'Gasto';

  @override
  String get expenses => 'Gastos';

  @override
  String get transfer => 'Transferencia';

  @override
  String get transfers => 'Transferencias';

  @override
  String get balanceAdjustment => 'Ajuste de saldo';

  @override
  String get balanceAdjustments => 'Ajustes';

  @override
  String get initialBalance => 'Balance inicial';

  @override
  String get pending => 'Pendiente';

  @override
  String get cleared => 'Liquidado';

  @override
  String get thisWeek => 'Esta semana';

  @override
  String get thisMonth => 'Este mes';

  @override
  String get lastMonth => 'Mes pasado';

  @override
  String get thisYear => 'Este año';

  @override
  String get source => 'Origen';

  @override
  String get destination => 'Destino';

  @override
  String get either => 'Cualquiera';

  @override
  String get matchAny => 'Cualquiera';

  @override
  String get matchAll => 'Todas';

  @override
  String get newAccount => 'Nueva cuenta';

  @override
  String get newCategory => 'Nueva categoría';

  @override
  String get newTag => 'Nueva etiqueta';

  @override
  String get noAccountsTitle => 'No tenés cuentas aún';

  @override
  String get noAccountsBody =>
      'Creá tu primera cuenta para empezar a registrar tus gastos.';

  @override
  String get createAccount => 'Crear cuenta';

  @override
  String get accountsLoadFailed => 'No se pudieron cargar las cuentas';

  @override
  String get nameCannotBeEmpty => 'El nombre no puede estar vacío';

  @override
  String get accountSaveFailed => 'No se pudo guardar la cuenta';

  @override
  String get accountsReorderFailed =>
      'No se pudo guardar el nuevo orden de tus cuentas';

  @override
  String get adjustBalance => 'Ajustar saldo';

  @override
  String get adjustBalanceFailed => 'No se pudo ajustar el saldo';

  @override
  String get deleteAccount => 'Eliminar cuenta';

  @override
  String deleteAccountConfirmation(String name) {
    return '¿Seguro que querés eliminar «$name»? Dejará de aparecer en tus cuentas.';
  }

  @override
  String get deleteAccountFailed => 'No se pudo eliminar la cuenta';

  @override
  String get balance => 'Saldo';

  @override
  String get lastTransactions => 'Últimas transacciones';

  @override
  String get transactionsCouldNotLoad =>
      'No se pudieron cargar las transacciones';

  @override
  String get initialBalanceOptional => 'Balance inicial (opcional)';

  @override
  String get enterValidAmount => 'Ingresá un monto válido';

  @override
  String get accountCreateFailed => 'No se pudo crear la cuenta';

  @override
  String get accountDuplicateNameCurrency =>
      'Ya existe una cuenta con ese nombre y moneda';

  @override
  String get suggestions => 'Sugerencias';

  @override
  String get accountNameExample => 'Ej.: Efectivo, Banco Nación…';

  @override
  String get categoryNameExample => 'Ej.: Supermercado, Transporte…';

  @override
  String get chooseCurrency => 'Elegí una moneda';

  @override
  String get searchCurrency => 'Buscar moneda…';

  @override
  String get mostUsed => 'Más usadas';

  @override
  String get cash => 'Efectivo';

  @override
  String get bank => 'Banco';

  @override
  String get card => 'Tarjeta';

  @override
  String get groceries => 'Supermercado';

  @override
  String get transport => 'Transporte';

  @override
  String get services => 'Servicios';

  @override
  String get createCategory => 'Crear categoría';

  @override
  String get categoryCreateFailed => 'No se pudo crear la categoría';

  @override
  String get categoriesLoadFailed => 'No se pudieron cargar las categorías';

  @override
  String get noCategoriesTitle => 'No tenés categorías aún';

  @override
  String get noCategoriesBody =>
      'Creá una categoría para organizar tus movimientos.';

  @override
  String get deleteCategory => 'Eliminar categoría';

  @override
  String deleteCategoryConfirmation(String name) {
    return '¿Seguro que querés eliminar «$name»? Dejará de aparecer en tus categorías.';
  }

  @override
  String get deleteCategoryFailed => 'No se pudo eliminar la categoría';

  @override
  String get categorySaveFailed => 'No se pudo guardar la categoría';

  @override
  String get categoriesReorderFailed =>
      'No se pudo guardar el nuevo orden de tus categorías';

  @override
  String get latestMovements => 'Últimos movimientos';

  @override
  String get movementsLoadFailed => 'No se pudieron cargar los movimientos';

  @override
  String get noMovementsYet => 'Sin movimientos todavía';

  @override
  String movementCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count movimientos',
      one: '1 movimiento',
      zero: 'Sin movimientos',
    );
    return '$_temp0';
  }

  @override
  String get tagsLoadFailed => 'No se pudieron cargar las etiquetas.';

  @override
  String get noTagsYet => 'No hay etiquetas todavía.';

  @override
  String get deleteTag => 'Eliminar etiqueta';

  @override
  String deleteTagConfirmation(String name) {
    return '¿Seguro que querés eliminar «$name»? Dejará de aparecer en tus etiquetas.';
  }

  @override
  String get deleteTagWithChildren => 'Eliminar etiqueta con subetiquetas';

  @override
  String deleteTagWithChildrenPrompt(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count subetiquetas',
      one: '1 subetiqueta',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ellas',
      one: 'ella',
    );
    return '«$name» tiene $_temp0. ¿Qué hacemos con $_temp1?';
  }

  @override
  String get keepSubtags => 'Conservar subetiquetas';

  @override
  String get deleteEverything => 'Eliminar todo';

  @override
  String get spentThisMonth => 'GASTADO ESTE MES';

  @override
  String get noSpendingThisMonth => 'Sin gastos este mes';

  @override
  String otherCurrencies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count monedas más',
      one: '1 moneda más',
    );
    return '+ $_temp0';
  }

  @override
  String get createSubtag => 'Crear subetiqueta';

  @override
  String get parentTag => 'Etiqueta padre';

  @override
  String get chooseParentTag => 'Elegí la etiqueta padre';

  @override
  String get noParentTag => 'Sin etiqueta padre';

  @override
  String insideTag(String name) {
    return 'Dentro de $name';
  }

  @override
  String get searchHint => 'Buscar nombre o descripción…';

  @override
  String get filters => 'Filtros';

  @override
  String get simple => 'Simple';

  @override
  String get advanced => 'Avanzado';

  @override
  String get customRange => 'Rango personalizado';

  @override
  String get noAccountsYet => 'No hay cuentas todavía.';

  @override
  String get transferDirection => 'Dirección (para transferencias)';

  @override
  String get noCategoriesYet => 'No hay categorías todavía.';

  @override
  String get noCurrenciesYet => 'No hay monedas todavía.';

  @override
  String get selectCurrencyForAmount =>
      'Seleccioná una moneda para filtrar por monto.';

  @override
  String get subtags => 'Subetiquetas';

  @override
  String get showLess => 'Ver menos';

  @override
  String showMore(int count) {
    return 'Ver $count más';
  }

  @override
  String get advancedFilterNotice => 'Este filtro usa reglas avanzadas.';

  @override
  String get advancedFilterWarning =>
      'La vista simple no puede editar OR, NOT o grupos anidados sin cambiar el significado del filtro.';

  @override
  String get editAdvanced => 'Editar avanzado';

  @override
  String get createSimpleFilter => 'Crear filtro simple';

  @override
  String get deleteGroup => 'Eliminar grupo';

  @override
  String get addConditionToStart => 'Agregá una condición para empezar.';

  @override
  String get condition => 'Condición';

  @override
  String get group => 'Grupo';

  @override
  String get field => 'Campo';

  @override
  String get operator => 'Operador';

  @override
  String get operatorIncludes => 'incluye';

  @override
  String get operatorExcludes => 'excluye';

  @override
  String get operatorRelative => 'relativa';

  @override
  String get operatorBetween => 'entre';

  @override
  String get operatorGreaterEqual => 'mayor o igual';

  @override
  String get operatorLessEqual => 'menor o igual';

  @override
  String get operatorContains => 'contiene';

  @override
  String get operatorNotContains => 'no contiene';

  @override
  String get filterAnd => 'Y';

  @override
  String get filterOr => 'O';

  @override
  String get filterNot => 'NO';

  @override
  String get deleteCondition => 'Eliminar condición';

  @override
  String get direction => 'Dirección';

  @override
  String get match => 'Coincidencia';

  @override
  String get includeSubtags => 'Incluir subetiquetas';

  @override
  String get unsupportedField => 'Campo no soportado.';

  @override
  String get chooseRange => 'Elegir rango';

  @override
  String filterOptionsLoadFailed(Object error) {
    return 'No se pudieron cargar las opciones de filtro.\n$error';
  }

  @override
  String get newTransaction => 'Añadir movimiento';

  @override
  String get noTagsAvailable => 'No hay etiquetas disponibles';

  @override
  String tagCreateFailed(Object error) {
    return 'No se pudo crear la etiqueta: $error';
  }

  @override
  String colorFor(String name) {
    return 'Color de «$name»';
  }

  @override
  String get selectAccount => 'Seleccioná una cuenta';

  @override
  String get selectCategory => 'Seleccioná una categoría';

  @override
  String get selectDestinationAccount => 'Seleccioná una cuenta destino';

  @override
  String get differentTransferAccounts =>
      'Origen y destino deben ser cuentas distintas';

  @override
  String recordFailed(Object error) {
    return 'No se pudo guardar el movimiento: $error';
  }

  @override
  String get title => 'Título';

  @override
  String get titleRequired => 'El título es obligatorio';

  @override
  String get addTag => 'Agregar etiqueta';

  @override
  String get record => 'Anotar';

  @override
  String get recurringExpense => 'Gasto recurrente';

  @override
  String get recurringIncome => 'Ingreso recurrente';

  @override
  String get frequency => 'Frecuencia';

  @override
  String get recurrenceDaily => 'Diario';

  @override
  String get recurrenceWeekly => 'Semanal';

  @override
  String get recurrenceMonthly => 'Mensual';

  @override
  String get recurrenceYearly => 'Anual';

  @override
  String get recurrenceEndDateOptional => 'Fecha de fin (opcional)';

  @override
  String get recurrenceNoEndDate => 'Sin fecha de fin';

  @override
  String recurrenceSpanDays(int value) {
    return '$value días';
  }

  @override
  String recurrenceSpanMonths(int value) {
    return '$value meses';
  }

  @override
  String recurrenceSpanYears(int value) {
    return '$value años';
  }

  @override
  String recurrenceOpenEndedNote(int count, String span) {
    return 'Sin fecha de fin no es para siempre: se crean $count movimientos, que cubren unos $span. Podés agregar más cuando quieras.';
  }

  @override
  String recurrenceTooLong(int max) {
    return 'Esa fecha de fin crearía demasiados movimientos. El máximo para esta frecuencia es $max.';
  }

  @override
  String get recurrenceCustomDays => 'Cada X días';

  @override
  String get recurrenceRepeatEvery => 'Repetir cada';

  @override
  String get recurrenceDaysUnit => 'días';

  @override
  String recurrenceEveryNDays(int days) {
    return 'Cada $days días';
  }

  @override
  String get futureMovements => 'Movimientos futuros';

  @override
  String get futureMovementsInfo =>
      'Estos son tus movimientos futuros: los que todavía no ocurrieron. No aparecen en Actividad hasta que suceden.';

  @override
  String get noFutureMovements => 'No tenés movimientos futuros programados';

  @override
  String seriesPosition(int index, int total) {
    return '$index/$total';
  }

  @override
  String coveredThrough(String date) {
    return 'hasta $date';
  }

  @override
  String addMoreMovements(int count) {
    return 'Añadir $count más';
  }

  @override
  String get addMoreMovementsHint =>
      'Los nuevos movimientos continúan a partir del último de la serie, no de este.';

  @override
  String get addingMoreMovements => 'Añadiendo movimientos…';

  @override
  String addedMoreMovements(int count) {
    return 'Se añadieron $count movimientos';
  }

  @override
  String get addMoreMovementsFailed => 'No se pudieron añadir los movimientos';

  @override
  String get editMovement => 'Editar movimiento';

  @override
  String get titlePlaceholder => 'Título';

  @override
  String get descriptionPlaceholder => 'Detalle opcional';

  @override
  String get saveChanges => 'Guardar cambios';

  @override
  String get deleteRecurring => 'Eliminar movimiento recurrente';

  @override
  String get savedOnlyThis => 'Cambios aplicados a este movimiento';

  @override
  String get savedAllFuture => 'Cambios aplicados a este y los futuros';

  @override
  String get deletedOnlyThis => 'Movimiento eliminado';

  @override
  String get deletedAllFuture => 'Movimiento y sus futuros eliminados';

  @override
  String get scopeEditDescription =>
      '¿Aplicar los cambios solo a este movimiento o también a los futuros?';

  @override
  String scopeDeleteDescription(String name) {
    return '¿Querés eliminar “$name” solo esta vez o también los futuros?';
  }

  @override
  String get scopeOnlyThis => 'Solo este movimiento';

  @override
  String get scopeAllFuture => 'Este y los futuros';

  @override
  String get scopeOnlyThisUnavailable =>
      'Cambiar la frecuencia siempre afecta a los movimientos futuros.';

  @override
  String get leaves => 'Sale';

  @override
  String get enters => 'Entra';

  @override
  String get required => 'Obligatorio';

  @override
  String get greaterThanZero => 'Mayor a 0';

  @override
  String get amountRequired => 'El monto es obligatorio';

  @override
  String get amountGreaterThanZero => 'El monto debe ser mayor a 0';

  @override
  String get loginIntro => 'Empezá con sincronización o sin cuenta.';

  @override
  String get withAccount => 'Con cuenta';

  @override
  String get withoutAccount => 'Cuenta local';

  @override
  String get withAccountDescription =>
      'Usá correo o Google para sincronizar tus gastos.';

  @override
  String get localAccountDescription =>
      'Agregá un nombre antes de abrir este espacio del dispositivo.';

  @override
  String get email => 'Correo';

  @override
  String get password => 'Contraseña';

  @override
  String get enterYourName => 'Ingresá tu nombre';

  @override
  String get enterEmail => 'Ingresá tu correo';

  @override
  String get enterValidEmail => 'Ingresá un correo válido';

  @override
  String get enterPassword => 'Ingresá tu contraseña';

  @override
  String get passwordMinLength => 'Usá al menos 8 caracteres';

  @override
  String get or => 'o';

  @override
  String get continueWithGoogle => 'Continuar con Google';

  @override
  String get continueWithApple => 'Continuar con Apple';

  @override
  String get continueLocally => 'Continuar sin cuenta';

  @override
  String get needAccountSignUp => '¿Necesitás una cuenta? Registrate';

  @override
  String get haveAccountSignIn => '¿Ya tenés cuenta? Iniciá sesión';

  @override
  String get signIn => 'Iniciar sesión';

  @override
  String get signUp => 'Registrarme';

  @override
  String get signInAction => 'iniciar sesión';

  @override
  String get signUpAction => 'crear la cuenta';

  @override
  String get accountAlreadyAdded =>
      'Ya tenés una cuenta agregada con ese correo';

  @override
  String get accountExistsSignIn =>
      'Ya existe una cuenta con ese correo. Iniciá sesión con tu contraseña o con Google.';

  @override
  String get emailSignInFailedGoogleHint =>
      'No se pudo iniciar sesión. Si te registraste con Google, usá «Continuar con Google».';

  @override
  String emailAuthFailed(String action, Object error) {
    return 'No se pudo $action: $error';
  }

  @override
  String get forgotPassword => '¿Olvidaste tu contraseña?';

  @override
  String get resetPasswordTitle => 'Restablecer contraseña';

  @override
  String get resetPasswordSubtitle =>
      'Ingresá tu correo y te enviamos un enlace para restablecerla.';

  @override
  String get sendResetLink => 'Enviar enlace';

  @override
  String resetEmailSent(String email) {
    return 'Te enviamos un enlace a $email para restablecer tu contraseña. El enlace se abre en el navegador.';
  }

  @override
  String get resetEmailSentReturnHint =>
      'Cuando la restablezcas, volvé acá e iniciá sesión con tu contraseña nueva.';

  @override
  String resetRequestFailed(Object error) {
    return 'No se pudo enviar el correo de restablecimiento: $error';
  }

  @override
  String get backToSignIn => 'Volver a iniciar sesión';

  @override
  String get verifyEmailTitle => 'Verificá tu correo';

  @override
  String verifyEmailSent(String email) {
    return 'Te enviamos un enlace de verificación a $email. El enlace se abre en el navegador.';
  }

  @override
  String get verifyEmailInstructions =>
      'Abrí el enlace para verificar tu cuenta y después volvé acá a iniciar sesión.';

  @override
  String get verifyEmailDone => 'Ya verifiqué';

  @override
  String get resendVerificationEmail => 'Reenviar correo';

  @override
  String resendVerificationCooldown(int seconds) {
    return 'Reenviar en ${seconds}s';
  }

  @override
  String get verificationEmailResent =>
      'Te reenviamos el correo de verificación.';

  @override
  String resendVerificationFailed(Object error) {
    return 'No se pudo reenviar el correo: $error';
  }

  @override
  String get emailStillNotVerified =>
      'Ese correo todavía no está verificado. Te enviamos un enlace nuevo.';

  @override
  String accountNotFoundForEmail(String email) {
    return 'No existe una cuenta para $email.';
  }

  @override
  String get emailAlreadyVerified =>
      'Ese correo ya está verificado. Iniciá sesión con tu cuenta.';

  @override
  String get tooManyAttempts =>
      'Demasiados intentos. Esperá un minuto y probá de nuevo.';

  @override
  String get emailSendFailed =>
      'No pudimos enviar el correo. Probá de nuevo en unos minutos.';

  @override
  String localAccountFailed(Object error) {
    return 'No se pudo continuar sin cuenta: $error';
  }

  @override
  String googleSignInFailed(Object error) {
    return 'No se pudo iniciar sesión con Google: $error';
  }

  @override
  String appleSignInFailed(Object error) {
    return 'No se pudo iniciar sesión con Apple: $error';
  }

  @override
  String get close => 'Cerrar';

  @override
  String get newCategoryTooltip => 'Nueva categoría';

  @override
  String get newTagTooltip => 'Nueva etiqueta';

  @override
  String get addScreen => 'Pantalla para agregar';

  @override
  String get dashboardEmpty =>
      'Tu tablero está vacío. Agregá un widget para empezar.';

  @override
  String get dashboardLoadFailed => 'No se pudo cargar el tablero.';

  @override
  String get removeWidget => 'Quitar widget';

  @override
  String removeWidgetConfirmation(String title) {
    return '¿Quitar «$title» del tablero?';
  }

  @override
  String dashboardUpdateFailed(Object error) {
    return 'No se pudo actualizar el tablero: $error';
  }

  @override
  String widgetRemoveFailed(Object error) {
    return 'No se pudo quitar el widget: $error';
  }

  @override
  String get valueWidget => 'Valor';

  @override
  String get listWidget => 'Lista';

  @override
  String get balanceWidget => 'Saldo';

  @override
  String get chartWidget => 'Gráfico';

  @override
  String get widget => 'Widget';

  @override
  String get moveLeft => 'Mover a la izquierda';

  @override
  String get moveUp => 'Mover hacia arriba';

  @override
  String get moveDown => 'Mover hacia abajo';

  @override
  String get moveRight => 'Mover a la derecha';

  @override
  String get chartLoadFailed => 'No se pudo cargar el gráfico.';

  @override
  String get chartNoData => 'No hay datos para mostrar todavía.';

  @override
  String get uncategorized => 'Sin categoría';

  @override
  String get unknownAccount => 'Cuenta desconocida';

  @override
  String get enterWidgetTitle => 'Ingresá un título';

  @override
  String get selectWidgetCurrency => 'Seleccioná una moneda';

  @override
  String get configureWidgetFilter => 'Configurá un filtro para este widget';

  @override
  String widgetSaveFailed(Object error) {
    return 'No se pudo guardar el widget: $error';
  }

  @override
  String get widgetType => 'Tipo';

  @override
  String get widgetTitle => 'Título';

  @override
  String get background => 'Fondo';

  @override
  String get low => 'Bajo';

  @override
  String get high => 'Alto';

  @override
  String get belowLow => 'Menor que bajo';

  @override
  String get betweenLowHigh => 'Entre bajo y alto';

  @override
  String get aboveHigh => 'Mayor que alto';

  @override
  String get aggregation => 'Agregación';

  @override
  String get transactionCount => 'Cantidad de movimientos';

  @override
  String get groupBy => 'Agrupar por';

  @override
  String get chartType => 'Tipo de gráfico';

  @override
  String get noAccountsUseArs => 'No hay cuentas todavía; se usará ARS.';

  @override
  String get widgetWidth => 'Ancho';

  @override
  String get widgetAccountsAllHint => 'Todas las cuentas de esta moneda.';

  @override
  String get widgetAccountsScopedHint => 'Solo las cuentas seleccionadas.';

  @override
  String get noColor => 'Sin color';

  @override
  String get editFilter => 'Editar filtro';

  @override
  String get removeFilter => 'Quitar filtro';

  @override
  String get configureFilter => 'Configurar filtro';

  @override
  String get addWidgetAction => 'Agregar';

  @override
  String get saveWidgetAction => 'Guardar';

  @override
  String get widgetTypeStat => 'Valor';

  @override
  String get widgetTypeList => 'Movimientos';

  @override
  String get widgetTypeBalance => 'Saldo';

  @override
  String get widgetTypeBalanceComparison => 'Comparación de saldo';

  @override
  String get dashboardLastMonthBalance => 'Saldo del mes pasado';

  @override
  String get dashboardCurrentBalance => 'Saldo actual';

  @override
  String get dashboardBalanceDifference => 'Diferencia';

  @override
  String get widgetTypeChart => 'Gráfico';

  @override
  String get aggregationSum => 'Suma';

  @override
  String get aggregationNet => 'Neto';

  @override
  String get aggregationCount => 'Cantidad';

  @override
  String get groupCategory => 'Categoría';

  @override
  String get groupAccount => 'Cuenta';

  @override
  String get groupMonth => 'Mes';

  @override
  String get chartPie => 'Torta';

  @override
  String get chartBar => 'Barras';

  @override
  String get chartLine => 'Líneas';

  @override
  String get defaultExpensesMonth => 'Gastos del mes';

  @override
  String get defaultIncomeMonth => 'Ingresos del mes';

  @override
  String get defaultMovementsMonth => 'Movimientos del mes';

  @override
  String get defaultTotalBalanceArs => 'Saldo total (ARS)';

  @override
  String get defaultMovements => 'Movimientos';

  @override
  String get defaultRecentMovements => 'Movimientos recientes';

  @override
  String get liveVoice => 'Habla con Gaston';

  @override
  String get endSession => 'Finalizar sesión';

  @override
  String get you => 'Vos';

  @override
  String get agentInterrupted => 'Agente interrumpido';

  @override
  String get interrupted => '(interrumpido)';

  @override
  String get toolRunning => 'En curso';

  @override
  String get toolDone => 'Listo';

  @override
  String get toolCancelled => 'Cancelado';

  @override
  String get tool => 'Herramienta';

  @override
  String get arguments => 'argumentos';

  @override
  String get result => 'resultado';

  @override
  String get connectionLostReconnecting =>
      'Se perdió la conexión. Reconectando automáticamente…';

  @override
  String get typeMessage => 'Escribí un mensaje…';

  @override
  String get voiceWelcomeTitle => '¿En qué te ayudo?';

  @override
  String get voiceWelcome => 'Contame un gasto o preguntame por tus cuentas';

  @override
  String get voiceStartTalking => 'Empezar a hablar';

  @override
  String get voiceHoldHint => 'Apretá una vez o mantené apretado para hablar';

  @override
  String get voicePreparingMic => 'Preparando el micrófono';

  @override
  String get voiceListening => 'Te escucho';

  @override
  String get voiceMicPaused => 'Micrófono en pausa';

  @override
  String get voiceSlideToLock => 'Deslizá para bloquear';

  @override
  String get voicePause => 'Pausar';

  @override
  String get voiceResume => 'Continuar';

  @override
  String get voiceSwitchToText => 'Pasar a texto';

  @override
  String get voiceSend => 'Enviar';

  @override
  String suggestionLogExpense(String amount, String category) {
    return 'Gasté $amount en $category';
  }

  @override
  String suggestionLogExpenseWithAccount(
    String amount,
    String category,
    String account,
  ) {
    return 'Gasté $amount en $category con $account';
  }

  @override
  String suggestionSpentInCategoryThisMonth(String category) {
    return '¿Cuánto gasté en $category este mes?';
  }

  @override
  String suggestionAccountBalance(String account) {
    return '¿Cuánto tengo en $account?';
  }

  @override
  String get suggestionTopSpendingThisMonth => '¿En qué gasté más este mes?';

  @override
  String suggestionCompareCategoryLastMonth(String category) {
    return '¿Gasté más en $category que el mes pasado?';
  }

  @override
  String suggestionTransfer(String amount, String account, String toAccount) {
    return 'Pasé $amount de $account a $toAccount';
  }

  @override
  String suggestionLogIncome(String amount, String account) {
    return 'Cobré $amount en $account';
  }

  @override
  String suggestionSpentWithTag(String tag) {
    return '¿Cuánto gasté con la etiqueta $tag?';
  }

  @override
  String get suggestionRecentExpenses => '¿Cuáles fueron mis últimos gastos?';

  @override
  String get suggestionWhatCanYouDo => '¿Qué podés hacer?';

  @override
  String get suggestionCreateCashAccount => 'Creá una cuenta de efectivo';

  @override
  String get suggestionSetupCategories => 'Ayudame a armar mis categorías';

  @override
  String get suggestionHowToLogExpense => '¿Cómo anoto un gasto?';

  @override
  String get suggestionHomeWidget =>
      'Agregá un widget en Inicio con mis gastos del mes';

  @override
  String suggestionHomeWidgetForCategory(String category) {
    return 'Agregá un widget en Inicio con mis gastos en $category';
  }

  @override
  String get microphonePermissionDenied => 'Se denegó el permiso del micrófono';

  @override
  String get recorderPermissionFailed =>
      'No se pudo verificar el permiso del micrófono';

  @override
  String get pcmUnsupported =>
      'Este dispositivo no admite streaming PCM de 16 bits';

  @override
  String get voiceStartFailed =>
      'No se pudo iniciar la conversación. Intentá de nuevo.';

  @override
  String get voiceUnavailable =>
      'Gastón no está disponible en este momento. Probá de nuevo en unos minutos.';

  @override
  String get voiceRequiresAccount =>
      'Gastón necesita una cuenta. Iniciá sesión para conversar.';

  @override
  String microphoneOpenFailed(Object error) {
    return 'No se pudo abrir el micrófono: $error';
  }

  @override
  String audioStreamFailed(Object error) {
    return 'Error del audio: $error';
  }

  @override
  String toolResponseUnmatched(Object result) {
    return 'Respuesta de herramienta sin llamada coincidente: $result';
  }

  @override
  String toolCallsCancelled(String ids) {
    return 'Llamadas de herramientas canceladas: $ids';
  }

  @override
  String get deletedAccount => 'Cuenta eliminada';

  @override
  String transactionSaved(String type, String updated, String date) {
    String _temp0 = intl.Intl.selectLogic(updated, {
      'true': 'Se actualizó',
      'other': 'Se registró',
    });
    return '$_temp0: $type · $date';
  }

  @override
  String editTransactionType(String type) {
    return 'Editar $type';
  }

  @override
  String get chooseCategory => 'Elegí una categoría';

  @override
  String get transactionSaveFailed => 'No se pudo guardar la transacción';

  @override
  String get accountCreated => 'Cuenta creada';

  @override
  String get accountUpdated => 'Cuenta actualizada';

  @override
  String get categoryCreated => 'Categoría creada';

  @override
  String get categoryUpdated => 'Categoría actualizada';

  @override
  String get tagCreated => 'Etiqueta creada';

  @override
  String get tagUpdated => 'Etiqueta actualizada';

  @override
  String get editAccount => 'Editar cuenta';

  @override
  String get editCategory => 'Editar categoría';

  @override
  String get editTag => 'Editar etiqueta';

  @override
  String get tagSaveFailed => 'No se pudo guardar la etiqueta';

  @override
  String get tagsReorderFailed =>
      'No se pudo guardar el nuevo orden de tus etiquetas';

  @override
  String get legalFirstTitle => 'Antes de empezar';

  @override
  String get legalFirstSubtitle =>
      'Necesitamos tu aceptación para crear tu cuenta y darte el servicio.';

  @override
  String get legalUpdatedTermsTitle => 'Actualizamos los Términos';

  @override
  String get legalUpdatedPrivacyTitle =>
      'Actualizamos la Política de Privacidad';

  @override
  String get legalUpdatedBothTitle =>
      'Actualizamos los Términos y la Privacidad';

  @override
  String get legalUpdatedSubtitle =>
      'Revisá los cambios y aceptalos para seguir usando Wallet Bot.';

  @override
  String get legalUpdatedSubtitleGrace =>
      'Podés seguir usando la app por ahora, pero vamos a necesitar tu aceptación.';

  @override
  String get legalAgeConfirm => 'Tengo 18 años o más';

  @override
  String get legalAcceptTerms => 'Acepto los [[terms]]';

  @override
  String get legalAcceptPrivacy => 'Acepto la [[privacy]]';

  @override
  String get legalAcceptBoth => 'Acepto los [[terms]] y la [[privacy]]';

  @override
  String get legalTermsName => 'Términos y Condiciones';

  @override
  String get legalPrivacyName => 'Política de Privacidad';

  @override
  String get legalAcceptAction => 'Aceptar y continuar';

  @override
  String get legalLater => 'Más tarde';

  @override
  String get legalUseAnotherAccount => 'Usar otra cuenta';

  @override
  String get legalAcceptFailed =>
      'No pudimos registrar tu aceptación. Revisá tu conexión e intentá de nuevo.';

  @override
  String get actionLoadFailed => 'No se pudo cargar la acción';

  @override
  String get tapToRetry => 'Tocá para volver a intentar';

  @override
  String get reportResponseAction => 'Reportar esta respuesta';

  @override
  String get reportResponseCopy => 'Copiar';

  @override
  String get reportResponseCopied => 'Respuesta copiada';

  @override
  String get reportResponseMenuItem => 'Reportar una respuesta';

  @override
  String get reportResponseBadge => 'Reportada';

  @override
  String get reportResponseTitle => 'Reportar una respuesta';

  @override
  String get reportResponseSubtitle =>
      'Contanos qué estuvo mal con lo que respondió Gaston. Lo revisamos para corregir el asistente.';

  @override
  String get reportResponseSessionSubtitle =>
      'Reportá esta conversación cuando la respuesta fue solo por voz o ya quedó demasiado arriba.';

  @override
  String get reportResponseReasonLabel => 'Motivo';

  @override
  String get reportReasonOffensive => 'Ofensiva, agresiva o violenta';

  @override
  String get reportReasonSexual => 'Contenido sexual';

  @override
  String get reportReasonDangerous => 'Peligrosa o ilegal';

  @override
  String get reportReasonMisleading => 'Información financiera falsa';

  @override
  String get reportReasonPrivacy => 'Mostró datos que no correspondían';

  @override
  String get reportReasonOther => 'Otro';

  @override
  String get reportResponseReasonRequired => 'Elegí un motivo antes de enviar';

  @override
  String get reportResponseNoteLabel => 'Detalle (opcional)';

  @override
  String get reportResponseNoteHint => '¿Qué pasó?';

  @override
  String get reportResponseReportedTextLabel => 'Respuesta reportada';

  @override
  String get reportResponseSessionNotice =>
      'Se envía la conversación de esta sesión, sin el audio.';

  @override
  String get reportResponsePrivacyNotice =>
      'Enviamos el texto de arriba junto con el modelo y la versión de la app. El audio nunca sale de tu dispositivo.';

  @override
  String get reportResponseSend => 'Enviar reporte';

  @override
  String get reportResponseSending => 'Enviando reporte…';

  @override
  String get reportResponseSent => 'Gracias. Vamos a revisar esta respuesta';

  @override
  String get reportResponseFailed => 'No pudimos enviar el reporte';

  @override
  String get reportResponseRateLimited =>
      'Ya enviaste varios reportes. Probá de nuevo más tarde.';

  @override
  String get reportResponseOffline =>
      'Sin conexión. Revisá tu internet y probá de nuevo.';

  @override
  String get reportResponseInvalid =>
      'No pudimos procesar este reporte. Probá de nuevo.';

  @override
  String get reportResponseNoResponseYet =>
      'Todavía no hay ninguna respuesta para reportar';

  @override
  String get whatsappTitle => 'WhatsApp';

  @override
  String get whatsappLocalAccountTitle => 'No disponible en cuentas locales';

  @override
  String get whatsappLocalAccountBody =>
      'Este espacio vive sólo en tu dispositivo, así que no hay cuenta para vincular. Iniciá sesión para sincronizarlo.';

  @override
  String get whatsappLoadFailed => 'No se pudo cargar tu estado de WhatsApp';

  @override
  String get whatsappUnavailableTitle => 'Todavía no disponible';

  @override
  String get whatsappUnavailableBody =>
      'WhatsApp no está configurado en este servidor. Probá más tarde.';

  @override
  String get whatsappNotConnectedTitle => 'Sin conectar';

  @override
  String get whatsappNotConnectedBody =>
      'Vinculá tu número para registrar gastos chateando con Gaston por WhatsApp.';

  @override
  String get whatsappConnect => 'Conectar WhatsApp';

  @override
  String get whatsappCodeLabel => 'Tu código de vinculación';

  @override
  String get whatsappCodeExpiryHint =>
      'Vale 10 minutos y se puede usar una sola vez.';

  @override
  String get whatsappOpenWhatsapp => 'Abrir WhatsApp';

  @override
  String get whatsappCopyCode => 'Copiar código';

  @override
  String get whatsappCodeCopied => 'Código copiado';

  @override
  String get whatsappCodeFailed => 'No se pudo crear el código de vinculación';

  @override
  String get whatsappOpenFailed =>
      'No se pudo abrir WhatsApp. Copiá el código y enviálo a mano.';

  @override
  String get whatsappConnectedTitle => 'Conectado';

  @override
  String get whatsappConnectedBody =>
      'Escribile a Gaston por WhatsApp y va a registrar tus movimientos.';

  @override
  String whatsappLinkedOn(String date) {
    return 'Vinculado el $date';
  }

  @override
  String get whatsappDisconnect => 'Desconectar';

  @override
  String get whatsappDisconnectConfirm =>
      'Gaston va a dejar de responderle a este número hasta que lo vincules de nuevo.';

  @override
  String get whatsappDisconnectFailed => 'No se pudo desconectar el número';

  @override
  String get aiConsentTitle => 'Antes de usar el asistente';

  @override
  String get aiConsentIntro =>
      'El asistente envía lo que decís y parte de tus datos de Wallet Bot a nuestros proveedores de IA, Google LLC (Gemini) y OpenAI, LLC, en Estados Unidos.';

  @override
  String get aiConsentMicTitle => 'Te vamos a pedir el micrófono';

  @override
  String get aiConsentMicBody =>
      'iOS lo pide cuando empezás una conversación por voz. Escribirle al asistente no necesita micrófono.';

  @override
  String get aiConsentWhatWeSend => 'Qué se envía';

  @override
  String get aiConsentItemAudio =>
      'Tu voz mientras hay una conversación abierta, y lo que escribís.';

  @override
  String get aiConsentItemProfile => 'Tu nombre y tu correo.';

  @override
  String get aiConsentItemFinancial =>
      'Tus cuentas, categorías, etiquetas y movimientos recientes.';

  @override
  String get aiConsentItemMemories =>
      'Las notas que el asistente guardó sobre vos.';

  @override
  String get aiConsentItemActions => 'Los registros que crea o modifica.';

  @override
  String get aiConsentReadPolicy => 'Leer la Política de Privacidad';

  @override
  String get aiConsentDecline => 'Ahora no';

  @override
  String get aiConsentAccept => 'Aceptar y continuar';

  @override
  String get aiConsentFailed =>
      'No se pudo registrar tu permiso. Revisá tu conexión y probá de nuevo.';

  @override
  String get aiConsentDeclined =>
      'Necesitás aceptar para que el asistente funcione.';
}
