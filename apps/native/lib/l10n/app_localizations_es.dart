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
  String get date => 'Fecha';

  @override
  String get category => 'Categoría';

  @override
  String get account => 'Cuenta';

  @override
  String get exchangeRate => 'Tipo de cambio';

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
  String get addTransaction => 'Añadir movimiento';

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
  String get liveVoice => 'Voz en vivo';

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
  String get connected => 'conectado';

  @override
  String get connecting => 'conectando';

  @override
  String get idle => 'inactivo';

  @override
  String get connectionLostReconnecting =>
      'Se perdió la conexión. Reconectando automáticamente…';

  @override
  String get connectingPrompt => 'Conectando…';

  @override
  String get voiceStartPrompt =>
      'Tocá el micrófono para iniciar una conversación';

  @override
  String get typeMessage => 'Escribí un mensaje…';

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
}
