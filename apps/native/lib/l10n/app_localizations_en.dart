// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Wallet Bot';

  @override
  String get home => 'Home';

  @override
  String get activity => 'Activity';

  @override
  String get accounts => 'Accounts';

  @override
  String get insights => 'Organization';

  @override
  String get categories => 'Categories';

  @override
  String get tags => 'Tags';

  @override
  String get cancel => 'Cancel';

  @override
  String get accept => 'Accept';

  @override
  String get apply => 'Apply';

  @override
  String get save => 'Save';

  @override
  String get add => 'Add';

  @override
  String get create => 'Create';

  @override
  String get delete => 'Delete';

  @override
  String get remove => 'Remove';

  @override
  String get edit => 'Edit';

  @override
  String get done => 'Done';

  @override
  String get retry => 'Retry';

  @override
  String get reconnect => 'Reconnect';

  @override
  String get clear => 'Clear';

  @override
  String get select => 'Select';

  @override
  String get any => 'Any';

  @override
  String get all => 'All';

  @override
  String get viewAll => 'View all';

  @override
  String get name => 'Name';

  @override
  String get nameRequiredLabel => 'Name *';

  @override
  String get enterName => 'Enter a name';

  @override
  String get description => 'Description';

  @override
  String get descriptionOptional => 'Description (optional)';

  @override
  String get noDescription => 'No description';

  @override
  String get color => 'Color';

  @override
  String get icon => 'Icon';

  @override
  String get iconAndColor => 'Icon and color';

  @override
  String get chooseColor => 'Choose a color';

  @override
  String get chooseIcon => 'Choose an icon';

  @override
  String get currency => 'Currency';

  @override
  String get amount => 'Amount';

  @override
  String get date => 'Date';

  @override
  String get category => 'Category';

  @override
  String get account => 'Account';

  @override
  String get exchangeRate => 'Exchange rate';

  @override
  String get status => 'Status';

  @override
  String get type => 'Type';

  @override
  String get text => 'Text';

  @override
  String get minimum => 'Min';

  @override
  String get maximum => 'Max';

  @override
  String get error => 'Error';

  @override
  String get optional => 'Optional';

  @override
  String get timeOptional => 'Time (optional)';

  @override
  String get noTime => 'No time';

  @override
  String get search => 'Search';

  @override
  String get loadingFailed => 'Could not load';

  @override
  String get voiceCommands => 'Voice commands';

  @override
  String get syncPaused => 'Sync paused — sign in again to reconnect';

  @override
  String reconnectFailed(Object error) {
    return 'Could not reconnect: $error';
  }

  @override
  String get sync => 'Sync';

  @override
  String get syncing => 'Syncing…';

  @override
  String get synced => 'Synced';

  @override
  String get syncError => 'Sync error';

  @override
  String get tapToSync => 'Tap to sync';

  @override
  String get syncInProgress => 'Sync in progress';

  @override
  String get syncedTapAgain => 'Synced. Tap to sync again.';

  @override
  String lastSynced(String time) {
    return 'Last synced $time ago. Tap to sync again.';
  }

  @override
  String get syncErrorRetry => 'Sync error. Tap to retry.';

  @override
  String syncErrorDetails(Object error) {
    return 'Sync error: $error. Tap to retry.';
  }

  @override
  String durationSeconds(int count) {
    return '${count}s';
  }

  @override
  String durationMinutes(int count) {
    return '${count}m';
  }

  @override
  String durationHours(int count) {
    return '${count}h';
  }

  @override
  String durationDays(int count) {
    return '${count}d';
  }

  @override
  String get yourAccounts => 'Your accounts';

  @override
  String get currentAccount => 'Current account';

  @override
  String get otherAccounts => 'Other accounts';

  @override
  String get chooseAccountToContinue =>
      'Choose an account to continue, or add another one.';

  @override
  String get signOut => 'Sign out';

  @override
  String get deleteLocalAccount => 'Delete this account';

  @override
  String signOutConfirmTitle(String name) {
    return 'Sign out of “$name”?';
  }

  @override
  String get signOutConfirmBody =>
      'This removes the account\'s data from this device. Your data stays in your account — sign in again to bring it back.';

  @override
  String get signOutUnsyncedWarning =>
      'Some changes have not synced yet. Signing out now discards them for good.';

  @override
  String deleteLocalAccountConfirmTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get deleteLocalAccountConfirmBody =>
      'This account only exists on this device. Deleting it erases its data for good — there is no copy anywhere else.';

  @override
  String get settings => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get languageDescription =>
      'Choose the language used throughout the app.';

  @override
  String get systemDefault => 'System default';

  @override
  String get english => 'English';

  @override
  String get spanish => 'Spanish';

  @override
  String get theme => 'Theme';

  @override
  String get themeDescription => 'Choose how the app looks on this device.';

  @override
  String get lightTheme => 'Light';

  @override
  String get darkTheme => 'Dark';

  @override
  String get settingsSaveFailed => 'Could not save the setting. Try again.';

  @override
  String get deleteUserAccount => 'Delete my account';

  @override
  String get deleteUserAccountDescription =>
      'Permanently delete your account and all your data';

  @override
  String get deleteUserAccountConfirmTitle => 'Delete your account?';

  @override
  String deleteUserAccountConfirmBody(String email) {
    return 'We will send a confirmation link to $email. Deleting your account is permanent and cannot be undone.';
  }

  @override
  String get deleteUserAccountSend => 'Send link';

  @override
  String get deleteUserAccountEmailSent =>
      'Check your email: we sent you a link to confirm the deletion.';

  @override
  String get deleteUserAccountFailed =>
      'Could not send the email. Try again in a few minutes.';

  @override
  String get deleteUserAccountAlreadyDeleted =>
      'That account was already deleted.';

  @override
  String get deleteUserAccountRateLimited =>
      'You already requested several deletion links. Wait an hour and try again.';

  @override
  String get accountDeletedBanner => 'This account was deleted';

  @override
  String get accountDeletedRemove => 'Remove';

  @override
  String get accountDeletedConfirmTitle =>
      'Remove this account from the device?';

  @override
  String get accountDeletedConfirmBody =>
      'The account is already deleted on the server. This erases its data from this device too, which is the last copy.';

  @override
  String get accountDeletedRemoveConfirm => 'Remove';

  @override
  String get updateRequiredTitle => 'Update required';

  @override
  String get updateRequiredMessage =>
      'Update the app to continue syncing your data.';

  @override
  String get updateAvailableTitle => 'New version available';

  @override
  String get updateAvailableMessage =>
      'Update when you can to receive **the latest improvements**.';

  @override
  String get updateApp => 'Update';

  @override
  String get openLinkFailed => 'Could not open the link';

  @override
  String get noName => 'No name';

  @override
  String get localAccount => 'Local account';

  @override
  String get syncedAccount => 'Synced account';

  @override
  String get removeAccount => 'Remove account';

  @override
  String get addAccount => 'Add account';

  @override
  String get thisAccount => 'this account';

  @override
  String removeAccountConfirmation(String name) {
    return 'The data for “$name” will be removed from this device. This action cannot be undone.';
  }

  @override
  String removeAccountFailed(Object error) {
    return 'Could not remove the account: $error';
  }

  @override
  String get addWidget => 'Add widget';

  @override
  String get editWidget => 'Edit widget';

  @override
  String get editDashboard => 'Edit dashboard';

  @override
  String get actions => 'Actions';

  @override
  String get addManually => 'Add manually';

  @override
  String get sendFeedback => 'Send feedback';

  @override
  String get feedbackTitle => 'Send feedback';

  @override
  String get feedbackSubtitle =>
      'Tell us what went wrong or what you would like to see. You can attach screenshots or files.';

  @override
  String get feedbackMessageLabel => 'Your feedback';

  @override
  String get feedbackMessageHint => 'What would you like to tell us?';

  @override
  String get feedbackAttach => 'Attach files';

  @override
  String feedbackAttachmentsCount(int count, int max, String max_size) {
    return 'Attachments: $count/$max · up to $max_size each';
  }

  @override
  String get feedbackRemoveAttachment => 'Remove attachment';

  @override
  String get feedbackSend => 'Send';

  @override
  String get feedbackSending => 'Sending feedback…';

  @override
  String feedbackUploading(int current, int total) {
    return 'Uploading file $current of $total…';
  }

  @override
  String get feedbackSent => 'Thank you! We got your feedback';

  @override
  String get feedbackSendFailed => 'Could not send your feedback';

  @override
  String get feedbackMessageRequired => 'Write your feedback before sending';

  @override
  String feedbackTooManyFiles(int max) {
    return 'You can attach up to $max files';
  }

  @override
  String feedbackFileTooLarge(String name, String max_size) {
    return '“$name” is larger than the $max_size limit';
  }

  @override
  String get feedbackRateLimited =>
      'You have sent several messages already. Try again later.';

  @override
  String get feedbackAttachmentRejected =>
      'We could not process the attachments. Remove them and try again.';

  @override
  String get feedbackOffline =>
      'No connection. Check your internet and try again, or write to us by email.';

  @override
  String get feedbackEmailInstead => 'Send an email instead';

  @override
  String get feedbackEmailTitle => 'Write to support';

  @override
  String get feedbackEmailBody =>
      'Send us an email and we will get back to you. Whatever you already typed goes into the message.';

  @override
  String get feedbackSupportEmail => 'support@walletbot.live';

  @override
  String get feedbackEmailOpen => 'Open email app';

  @override
  String get feedbackEmailCopy => 'Copy address';

  @override
  String get feedbackEmailCopied => 'Address copied';

  @override
  String get feedbackEmailNoApp =>
      'No email app on this device. Copy the address and write to us from anywhere.';

  @override
  String get feedbackEmailSubject => 'Wallet Bot feedback';

  @override
  String feedbackEmailBodyFooter(String client) {
    return 'Sent from Wallet Bot $client';
  }

  @override
  String get feedbackErrorDismiss => 'Dismiss this message';

  @override
  String get addTransaction => 'Add transaction';

  @override
  String transactionsLoadFailed(Object error) {
    return 'Could not load transactions: $error';
  }

  @override
  String get noTransactions => 'No transactions';

  @override
  String get noTransactionsYet => 'No transactions yet';

  @override
  String get selectTransactionDetail =>
      'Select a transaction to see its details';

  @override
  String get selectAccountDetail => 'Select an account to see its details';

  @override
  String get selectCategoryDetail => 'Select a category to see its details';

  @override
  String get selectTagDetail => 'Select a tag to see its details';

  @override
  String get accountDetails => 'Account details';

  @override
  String get categoryDetails => 'Category details';

  @override
  String get tagDetails => 'Tag details';

  @override
  String get today => 'Today';

  @override
  String get yesterday => 'Yesterday';

  @override
  String estimated(String date) {
    return '$date (estimated)';
  }

  @override
  String get transferSent => 'Transfer sent';

  @override
  String get transferReceived => 'Transfer received';

  @override
  String get income => 'Income';

  @override
  String get incomes => 'Income';

  @override
  String get expense => 'Expense';

  @override
  String get expenses => 'Expenses';

  @override
  String get transfer => 'Transfer';

  @override
  String get transfers => 'Transfers';

  @override
  String get balanceAdjustment => 'Balance adjustment';

  @override
  String get balanceAdjustments => 'Adjustments';

  @override
  String get initialBalance => 'Initial balance';

  @override
  String get pending => 'Pending';

  @override
  String get cleared => 'Cleared';

  @override
  String get thisWeek => 'This week';

  @override
  String get thisMonth => 'This month';

  @override
  String get lastMonth => 'Last month';

  @override
  String get thisYear => 'This year';

  @override
  String get source => 'Source';

  @override
  String get destination => 'Destination';

  @override
  String get either => 'Either';

  @override
  String get matchAny => 'Any';

  @override
  String get matchAll => 'All';

  @override
  String get newAccount => 'New account';

  @override
  String get newCategory => 'New category';

  @override
  String get newTag => 'New tag';

  @override
  String get noAccountsTitle => 'You don\'t have any accounts yet';

  @override
  String get noAccountsBody =>
      'Create your first account to start tracking your expenses.';

  @override
  String get createAccount => 'Create account';

  @override
  String get accountsLoadFailed => 'Could not load accounts';

  @override
  String get nameCannotBeEmpty => 'The name cannot be empty';

  @override
  String get accountSaveFailed => 'Could not save the account';

  @override
  String get adjustBalance => 'Adjust balance';

  @override
  String get adjustBalanceFailed => 'Could not adjust the balance';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String deleteAccountConfirmation(String name) {
    return 'Are you sure you want to delete “$name”? It will no longer appear in your accounts.';
  }

  @override
  String get deleteAccountFailed => 'Could not delete the account';

  @override
  String get balance => 'Balance';

  @override
  String get lastTransactions => 'Latest transactions';

  @override
  String get transactionsCouldNotLoad => 'Could not load the transactions';

  @override
  String get initialBalanceOptional => 'Initial balance (optional)';

  @override
  String get enterValidAmount => 'Enter a valid amount';

  @override
  String get accountCreateFailed => 'Could not create the account';

  @override
  String get accountDuplicateNameCurrency =>
      'An account with that name and currency already exists';

  @override
  String get suggestions => 'Suggestions';

  @override
  String get accountNameExample => 'E.g. Cash, Main bank…';

  @override
  String get categoryNameExample => 'E.g. Groceries, Transport…';

  @override
  String get chooseCurrency => 'Choose a currency';

  @override
  String get searchCurrency => 'Search currencies…';

  @override
  String get mostUsed => 'Most used';

  @override
  String get cash => 'Cash';

  @override
  String get bank => 'Bank';

  @override
  String get card => 'Card';

  @override
  String get groceries => 'Groceries';

  @override
  String get transport => 'Transport';

  @override
  String get services => 'Services';

  @override
  String get createCategory => 'Create category';

  @override
  String get categoryCreateFailed => 'Could not create the category';

  @override
  String get categoriesLoadFailed => 'Could not load categories';

  @override
  String get noCategoriesTitle => 'You don\'t have any categories yet';

  @override
  String get noCategoriesBody =>
      'Create a category to organize your transactions.';

  @override
  String get deleteCategory => 'Delete category';

  @override
  String deleteCategoryConfirmation(String name) {
    return 'Are you sure you want to delete “$name”? It will no longer appear in your categories.';
  }

  @override
  String get deleteCategoryFailed => 'Could not delete the category';

  @override
  String get categorySaveFailed => 'Could not save the category';

  @override
  String get latestMovements => 'Latest movements';

  @override
  String get movementsLoadFailed => 'Could not load movements';

  @override
  String get noMovementsYet => 'No movements yet';

  @override
  String movementCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count movements',
      one: '1 movement',
      zero: 'No movements',
    );
    return '$_temp0';
  }

  @override
  String get tagsLoadFailed => 'Could not load tags.';

  @override
  String get noTagsYet => 'No tags yet.';

  @override
  String get deleteTag => 'Delete tag';

  @override
  String deleteTagConfirmation(String name) {
    return 'Are you sure you want to delete “$name”? It will no longer appear in your tags.';
  }

  @override
  String get deleteTagWithChildren => 'Delete tag with subtags';

  @override
  String deleteTagWithChildrenPrompt(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count subtags',
      one: '1 subtag',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'them',
      one: 'it',
    );
    return '“$name” has $_temp0. What should happen to $_temp1?';
  }

  @override
  String get keepSubtags => 'Keep subtags';

  @override
  String get deleteEverything => 'Delete everything';

  @override
  String get spentThisMonth => 'SPENT THIS MONTH';

  @override
  String get noSpendingThisMonth => 'No spending this month';

  @override
  String otherCurrencies(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count other currencies',
      one: '1 other currency',
    );
    return '+ $_temp0';
  }

  @override
  String get createSubtag => 'Create subtag';

  @override
  String get parentTag => 'Parent tag';

  @override
  String get chooseParentTag => 'Choose the parent tag';

  @override
  String get noParentTag => 'No parent tag';

  @override
  String insideTag(String name) {
    return 'Inside $name';
  }

  @override
  String get searchHint => 'Search by name or description…';

  @override
  String get filters => 'Filters';

  @override
  String get simple => 'Simple';

  @override
  String get advanced => 'Advanced';

  @override
  String get customRange => 'Custom range';

  @override
  String get noAccountsYet => 'No accounts yet.';

  @override
  String get transferDirection => 'Direction (for transfers)';

  @override
  String get noCategoriesYet => 'No categories yet.';

  @override
  String get noCurrenciesYet => 'No currencies yet.';

  @override
  String get selectCurrencyForAmount =>
      'Select a currency to filter by amount.';

  @override
  String get subtags => 'Subtags';

  @override
  String get showLess => 'Show less';

  @override
  String showMore(int count) {
    return 'Show $count more';
  }

  @override
  String get advancedFilterNotice => 'This filter uses advanced rules.';

  @override
  String get advancedFilterWarning =>
      'The simple view cannot edit OR, NOT, or nested groups without changing the filter\'s meaning.';

  @override
  String get editAdvanced => 'Edit advanced';

  @override
  String get createSimpleFilter => 'Create simple filter';

  @override
  String get deleteGroup => 'Delete group';

  @override
  String get addConditionToStart => 'Add a condition to get started.';

  @override
  String get condition => 'Condition';

  @override
  String get group => 'Group';

  @override
  String get field => 'Field';

  @override
  String get operator => 'Operator';

  @override
  String get operatorIncludes => 'includes';

  @override
  String get operatorExcludes => 'excludes';

  @override
  String get operatorRelative => 'relative';

  @override
  String get operatorBetween => 'between';

  @override
  String get operatorGreaterEqual => 'greater than or equal to';

  @override
  String get operatorLessEqual => 'less than or equal to';

  @override
  String get operatorContains => 'contains';

  @override
  String get operatorNotContains => 'does not contain';

  @override
  String get filterAnd => 'AND';

  @override
  String get filterOr => 'OR';

  @override
  String get filterNot => 'NOT';

  @override
  String get deleteCondition => 'Delete condition';

  @override
  String get direction => 'Direction';

  @override
  String get match => 'Match';

  @override
  String get includeSubtags => 'Include subtags';

  @override
  String get unsupportedField => 'Unsupported field.';

  @override
  String get chooseRange => 'Choose range';

  @override
  String filterOptionsLoadFailed(Object error) {
    return 'Could not load filter options.\n$error';
  }

  @override
  String get newTransaction => 'Add transaction';

  @override
  String get noTagsAvailable => 'No tags available';

  @override
  String tagCreateFailed(Object error) {
    return 'Could not create the tag: $error';
  }

  @override
  String colorFor(String name) {
    return 'Color for “$name”';
  }

  @override
  String get selectAccount => 'Select an account';

  @override
  String get selectCategory => 'Select a category';

  @override
  String get selectDestinationAccount => 'Select a destination account';

  @override
  String get differentTransferAccounts =>
      'Source and destination must be different accounts';

  @override
  String recordFailed(Object error) {
    return 'Could not save the transaction: $error';
  }

  @override
  String get title => 'Title';

  @override
  String get titleRequired => 'A title is required';

  @override
  String get addTag => 'Add tag';

  @override
  String get record => 'Save transaction';

  @override
  String get recurringExpense => 'Recurring expense';

  @override
  String get leaves => 'Leaves';

  @override
  String get enters => 'Enters';

  @override
  String get required => 'Required';

  @override
  String get greaterThanZero => 'Greater than 0';

  @override
  String get amountRequired => 'Amount is required';

  @override
  String get amountGreaterThanZero => 'Amount must be greater than 0';

  @override
  String get loginIntro => 'Get started with sync or a local account.';

  @override
  String get withAccount => 'With account';

  @override
  String get withoutAccount => 'Local account';

  @override
  String get withAccountDescription =>
      'Use email or Google to sync your expenses.';

  @override
  String get localAccountDescription =>
      'Add a name before opening this space on your device.';

  @override
  String get email => 'Email';

  @override
  String get password => 'Password';

  @override
  String get enterYourName => 'Enter your name';

  @override
  String get enterEmail => 'Enter your email';

  @override
  String get enterValidEmail => 'Enter a valid email';

  @override
  String get enterPassword => 'Enter your password';

  @override
  String get passwordMinLength => 'Use at least 8 characters';

  @override
  String get or => 'or';

  @override
  String get continueWithGoogle => 'Continue with Google';

  @override
  String get continueWithApple => 'Continue with Apple';

  @override
  String get continueLocally => 'Continue locally';

  @override
  String get needAccountSignUp => 'Need an account? Sign up';

  @override
  String get haveAccountSignIn => 'Already have an account? Sign in';

  @override
  String get signIn => 'Sign in';

  @override
  String get signUp => 'Sign up';

  @override
  String get signInAction => 'sign in';

  @override
  String get signUpAction => 'create the account';

  @override
  String get accountAlreadyAdded =>
      'You already added an account with that email';

  @override
  String get accountExistsSignIn =>
      'An account with that email already exists. Sign in with your password or with Google.';

  @override
  String get emailSignInFailedGoogleHint =>
      'Sign-in failed. If you registered with Google, use “Continue with Google”.';

  @override
  String emailAuthFailed(String action, Object error) {
    return 'Could not $action: $error';
  }

  @override
  String get forgotPassword => 'Forgot your password?';

  @override
  String get resetPasswordTitle => 'Reset your password';

  @override
  String get resetPasswordSubtitle =>
      'Enter your email and we\'ll send you a reset link.';

  @override
  String get sendResetLink => 'Send reset link';

  @override
  String resetEmailSent(String email) {
    return 'We sent a link to $email to reset your password. The link opens in your browser.';
  }

  @override
  String get resetEmailSentReturnHint =>
      'After resetting it, come back here and sign in with your new password.';

  @override
  String resetRequestFailed(Object error) {
    return 'Could not send the reset email: $error';
  }

  @override
  String get backToSignIn => 'Back to sign in';

  @override
  String get verifyEmailTitle => 'Verify your email';

  @override
  String verifyEmailSent(String email) {
    return 'We sent a verification link to $email. The link opens in your browser.';
  }

  @override
  String get verifyEmailInstructions =>
      'Open the link to verify your account, then come back here and sign in.';

  @override
  String get verifyEmailDone => 'I verified my email';

  @override
  String get resendVerificationEmail => 'Resend email';

  @override
  String resendVerificationCooldown(int seconds) {
    return 'Resend in ${seconds}s';
  }

  @override
  String get verificationEmailResent => 'Verification email sent again.';

  @override
  String resendVerificationFailed(Object error) {
    return 'Could not resend the email: $error';
  }

  @override
  String get emailStillNotVerified =>
      'That email isn\'t verified yet. We sent you a new link.';

  @override
  String accountNotFoundForEmail(String email) {
    return 'There is no account for $email.';
  }

  @override
  String get emailAlreadyVerified =>
      'That email is already verified. Sign in with your account.';

  @override
  String get tooManyAttempts =>
      'Too many attempts. Wait a minute and try again.';

  @override
  String get emailSendFailed =>
      'Could not send the email. Try again in a few minutes.';

  @override
  String localAccountFailed(Object error) {
    return 'Could not continue locally: $error';
  }

  @override
  String googleSignInFailed(Object error) {
    return 'Could not sign in with Google: $error';
  }

  @override
  String appleSignInFailed(Object error) {
    return 'Could not sign in with Apple: $error';
  }

  @override
  String get close => 'Close';

  @override
  String get newCategoryTooltip => 'New category';

  @override
  String get newTagTooltip => 'New tag';

  @override
  String get addScreen => 'Add screen';

  @override
  String get dashboardEmpty =>
      'Your dashboard is empty. Add a widget to get started.';

  @override
  String get dashboardLoadFailed => 'Could not load the dashboard.';

  @override
  String get removeWidget => 'Remove widget';

  @override
  String removeWidgetConfirmation(String title) {
    return 'Remove “$title” from the dashboard?';
  }

  @override
  String dashboardUpdateFailed(Object error) {
    return 'Could not update the dashboard: $error';
  }

  @override
  String widgetRemoveFailed(Object error) {
    return 'Could not remove the widget: $error';
  }

  @override
  String get valueWidget => 'Value';

  @override
  String get listWidget => 'List';

  @override
  String get balanceWidget => 'Balance';

  @override
  String get chartWidget => 'Chart';

  @override
  String get widget => 'Widget';

  @override
  String get moveLeft => 'Move left';

  @override
  String get moveUp => 'Move up';

  @override
  String get moveDown => 'Move down';

  @override
  String get moveRight => 'Move right';

  @override
  String get chartLoadFailed => 'Could not load the chart.';

  @override
  String get chartNoData => 'No data to show yet.';

  @override
  String get uncategorized => 'Uncategorized';

  @override
  String get unknownAccount => 'Unknown account';

  @override
  String get enterWidgetTitle => 'Enter a title';

  @override
  String get selectWidgetCurrency => 'Select a currency';

  @override
  String get configureWidgetFilter => 'Configure a filter for this widget';

  @override
  String widgetSaveFailed(Object error) {
    return 'Could not save the widget: $error';
  }

  @override
  String get widgetType => 'Type';

  @override
  String get widgetTitle => 'Title';

  @override
  String get background => 'Background';

  @override
  String get low => 'Low';

  @override
  String get high => 'High';

  @override
  String get belowLow => 'Below low';

  @override
  String get betweenLowHigh => 'Between low and high';

  @override
  String get aboveHigh => 'Above high';

  @override
  String get aggregation => 'Aggregation';

  @override
  String get transactionCount => 'Number of transactions';

  @override
  String get groupBy => 'Group by';

  @override
  String get chartType => 'Chart type';

  @override
  String get noAccountsUseArs => 'There are no accounts yet; ARS will be used.';

  @override
  String get widgetWidth => 'Width';

  @override
  String get widgetAccountsAllHint => 'Every account in this currency.';

  @override
  String get widgetAccountsScopedHint => 'Only the selected accounts.';

  @override
  String get noColor => 'No color';

  @override
  String get editFilter => 'Edit filter';

  @override
  String get removeFilter => 'Remove filter';

  @override
  String get configureFilter => 'Configure filter';

  @override
  String get addWidgetAction => 'Add';

  @override
  String get saveWidgetAction => 'Save';

  @override
  String get widgetTypeStat => 'Value';

  @override
  String get widgetTypeList => 'Transactions';

  @override
  String get widgetTypeBalance => 'Balance';

  @override
  String get widgetTypeChart => 'Chart';

  @override
  String get aggregationSum => 'Sum';

  @override
  String get aggregationNet => 'Net';

  @override
  String get aggregationCount => 'Count';

  @override
  String get groupCategory => 'Category';

  @override
  String get groupAccount => 'Account';

  @override
  String get groupMonth => 'Month';

  @override
  String get chartPie => 'Pie';

  @override
  String get chartBar => 'Bar';

  @override
  String get chartLine => 'Line';

  @override
  String get defaultExpensesMonth => 'Monthly expenses';

  @override
  String get defaultIncomeMonth => 'Monthly income';

  @override
  String get defaultMovementsMonth => 'Monthly transactions';

  @override
  String get defaultTotalBalanceArs => 'Total balance (ARS)';

  @override
  String get defaultMovements => 'Transactions';

  @override
  String get defaultRecentMovements => 'Recent transactions';

  @override
  String get liveVoice => 'Talk to Gaston';

  @override
  String get endSession => 'End session';

  @override
  String get you => 'You';

  @override
  String get agentInterrupted => 'Agent interrupted';

  @override
  String get interrupted => '(interrupted)';

  @override
  String get toolRunning => 'Running';

  @override
  String get toolDone => 'Done';

  @override
  String get toolCancelled => 'Cancelled';

  @override
  String get tool => 'Tool';

  @override
  String get arguments => 'arguments';

  @override
  String get result => 'result';

  @override
  String get connected => 'connected';

  @override
  String get connecting => 'connecting';

  @override
  String get idle => 'idle';

  @override
  String get connectionLostReconnecting =>
      'Connection lost. Reconnecting automatically…';

  @override
  String get connectingPrompt => 'Connecting…';

  @override
  String get voiceStartPrompt => 'Tap the mic to start a conversation';

  @override
  String get typeMessage => 'Type a message…';

  @override
  String get microphonePermissionDenied => 'Microphone permission denied';

  @override
  String get recorderPermissionFailed =>
      'Could not check microphone permission';

  @override
  String get pcmUnsupported =>
      'PCM 16-bit streaming is not supported on this device';

  @override
  String get voiceStartFailed =>
      'Couldn\'t start the conversation. Please try again.';

  @override
  String get voiceUnavailable =>
      'Gastón isn\'t available right now. Please try again in a few minutes.';

  @override
  String get voiceRequiresAccount =>
      'Gastón needs an account. Sign in to start a conversation.';

  @override
  String microphoneOpenFailed(Object error) {
    return 'Failed to open the microphone: $error';
  }

  @override
  String audioStreamFailed(Object error) {
    return 'Audio stream error: $error';
  }

  @override
  String toolResponseUnmatched(Object result) {
    return 'Tool response with no matching call: $result';
  }

  @override
  String toolCallsCancelled(String ids) {
    return 'Tool calls cancelled: $ids';
  }

  @override
  String get deletedAccount => 'Deleted account';

  @override
  String transactionSaved(String type, String updated, String date) {
    String _temp0 = intl.Intl.selectLogic(updated, {
      'true': 'updated',
      'other': 'recorded',
    });
    return '$type $_temp0 · $date';
  }

  @override
  String editTransactionType(String type) {
    return 'Edit $type';
  }

  @override
  String get chooseCategory => 'Choose a category';

  @override
  String get transactionSaveFailed => 'Could not save the transaction';

  @override
  String get accountCreated => 'Account created';

  @override
  String get accountUpdated => 'Account updated';

  @override
  String get categoryCreated => 'Category created';

  @override
  String get categoryUpdated => 'Category updated';

  @override
  String get tagCreated => 'Tag created';

  @override
  String get tagUpdated => 'Tag updated';

  @override
  String get editAccount => 'Edit account';

  @override
  String get editCategory => 'Edit category';

  @override
  String get editTag => 'Edit tag';

  @override
  String get tagSaveFailed => 'Could not save the tag';

  @override
  String get legalFirstTitle => 'Before you start';

  @override
  String get legalFirstSubtitle =>
      'We need your acceptance to create your account and provide the service.';

  @override
  String get legalUpdatedTermsTitle => 'We updated the Terms';

  @override
  String get legalUpdatedPrivacyTitle => 'We updated the Privacy Policy';

  @override
  String get legalUpdatedBothTitle =>
      'We updated the Terms and the Privacy Policy';

  @override
  String get legalUpdatedSubtitle =>
      'Review the changes and accept them to keep using Wallet Bot.';

  @override
  String get legalUpdatedSubtitleGrace =>
      'You can keep using the app for now, but we will need your acceptance.';

  @override
  String get legalAgeConfirm => 'I am 18 or older';

  @override
  String get legalAcceptTerms => 'I accept the [[terms]]';

  @override
  String get legalAcceptPrivacy => 'I accept the [[privacy]]';

  @override
  String get legalAcceptBoth => 'I accept the [[terms]] and the [[privacy]]';

  @override
  String get legalTermsName => 'Terms and Conditions';

  @override
  String get legalPrivacyName => 'Privacy Policy';

  @override
  String get legalAcceptAction => 'Accept and continue';

  @override
  String get legalLater => 'Later';

  @override
  String get legalUseAnotherAccount => 'Use another account';

  @override
  String get legalAcceptFailed =>
      'We could not record your acceptance. Check your connection and try again.';

  @override
  String get actionLoadFailed => 'Could not load the action';

  @override
  String get tapToRetry => 'Tap to try again';

  @override
  String get reportResponseAction => 'Report this response';

  @override
  String get reportResponseCopy => 'Copy';

  @override
  String get reportResponseCopied => 'Response copied';

  @override
  String get reportResponseMenuItem => 'Report a response';

  @override
  String get reportResponseBadge => 'Reported';

  @override
  String get reportResponseTitle => 'Report a response';

  @override
  String get reportResponseSubtitle =>
      'Tell us what was wrong with what Gaston said. We review reports to fix the assistant.';

  @override
  String get reportResponseSessionSubtitle =>
      'Report this conversation when the response was voice-only or has already scrolled away.';

  @override
  String get reportResponseReasonLabel => 'Reason';

  @override
  String get reportReasonOffensive => 'Offensive, abusive or violent';

  @override
  String get reportReasonSexual => 'Sexual content';

  @override
  String get reportReasonDangerous => 'Dangerous or illegal';

  @override
  String get reportReasonMisleading => 'False financial information';

  @override
  String get reportReasonPrivacy => 'Showed data it should not have';

  @override
  String get reportReasonOther => 'Something else';

  @override
  String get reportResponseReasonRequired => 'Pick a reason before sending';

  @override
  String get reportResponseNoteLabel => 'Details (optional)';

  @override
  String get reportResponseNoteHint => 'What happened?';

  @override
  String get reportResponseReportedTextLabel => 'Reported response';

  @override
  String get reportResponseSessionNotice =>
      'This sends the conversation from this session, without the audio.';

  @override
  String get reportResponsePrivacyNotice =>
      'We send the text above along with the model and your app version. Audio never leaves your device.';

  @override
  String get reportResponseSend => 'Send report';

  @override
  String get reportResponseSending => 'Sending report…';

  @override
  String get reportResponseSent => 'Thank you. We will review this response';

  @override
  String get reportResponseFailed => 'Could not send your report';

  @override
  String get reportResponseRateLimited =>
      'You have sent several reports already. Try again later.';

  @override
  String get reportResponseOffline =>
      'No connection. Check your internet and try again.';

  @override
  String get reportResponseInvalid =>
      'We could not process this report. Try again.';

  @override
  String get reportResponseNoResponseYet =>
      'There is no response to report yet';
}
