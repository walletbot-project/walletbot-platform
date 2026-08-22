import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Wallet Bot'**
  String get appTitle;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @activity.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// No description provided for @accounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accounts;

  /// No description provided for @insights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get insights;

  /// No description provided for @categories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// No description provided for @tags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get tags;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @reconnect.
  ///
  /// In en, this message translates to:
  /// **'Reconnect'**
  String get reconnect;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @any.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get any;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get viewAll;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @nameRequiredLabel.
  ///
  /// In en, this message translates to:
  /// **'Name *'**
  String get nameRequiredLabel;

  /// No description provided for @enterName.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get enterName;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @descriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptional;

  /// No description provided for @noDescription.
  ///
  /// In en, this message translates to:
  /// **'No description'**
  String get noDescription;

  /// No description provided for @color.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get color;

  /// No description provided for @icon.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get icon;

  /// No description provided for @iconAndColor.
  ///
  /// In en, this message translates to:
  /// **'Icon and color'**
  String get iconAndColor;

  /// No description provided for @chooseColor.
  ///
  /// In en, this message translates to:
  /// **'Choose a color'**
  String get chooseColor;

  /// No description provided for @chooseIcon.
  ///
  /// In en, this message translates to:
  /// **'Choose an icon'**
  String get chooseIcon;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currency;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @text.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get text;

  /// No description provided for @minimum.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get minimum;

  /// No description provided for @maximum.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get maximum;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @optional.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// No description provided for @timeOptional.
  ///
  /// In en, this message translates to:
  /// **'Time (optional)'**
  String get timeOptional;

  /// No description provided for @noTime.
  ///
  /// In en, this message translates to:
  /// **'No time'**
  String get noTime;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @loadingFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load'**
  String get loadingFailed;

  /// No description provided for @voiceCommands.
  ///
  /// In en, this message translates to:
  /// **'Voice commands'**
  String get voiceCommands;

  /// No description provided for @syncPaused.
  ///
  /// In en, this message translates to:
  /// **'Sync paused — sign in again to reconnect'**
  String get syncPaused;

  /// No description provided for @reconnectFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not reconnect: {error}'**
  String reconnectFailed(Object error);

  /// No description provided for @sync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get sync;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncing;

  /// No description provided for @synced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get synced;

  /// No description provided for @syncError.
  ///
  /// In en, this message translates to:
  /// **'Sync error'**
  String get syncError;

  /// No description provided for @tapToSync.
  ///
  /// In en, this message translates to:
  /// **'Tap to sync'**
  String get tapToSync;

  /// No description provided for @syncInProgress.
  ///
  /// In en, this message translates to:
  /// **'Sync in progress'**
  String get syncInProgress;

  /// No description provided for @syncedTapAgain.
  ///
  /// In en, this message translates to:
  /// **'Synced. Tap to sync again.'**
  String get syncedTapAgain;

  /// No description provided for @lastSynced.
  ///
  /// In en, this message translates to:
  /// **'Last synced {time} ago. Tap to sync again.'**
  String lastSynced(String time);

  /// No description provided for @syncErrorRetry.
  ///
  /// In en, this message translates to:
  /// **'Sync error. Tap to retry.'**
  String get syncErrorRetry;

  /// No description provided for @syncErrorDetails.
  ///
  /// In en, this message translates to:
  /// **'Sync error: {error}. Tap to retry.'**
  String syncErrorDetails(Object error);

  /// No description provided for @durationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{count}s'**
  String durationSeconds(int count);

  /// No description provided for @durationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count}m'**
  String durationMinutes(int count);

  /// No description provided for @durationHours.
  ///
  /// In en, this message translates to:
  /// **'{count}h'**
  String durationHours(int count);

  /// No description provided for @durationDays.
  ///
  /// In en, this message translates to:
  /// **'{count}d'**
  String durationDays(int count);

  /// No description provided for @yourAccounts.
  ///
  /// In en, this message translates to:
  /// **'Your accounts'**
  String get yourAccounts;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose the language used throughout the app.'**
  String get languageDescription;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefault;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @spanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get spanish;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose how the app looks on this device.'**
  String get themeDescription;

  /// No description provided for @lightTheme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightTheme;

  /// No description provided for @darkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get darkTheme;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the setting. Try again.'**
  String get settingsSaveFailed;

  /// No description provided for @deleteUserAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete my account'**
  String get deleteUserAccount;

  /// No description provided for @deleteUserAccountDescription.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your account and all your data'**
  String get deleteUserAccountDescription;

  /// No description provided for @deleteUserAccountConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get deleteUserAccountConfirmTitle;

  /// No description provided for @deleteUserAccountConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'We will send a confirmation link to {email}. Deleting your account is permanent and cannot be undone.'**
  String deleteUserAccountConfirmBody(String email);

  /// No description provided for @deleteUserAccountSend.
  ///
  /// In en, this message translates to:
  /// **'Send link'**
  String get deleteUserAccountSend;

  /// No description provided for @deleteUserAccountEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Check your email: we sent you a link to confirm the deletion.'**
  String get deleteUserAccountEmailSent;

  /// No description provided for @deleteUserAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send the email. Try again in a few minutes.'**
  String get deleteUserAccountFailed;

  /// No description provided for @deleteUserAccountAlreadyDeleted.
  ///
  /// In en, this message translates to:
  /// **'That account was already deleted.'**
  String get deleteUserAccountAlreadyDeleted;

  /// No description provided for @deleteUserAccountRateLimited.
  ///
  /// In en, this message translates to:
  /// **'You already requested several deletion links. Wait an hour and try again.'**
  String get deleteUserAccountRateLimited;

  /// No description provided for @accountDeletedBanner.
  ///
  /// In en, this message translates to:
  /// **'This account was deleted'**
  String get accountDeletedBanner;

  /// No description provided for @accountDeletedRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get accountDeletedRemove;

  /// No description provided for @accountDeletedConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this account from the device?'**
  String get accountDeletedConfirmTitle;

  /// No description provided for @accountDeletedConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The account is already deleted on the server. This erases its data from this device too, which is the last copy.'**
  String get accountDeletedConfirmBody;

  /// No description provided for @accountDeletedRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get accountDeletedRemoveConfirm;

  /// No description provided for @updateRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Update required'**
  String get updateRequiredTitle;

  /// No description provided for @updateRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Update the app to continue syncing your data.'**
  String get updateRequiredMessage;

  /// No description provided for @updateAvailableTitle.
  ///
  /// In en, this message translates to:
  /// **'New version available'**
  String get updateAvailableTitle;

  /// No description provided for @updateAvailableMessage.
  ///
  /// In en, this message translates to:
  /// **'Update when you can to receive **the latest improvements**.'**
  String get updateAvailableMessage;

  /// No description provided for @updateApp.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateApp;

  /// No description provided for @openLinkFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the link'**
  String get openLinkFailed;

  /// No description provided for @noName.
  ///
  /// In en, this message translates to:
  /// **'No name'**
  String get noName;

  /// No description provided for @localAccount.
  ///
  /// In en, this message translates to:
  /// **'Local account'**
  String get localAccount;

  /// No description provided for @syncedAccount.
  ///
  /// In en, this message translates to:
  /// **'Synced account'**
  String get syncedAccount;

  /// No description provided for @removeAccount.
  ///
  /// In en, this message translates to:
  /// **'Remove account'**
  String get removeAccount;

  /// No description provided for @addAccount.
  ///
  /// In en, this message translates to:
  /// **'Add account'**
  String get addAccount;

  /// No description provided for @thisAccount.
  ///
  /// In en, this message translates to:
  /// **'this account'**
  String get thisAccount;

  /// No description provided for @removeAccountConfirmation.
  ///
  /// In en, this message translates to:
  /// **'The data for “{name}” will be removed from this device. This action cannot be undone.'**
  String removeAccountConfirmation(String name);

  /// No description provided for @removeAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove the account: {error}'**
  String removeAccountFailed(Object error);

  /// No description provided for @addWidget.
  ///
  /// In en, this message translates to:
  /// **'Add widget'**
  String get addWidget;

  /// No description provided for @editWidget.
  ///
  /// In en, this message translates to:
  /// **'Edit widget'**
  String get editWidget;

  /// No description provided for @editDashboard.
  ///
  /// In en, this message translates to:
  /// **'Edit dashboard'**
  String get editDashboard;

  /// No description provided for @actions.
  ///
  /// In en, this message translates to:
  /// **'Actions'**
  String get actions;

  /// No description provided for @addManually.
  ///
  /// In en, this message translates to:
  /// **'Add manually'**
  String get addManually;

  /// No description provided for @addTransaction.
  ///
  /// In en, this message translates to:
  /// **'Add transaction'**
  String get addTransaction;

  /// No description provided for @transactionsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load transactions: {error}'**
  String transactionsLoadFailed(Object error);

  /// No description provided for @noTransactions.
  ///
  /// In en, this message translates to:
  /// **'No transactions'**
  String get noTransactions;

  /// No description provided for @noTransactionsYet.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get noTransactionsYet;

  /// No description provided for @selectTransactionDetail.
  ///
  /// In en, this message translates to:
  /// **'Select a transaction to see its details'**
  String get selectTransactionDetail;

  /// No description provided for @selectAccountDetail.
  ///
  /// In en, this message translates to:
  /// **'Select an account to see its details'**
  String get selectAccountDetail;

  /// No description provided for @selectCategoryDetail.
  ///
  /// In en, this message translates to:
  /// **'Select a category to see its details'**
  String get selectCategoryDetail;

  /// No description provided for @selectTagDetail.
  ///
  /// In en, this message translates to:
  /// **'Select a tag to see its details'**
  String get selectTagDetail;

  /// No description provided for @accountDetails.
  ///
  /// In en, this message translates to:
  /// **'Account details'**
  String get accountDetails;

  /// No description provided for @categoryDetails.
  ///
  /// In en, this message translates to:
  /// **'Category details'**
  String get categoryDetails;

  /// No description provided for @tagDetails.
  ///
  /// In en, this message translates to:
  /// **'Tag details'**
  String get tagDetails;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get yesterday;

  /// No description provided for @estimated.
  ///
  /// In en, this message translates to:
  /// **'{date} (estimated)'**
  String estimated(String date);

  /// No description provided for @transferSent.
  ///
  /// In en, this message translates to:
  /// **'Transfer sent'**
  String get transferSent;

  /// No description provided for @transferReceived.
  ///
  /// In en, this message translates to:
  /// **'Transfer received'**
  String get transferReceived;

  /// No description provided for @income.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get income;

  /// No description provided for @incomes.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get incomes;

  /// No description provided for @expense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get expense;

  /// No description provided for @expenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenses;

  /// No description provided for @transfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get transfer;

  /// No description provided for @transfers.
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get transfers;

  /// Transaction type label. Also the display name of an auto-generated balance-adjustment transaction (stored canonically as 'Ajuste de saldo').
  ///
  /// In en, this message translates to:
  /// **'Balance adjustment'**
  String get balanceAdjustment;

  /// No description provided for @balanceAdjustments.
  ///
  /// In en, this message translates to:
  /// **'Adjustments'**
  String get balanceAdjustments;

  /// Display name of the balance-adjustment transaction seeded when an account is created with a starting balance (stored canonically as 'Balance inicial').
  ///
  /// In en, this message translates to:
  /// **'Initial balance'**
  String get initialBalance;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @cleared.
  ///
  /// In en, this message translates to:
  /// **'Cleared'**
  String get cleared;

  /// No description provided for @thisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get thisWeek;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get thisMonth;

  /// No description provided for @lastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get lastMonth;

  /// No description provided for @thisYear.
  ///
  /// In en, this message translates to:
  /// **'This year'**
  String get thisYear;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get source;

  /// No description provided for @destination.
  ///
  /// In en, this message translates to:
  /// **'Destination'**
  String get destination;

  /// No description provided for @either.
  ///
  /// In en, this message translates to:
  /// **'Either'**
  String get either;

  /// No description provided for @matchAny.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get matchAny;

  /// No description provided for @matchAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get matchAll;

  /// No description provided for @newAccount.
  ///
  /// In en, this message translates to:
  /// **'New account'**
  String get newAccount;

  /// No description provided for @newCategory.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get newCategory;

  /// No description provided for @newTag.
  ///
  /// In en, this message translates to:
  /// **'New tag'**
  String get newTag;

  /// No description provided for @noAccountsTitle.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have any accounts yet'**
  String get noAccountsTitle;

  /// No description provided for @noAccountsBody.
  ///
  /// In en, this message translates to:
  /// **'Create your first account to start tracking your expenses.'**
  String get noAccountsBody;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @accountsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load accounts'**
  String get accountsLoadFailed;

  /// No description provided for @nameCannotBeEmpty.
  ///
  /// In en, this message translates to:
  /// **'The name cannot be empty'**
  String get nameCannotBeEmpty;

  /// No description provided for @accountSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the account'**
  String get accountSaveFailed;

  /// No description provided for @adjustBalance.
  ///
  /// In en, this message translates to:
  /// **'Adjust balance'**
  String get adjustBalance;

  /// No description provided for @adjustBalanceFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not adjust the balance'**
  String get adjustBalanceFailed;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete “{name}”? It will no longer appear in your accounts.'**
  String deleteAccountConfirmation(String name);

  /// No description provided for @deleteAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the account'**
  String get deleteAccountFailed;

  /// No description provided for @balance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balance;

  /// No description provided for @lastTransactions.
  ///
  /// In en, this message translates to:
  /// **'Latest transactions'**
  String get lastTransactions;

  /// No description provided for @transactionsCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Could not load the transactions'**
  String get transactionsCouldNotLoad;

  /// No description provided for @initialBalanceOptional.
  ///
  /// In en, this message translates to:
  /// **'Initial balance (optional)'**
  String get initialBalanceOptional;

  /// No description provided for @enterValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get enterValidAmount;

  /// No description provided for @accountCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create the account'**
  String get accountCreateFailed;

  /// No description provided for @accountDuplicateNameCurrency.
  ///
  /// In en, this message translates to:
  /// **'An account with that name and currency already exists'**
  String get accountDuplicateNameCurrency;

  /// No description provided for @suggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get suggestions;

  /// No description provided for @accountNameExample.
  ///
  /// In en, this message translates to:
  /// **'E.g. Cash, Main bank…'**
  String get accountNameExample;

  /// No description provided for @categoryNameExample.
  ///
  /// In en, this message translates to:
  /// **'E.g. Groceries, Transport…'**
  String get categoryNameExample;

  /// No description provided for @chooseCurrency.
  ///
  /// In en, this message translates to:
  /// **'Choose a currency'**
  String get chooseCurrency;

  /// No description provided for @searchCurrency.
  ///
  /// In en, this message translates to:
  /// **'Search currencies…'**
  String get searchCurrency;

  /// No description provided for @mostUsed.
  ///
  /// In en, this message translates to:
  /// **'Most used'**
  String get mostUsed;

  /// No description provided for @cash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get cash;

  /// No description provided for @bank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get bank;

  /// No description provided for @card.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get card;

  /// No description provided for @groceries.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get groceries;

  /// No description provided for @transport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get transport;

  /// No description provided for @services.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get services;

  /// No description provided for @createCategory.
  ///
  /// In en, this message translates to:
  /// **'Create category'**
  String get createCategory;

  /// No description provided for @categoryCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create the category'**
  String get categoryCreateFailed;

  /// No description provided for @categoriesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load categories'**
  String get categoriesLoadFailed;

  /// No description provided for @noCategoriesTitle.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have any categories yet'**
  String get noCategoriesTitle;

  /// No description provided for @noCategoriesBody.
  ///
  /// In en, this message translates to:
  /// **'Create a category to organize your transactions.'**
  String get noCategoriesBody;

  /// No description provided for @deleteCategory.
  ///
  /// In en, this message translates to:
  /// **'Delete category'**
  String get deleteCategory;

  /// No description provided for @deleteCategoryConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete “{name}”? It will no longer appear in your categories.'**
  String deleteCategoryConfirmation(String name);

  /// No description provided for @deleteCategoryFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the category'**
  String get deleteCategoryFailed;

  /// No description provided for @categorySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the category'**
  String get categorySaveFailed;

  /// No description provided for @latestMovements.
  ///
  /// In en, this message translates to:
  /// **'Latest movements'**
  String get latestMovements;

  /// No description provided for @movementsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load movements'**
  String get movementsLoadFailed;

  /// No description provided for @noMovementsYet.
  ///
  /// In en, this message translates to:
  /// **'No movements yet'**
  String get noMovementsYet;

  /// No description provided for @movementCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No movements} =1{1 movement} other{{count} movements}}'**
  String movementCount(int count);

  /// No description provided for @tagsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load tags.'**
  String get tagsLoadFailed;

  /// No description provided for @noTagsYet.
  ///
  /// In en, this message translates to:
  /// **'No tags yet.'**
  String get noTagsYet;

  /// No description provided for @deleteTag.
  ///
  /// In en, this message translates to:
  /// **'Delete tag'**
  String get deleteTag;

  /// No description provided for @deleteTagConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete “{name}”? It will no longer appear in your tags.'**
  String deleteTagConfirmation(String name);

  /// No description provided for @deleteTagWithChildren.
  ///
  /// In en, this message translates to:
  /// **'Delete tag with subtags'**
  String get deleteTagWithChildren;

  /// No description provided for @deleteTagWithChildrenPrompt.
  ///
  /// In en, this message translates to:
  /// **'“{name}” has {count, plural, =1{1 subtag} other{{count} subtags}}. What should happen to {count, plural, =1{it} other{them}}?'**
  String deleteTagWithChildrenPrompt(String name, int count);

  /// No description provided for @keepSubtags.
  ///
  /// In en, this message translates to:
  /// **'Keep subtags'**
  String get keepSubtags;

  /// No description provided for @deleteEverything.
  ///
  /// In en, this message translates to:
  /// **'Delete everything'**
  String get deleteEverything;

  /// No description provided for @spentThisMonth.
  ///
  /// In en, this message translates to:
  /// **'SPENT THIS MONTH'**
  String get spentThisMonth;

  /// No description provided for @noSpendingThisMonth.
  ///
  /// In en, this message translates to:
  /// **'No spending this month'**
  String get noSpendingThisMonth;

  /// No description provided for @otherCurrencies.
  ///
  /// In en, this message translates to:
  /// **'+ {count, plural, =1{1 other currency} other{{count} other currencies}}'**
  String otherCurrencies(int count);

  /// No description provided for @createSubtag.
  ///
  /// In en, this message translates to:
  /// **'Create subtag'**
  String get createSubtag;

  /// No description provided for @parentTag.
  ///
  /// In en, this message translates to:
  /// **'Parent tag'**
  String get parentTag;

  /// No description provided for @chooseParentTag.
  ///
  /// In en, this message translates to:
  /// **'Choose the parent tag'**
  String get chooseParentTag;

  /// No description provided for @noParentTag.
  ///
  /// In en, this message translates to:
  /// **'No parent tag'**
  String get noParentTag;

  /// No description provided for @insideTag.
  ///
  /// In en, this message translates to:
  /// **'Inside {name}'**
  String insideTag(String name);

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or description…'**
  String get searchHint;

  /// No description provided for @filters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filters;

  /// No description provided for @simple.
  ///
  /// In en, this message translates to:
  /// **'Simple'**
  String get simple;

  /// No description provided for @advanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advanced;

  /// No description provided for @customRange.
  ///
  /// In en, this message translates to:
  /// **'Custom range'**
  String get customRange;

  /// No description provided for @noAccountsYet.
  ///
  /// In en, this message translates to:
  /// **'No accounts yet.'**
  String get noAccountsYet;

  /// No description provided for @transferDirection.
  ///
  /// In en, this message translates to:
  /// **'Direction (for transfers)'**
  String get transferDirection;

  /// No description provided for @noCategoriesYet.
  ///
  /// In en, this message translates to:
  /// **'No categories yet.'**
  String get noCategoriesYet;

  /// No description provided for @noCurrenciesYet.
  ///
  /// In en, this message translates to:
  /// **'No currencies yet.'**
  String get noCurrenciesYet;

  /// No description provided for @selectCurrencyForAmount.
  ///
  /// In en, this message translates to:
  /// **'Select a currency to filter by amount.'**
  String get selectCurrencyForAmount;

  /// No description provided for @subtags.
  ///
  /// In en, this message translates to:
  /// **'Subtags'**
  String get subtags;

  /// No description provided for @showLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get showLess;

  /// No description provided for @showMore.
  ///
  /// In en, this message translates to:
  /// **'Show {count} more'**
  String showMore(int count);

  /// No description provided for @advancedFilterNotice.
  ///
  /// In en, this message translates to:
  /// **'This filter uses advanced rules.'**
  String get advancedFilterNotice;

  /// No description provided for @advancedFilterWarning.
  ///
  /// In en, this message translates to:
  /// **'The simple view cannot edit OR, NOT, or nested groups without changing the filter\'s meaning.'**
  String get advancedFilterWarning;

  /// No description provided for @editAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Edit advanced'**
  String get editAdvanced;

  /// No description provided for @createSimpleFilter.
  ///
  /// In en, this message translates to:
  /// **'Create simple filter'**
  String get createSimpleFilter;

  /// No description provided for @deleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get deleteGroup;

  /// No description provided for @addConditionToStart.
  ///
  /// In en, this message translates to:
  /// **'Add a condition to get started.'**
  String get addConditionToStart;

  /// No description provided for @condition.
  ///
  /// In en, this message translates to:
  /// **'Condition'**
  String get condition;

  /// No description provided for @group.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get group;

  /// No description provided for @field.
  ///
  /// In en, this message translates to:
  /// **'Field'**
  String get field;

  /// No description provided for @operator.
  ///
  /// In en, this message translates to:
  /// **'Operator'**
  String get operator;

  /// No description provided for @operatorIncludes.
  ///
  /// In en, this message translates to:
  /// **'includes'**
  String get operatorIncludes;

  /// No description provided for @operatorExcludes.
  ///
  /// In en, this message translates to:
  /// **'excludes'**
  String get operatorExcludes;

  /// No description provided for @operatorRelative.
  ///
  /// In en, this message translates to:
  /// **'relative'**
  String get operatorRelative;

  /// No description provided for @operatorBetween.
  ///
  /// In en, this message translates to:
  /// **'between'**
  String get operatorBetween;

  /// No description provided for @operatorGreaterEqual.
  ///
  /// In en, this message translates to:
  /// **'greater than or equal to'**
  String get operatorGreaterEqual;

  /// No description provided for @operatorLessEqual.
  ///
  /// In en, this message translates to:
  /// **'less than or equal to'**
  String get operatorLessEqual;

  /// No description provided for @operatorContains.
  ///
  /// In en, this message translates to:
  /// **'contains'**
  String get operatorContains;

  /// No description provided for @operatorNotContains.
  ///
  /// In en, this message translates to:
  /// **'does not contain'**
  String get operatorNotContains;

  /// No description provided for @filterAnd.
  ///
  /// In en, this message translates to:
  /// **'AND'**
  String get filterAnd;

  /// No description provided for @filterOr.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get filterOr;

  /// No description provided for @filterNot.
  ///
  /// In en, this message translates to:
  /// **'NOT'**
  String get filterNot;

  /// No description provided for @deleteCondition.
  ///
  /// In en, this message translates to:
  /// **'Delete condition'**
  String get deleteCondition;

  /// No description provided for @direction.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get direction;

  /// No description provided for @match.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get match;

  /// No description provided for @includeSubtags.
  ///
  /// In en, this message translates to:
  /// **'Include subtags'**
  String get includeSubtags;

  /// No description provided for @unsupportedField.
  ///
  /// In en, this message translates to:
  /// **'Unsupported field.'**
  String get unsupportedField;

  /// No description provided for @chooseRange.
  ///
  /// In en, this message translates to:
  /// **'Choose range'**
  String get chooseRange;

  /// No description provided for @filterOptionsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load filter options.\n{error}'**
  String filterOptionsLoadFailed(Object error);

  /// No description provided for @newTransaction.
  ///
  /// In en, this message translates to:
  /// **'Add transaction'**
  String get newTransaction;

  /// No description provided for @noTagsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No tags available'**
  String get noTagsAvailable;

  /// No description provided for @tagCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not create the tag: {error}'**
  String tagCreateFailed(Object error);

  /// No description provided for @colorFor.
  ///
  /// In en, this message translates to:
  /// **'Color for “{name}”'**
  String colorFor(String name);

  /// No description provided for @selectAccount.
  ///
  /// In en, this message translates to:
  /// **'Select an account'**
  String get selectAccount;

  /// No description provided for @selectCategory.
  ///
  /// In en, this message translates to:
  /// **'Select a category'**
  String get selectCategory;

  /// No description provided for @selectDestinationAccount.
  ///
  /// In en, this message translates to:
  /// **'Select a destination account'**
  String get selectDestinationAccount;

  /// No description provided for @differentTransferAccounts.
  ///
  /// In en, this message translates to:
  /// **'Source and destination must be different accounts'**
  String get differentTransferAccounts;

  /// No description provided for @recordFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the transaction: {error}'**
  String recordFailed(Object error);

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @titleRequired.
  ///
  /// In en, this message translates to:
  /// **'A title is required'**
  String get titleRequired;

  /// No description provided for @addTag.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get addTag;

  /// No description provided for @record.
  ///
  /// In en, this message translates to:
  /// **'Save transaction'**
  String get record;

  /// No description provided for @recurringExpense.
  ///
  /// In en, this message translates to:
  /// **'Recurring expense'**
  String get recurringExpense;

  /// No description provided for @leaves.
  ///
  /// In en, this message translates to:
  /// **'Leaves'**
  String get leaves;

  /// No description provided for @enters.
  ///
  /// In en, this message translates to:
  /// **'Enters'**
  String get enters;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @greaterThanZero.
  ///
  /// In en, this message translates to:
  /// **'Greater than 0'**
  String get greaterThanZero;

  /// No description provided for @amountRequired.
  ///
  /// In en, this message translates to:
  /// **'Amount is required'**
  String get amountRequired;

  /// No description provided for @amountGreaterThanZero.
  ///
  /// In en, this message translates to:
  /// **'Amount must be greater than 0'**
  String get amountGreaterThanZero;

  /// No description provided for @loginIntro.
  ///
  /// In en, this message translates to:
  /// **'Get started with sync or a local account.'**
  String get loginIntro;

  /// No description provided for @withAccount.
  ///
  /// In en, this message translates to:
  /// **'With account'**
  String get withAccount;

  /// No description provided for @withoutAccount.
  ///
  /// In en, this message translates to:
  /// **'Local account'**
  String get withoutAccount;

  /// No description provided for @withAccountDescription.
  ///
  /// In en, this message translates to:
  /// **'Use email or Google to sync your expenses.'**
  String get withAccountDescription;

  /// No description provided for @localAccountDescription.
  ///
  /// In en, this message translates to:
  /// **'Add a name before opening this space on your device.'**
  String get localAccountDescription;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @enterYourName.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get enterYourName;

  /// No description provided for @enterEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get enterEmail;

  /// No description provided for @enterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get enterValidEmail;

  /// No description provided for @enterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get enterPassword;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Use at least 8 characters'**
  String get passwordMinLength;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get or;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @continueLocally.
  ///
  /// In en, this message translates to:
  /// **'Continue locally'**
  String get continueLocally;

  /// No description provided for @needAccountSignUp.
  ///
  /// In en, this message translates to:
  /// **'Need an account? Sign up'**
  String get needAccountSignUp;

  /// No description provided for @haveAccountSignIn.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? Sign in'**
  String get haveAccountSignIn;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get signUp;

  /// No description provided for @signInAction.
  ///
  /// In en, this message translates to:
  /// **'sign in'**
  String get signInAction;

  /// No description provided for @signUpAction.
  ///
  /// In en, this message translates to:
  /// **'create the account'**
  String get signUpAction;

  /// No description provided for @accountAlreadyAdded.
  ///
  /// In en, this message translates to:
  /// **'You already added an account with that email'**
  String get accountAlreadyAdded;

  /// No description provided for @accountExistsSignIn.
  ///
  /// In en, this message translates to:
  /// **'An account with that email already exists. Sign in with your password or with Google.'**
  String get accountExistsSignIn;

  /// No description provided for @emailSignInFailedGoogleHint.
  ///
  /// In en, this message translates to:
  /// **'Sign-in failed. If you registered with Google, use “Continue with Google”.'**
  String get emailSignInFailedGoogleHint;

  /// No description provided for @emailAuthFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not {action}: {error}'**
  String emailAuthFailed(String action, Object error);

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot your password?'**
  String get forgotPassword;

  /// No description provided for @resetPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get resetPasswordTitle;

  /// No description provided for @resetPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your email and we\'ll send you a reset link.'**
  String get resetPasswordSubtitle;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send reset link'**
  String get sendResetLink;

  /// No description provided for @resetEmailSent.
  ///
  /// In en, this message translates to:
  /// **'We sent a link to {email} to reset your password. The link opens in your browser.'**
  String resetEmailSent(String email);

  /// No description provided for @resetEmailSentReturnHint.
  ///
  /// In en, this message translates to:
  /// **'After resetting it, come back here and sign in with your new password.'**
  String get resetEmailSentReturnHint;

  /// No description provided for @resetRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send the reset email: {error}'**
  String resetRequestFailed(Object error);

  /// No description provided for @backToSignIn.
  ///
  /// In en, this message translates to:
  /// **'Back to sign in'**
  String get backToSignIn;

  /// No description provided for @verifyEmailTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get verifyEmailTitle;

  /// No description provided for @verifyEmailSent.
  ///
  /// In en, this message translates to:
  /// **'We sent a verification link to {email}. The link opens in your browser.'**
  String verifyEmailSent(String email);

  /// No description provided for @verifyEmailInstructions.
  ///
  /// In en, this message translates to:
  /// **'Open the link to verify your account, then come back here and sign in.'**
  String get verifyEmailInstructions;

  /// No description provided for @verifyEmailDone.
  ///
  /// In en, this message translates to:
  /// **'I verified my email'**
  String get verifyEmailDone;

  /// No description provided for @resendVerificationEmail.
  ///
  /// In en, this message translates to:
  /// **'Resend email'**
  String get resendVerificationEmail;

  /// No description provided for @resendVerificationCooldown.
  ///
  /// In en, this message translates to:
  /// **'Resend in {seconds}s'**
  String resendVerificationCooldown(int seconds);

  /// No description provided for @verificationEmailResent.
  ///
  /// In en, this message translates to:
  /// **'Verification email sent again.'**
  String get verificationEmailResent;

  /// No description provided for @resendVerificationFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not resend the email: {error}'**
  String resendVerificationFailed(Object error);

  /// No description provided for @emailStillNotVerified.
  ///
  /// In en, this message translates to:
  /// **'That email isn\'t verified yet. We sent you a new link.'**
  String get emailStillNotVerified;

  /// No description provided for @accountNotFoundForEmail.
  ///
  /// In en, this message translates to:
  /// **'There is no account for {email}.'**
  String accountNotFoundForEmail(String email);

  /// No description provided for @emailAlreadyVerified.
  ///
  /// In en, this message translates to:
  /// **'That email is already verified. Sign in with your account.'**
  String get emailAlreadyVerified;

  /// No description provided for @tooManyAttempts.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Wait a minute and try again.'**
  String get tooManyAttempts;

  /// No description provided for @emailSendFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not send the email. Try again in a few minutes.'**
  String get emailSendFailed;

  /// No description provided for @localAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not continue locally: {error}'**
  String localAccountFailed(Object error);

  /// No description provided for @googleSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not sign in with Google: {error}'**
  String googleSignInFailed(Object error);

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @newCategoryTooltip.
  ///
  /// In en, this message translates to:
  /// **'New category'**
  String get newCategoryTooltip;

  /// No description provided for @newTagTooltip.
  ///
  /// In en, this message translates to:
  /// **'New tag'**
  String get newTagTooltip;

  /// No description provided for @addScreen.
  ///
  /// In en, this message translates to:
  /// **'Add screen'**
  String get addScreen;

  /// No description provided for @dashboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your dashboard is empty. Add a widget to get started.'**
  String get dashboardEmpty;

  /// No description provided for @dashboardLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the dashboard.'**
  String get dashboardLoadFailed;

  /// No description provided for @removeWidget.
  ///
  /// In en, this message translates to:
  /// **'Remove widget'**
  String get removeWidget;

  /// No description provided for @removeWidgetConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Remove “{title}” from the dashboard?'**
  String removeWidgetConfirmation(String title);

  /// No description provided for @dashboardUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not update the dashboard: {error}'**
  String dashboardUpdateFailed(Object error);

  /// No description provided for @widgetRemoveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not remove the widget: {error}'**
  String widgetRemoveFailed(Object error);

  /// No description provided for @valueWidget.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get valueWidget;

  /// No description provided for @listWidget.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get listWidget;

  /// No description provided for @balanceWidget.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balanceWidget;

  /// No description provided for @chartWidget.
  ///
  /// In en, this message translates to:
  /// **'Chart'**
  String get chartWidget;

  /// No description provided for @widget.
  ///
  /// In en, this message translates to:
  /// **'Widget'**
  String get widget;

  /// No description provided for @moveLeft.
  ///
  /// In en, this message translates to:
  /// **'Move left'**
  String get moveLeft;

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get moveDown;

  /// No description provided for @moveRight.
  ///
  /// In en, this message translates to:
  /// **'Move right'**
  String get moveRight;

  /// No description provided for @chartLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the chart.'**
  String get chartLoadFailed;

  /// No description provided for @chartNoData.
  ///
  /// In en, this message translates to:
  /// **'No data to show yet.'**
  String get chartNoData;

  /// No description provided for @uncategorized.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get uncategorized;

  /// No description provided for @unknownAccount.
  ///
  /// In en, this message translates to:
  /// **'Unknown account'**
  String get unknownAccount;

  /// No description provided for @enterWidgetTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter a title'**
  String get enterWidgetTitle;

  /// No description provided for @selectWidgetCurrency.
  ///
  /// In en, this message translates to:
  /// **'Select a currency'**
  String get selectWidgetCurrency;

  /// No description provided for @configureWidgetFilter.
  ///
  /// In en, this message translates to:
  /// **'Configure a filter for this widget'**
  String get configureWidgetFilter;

  /// No description provided for @widgetSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the widget: {error}'**
  String widgetSaveFailed(Object error);

  /// No description provided for @widgetType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get widgetType;

  /// No description provided for @widgetTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get widgetTitle;

  /// No description provided for @background.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get background;

  /// No description provided for @low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get low;

  /// No description provided for @high.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get high;

  /// No description provided for @belowLow.
  ///
  /// In en, this message translates to:
  /// **'Below low'**
  String get belowLow;

  /// No description provided for @betweenLowHigh.
  ///
  /// In en, this message translates to:
  /// **'Between low and high'**
  String get betweenLowHigh;

  /// No description provided for @aboveHigh.
  ///
  /// In en, this message translates to:
  /// **'Above high'**
  String get aboveHigh;

  /// No description provided for @aggregation.
  ///
  /// In en, this message translates to:
  /// **'Aggregation'**
  String get aggregation;

  /// No description provided for @transactionCount.
  ///
  /// In en, this message translates to:
  /// **'Number of transactions'**
  String get transactionCount;

  /// No description provided for @groupBy.
  ///
  /// In en, this message translates to:
  /// **'Group by'**
  String get groupBy;

  /// No description provided for @chartType.
  ///
  /// In en, this message translates to:
  /// **'Chart type'**
  String get chartType;

  /// No description provided for @noAccountsUseArs.
  ///
  /// In en, this message translates to:
  /// **'There are no accounts yet; ARS will be used.'**
  String get noAccountsUseArs;

  /// No description provided for @noColor.
  ///
  /// In en, this message translates to:
  /// **'No color'**
  String get noColor;

  /// No description provided for @editFilter.
  ///
  /// In en, this message translates to:
  /// **'Edit filter'**
  String get editFilter;

  /// No description provided for @removeFilter.
  ///
  /// In en, this message translates to:
  /// **'Remove filter'**
  String get removeFilter;

  /// No description provided for @configureFilter.
  ///
  /// In en, this message translates to:
  /// **'Configure filter'**
  String get configureFilter;

  /// No description provided for @addWidgetAction.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addWidgetAction;

  /// No description provided for @saveWidgetAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveWidgetAction;

  /// No description provided for @widgetTypeStat.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get widgetTypeStat;

  /// No description provided for @widgetTypeList.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get widgetTypeList;

  /// No description provided for @widgetTypeBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get widgetTypeBalance;

  /// No description provided for @widgetTypeChart.
  ///
  /// In en, this message translates to:
  /// **'Chart'**
  String get widgetTypeChart;

  /// No description provided for @aggregationSum.
  ///
  /// In en, this message translates to:
  /// **'Sum'**
  String get aggregationSum;

  /// No description provided for @aggregationNet.
  ///
  /// In en, this message translates to:
  /// **'Net'**
  String get aggregationNet;

  /// No description provided for @aggregationCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get aggregationCount;

  /// No description provided for @groupCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get groupCategory;

  /// No description provided for @groupAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get groupAccount;

  /// No description provided for @groupMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get groupMonth;

  /// No description provided for @chartPie.
  ///
  /// In en, this message translates to:
  /// **'Pie'**
  String get chartPie;

  /// No description provided for @chartBar.
  ///
  /// In en, this message translates to:
  /// **'Bar'**
  String get chartBar;

  /// No description provided for @chartLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get chartLine;

  /// No description provided for @defaultExpensesMonth.
  ///
  /// In en, this message translates to:
  /// **'Monthly expenses'**
  String get defaultExpensesMonth;

  /// No description provided for @defaultIncomeMonth.
  ///
  /// In en, this message translates to:
  /// **'Monthly income'**
  String get defaultIncomeMonth;

  /// No description provided for @defaultMovementsMonth.
  ///
  /// In en, this message translates to:
  /// **'Monthly transactions'**
  String get defaultMovementsMonth;

  /// No description provided for @defaultTotalBalanceArs.
  ///
  /// In en, this message translates to:
  /// **'Total balance (ARS)'**
  String get defaultTotalBalanceArs;

  /// No description provided for @defaultMovements.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get defaultMovements;

  /// No description provided for @defaultRecentMovements.
  ///
  /// In en, this message translates to:
  /// **'Recent transactions'**
  String get defaultRecentMovements;

  /// No description provided for @liveVoice.
  ///
  /// In en, this message translates to:
  /// **'Live Voice'**
  String get liveVoice;

  /// No description provided for @endSession.
  ///
  /// In en, this message translates to:
  /// **'End session'**
  String get endSession;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get you;

  /// No description provided for @agentInterrupted.
  ///
  /// In en, this message translates to:
  /// **'Agent interrupted'**
  String get agentInterrupted;

  /// No description provided for @interrupted.
  ///
  /// In en, this message translates to:
  /// **'(interrupted)'**
  String get interrupted;

  /// No description provided for @voiceRuntimeError.
  ///
  /// In en, this message translates to:
  /// **'Voice error: {error}'**
  String voiceRuntimeError(Object error);

  /// No description provided for @toolRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get toolRunning;

  /// No description provided for @toolDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get toolDone;

  /// No description provided for @toolCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get toolCancelled;

  /// No description provided for @tool.
  ///
  /// In en, this message translates to:
  /// **'Tool'**
  String get tool;

  /// No description provided for @arguments.
  ///
  /// In en, this message translates to:
  /// **'arguments'**
  String get arguments;

  /// No description provided for @result.
  ///
  /// In en, this message translates to:
  /// **'result'**
  String get result;

  /// No description provided for @connected.
  ///
  /// In en, this message translates to:
  /// **'connected'**
  String get connected;

  /// No description provided for @connecting.
  ///
  /// In en, this message translates to:
  /// **'connecting'**
  String get connecting;

  /// No description provided for @idle.
  ///
  /// In en, this message translates to:
  /// **'idle'**
  String get idle;

  /// No description provided for @connectionLostReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Connection lost. Reconnecting automatically…'**
  String get connectionLostReconnecting;

  /// No description provided for @connectingPrompt.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get connectingPrompt;

  /// No description provided for @voiceStartPrompt.
  ///
  /// In en, this message translates to:
  /// **'Tap the mic to start a conversation'**
  String get voiceStartPrompt;

  /// No description provided for @typeMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message…'**
  String get typeMessage;

  /// No description provided for @microphonePermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission denied'**
  String get microphonePermissionDenied;

  /// No description provided for @recorderPermissionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not check microphone permission'**
  String get recorderPermissionFailed;

  /// No description provided for @pcmUnsupported.
  ///
  /// In en, this message translates to:
  /// **'PCM 16-bit streaming is not supported on this device'**
  String get pcmUnsupported;

  /// No description provided for @voiceStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to start: {error}'**
  String voiceStartFailed(Object error);

  /// No description provided for @microphoneOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open the microphone: {error}'**
  String microphoneOpenFailed(Object error);

  /// No description provided for @audioStreamFailed.
  ///
  /// In en, this message translates to:
  /// **'Audio stream error: {error}'**
  String audioStreamFailed(Object error);

  /// No description provided for @voiceStopFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to stop cleanly: {error}'**
  String voiceStopFailed(Object error);

  /// No description provided for @toolResponseUnmatched.
  ///
  /// In en, this message translates to:
  /// **'Tool response with no matching call: {result}'**
  String toolResponseUnmatched(Object result);

  /// No description provided for @toolCallsCancelled.
  ///
  /// In en, this message translates to:
  /// **'Tool calls cancelled: {ids}'**
  String toolCallsCancelled(String ids);

  /// No description provided for @deletedAccount.
  ///
  /// In en, this message translates to:
  /// **'Deleted account'**
  String get deletedAccount;

  /// No description provided for @transactionSaved.
  ///
  /// In en, this message translates to:
  /// **'{type} {updated, select, true{updated} other{recorded}} · {date}'**
  String transactionSaved(String type, String updated, String date);

  /// No description provided for @editTransactionType.
  ///
  /// In en, this message translates to:
  /// **'Edit {type}'**
  String editTransactionType(String type);

  /// No description provided for @chooseCategory.
  ///
  /// In en, this message translates to:
  /// **'Choose a category'**
  String get chooseCategory;

  /// No description provided for @transactionSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the transaction'**
  String get transactionSaveFailed;

  /// No description provided for @accountCreated.
  ///
  /// In en, this message translates to:
  /// **'Account created'**
  String get accountCreated;

  /// No description provided for @accountUpdated.
  ///
  /// In en, this message translates to:
  /// **'Account updated'**
  String get accountUpdated;

  /// No description provided for @categoryCreated.
  ///
  /// In en, this message translates to:
  /// **'Category created'**
  String get categoryCreated;

  /// No description provided for @categoryUpdated.
  ///
  /// In en, this message translates to:
  /// **'Category updated'**
  String get categoryUpdated;

  /// No description provided for @tagCreated.
  ///
  /// In en, this message translates to:
  /// **'Tag created'**
  String get tagCreated;

  /// No description provided for @tagUpdated.
  ///
  /// In en, this message translates to:
  /// **'Tag updated'**
  String get tagUpdated;

  /// No description provided for @editAccount.
  ///
  /// In en, this message translates to:
  /// **'Edit account'**
  String get editAccount;

  /// No description provided for @editCategory.
  ///
  /// In en, this message translates to:
  /// **'Edit category'**
  String get editCategory;

  /// No description provided for @editTag.
  ///
  /// In en, this message translates to:
  /// **'Edit tag'**
  String get editTag;

  /// No description provided for @tagSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the tag'**
  String get tagSaveFailed;

  /// No description provided for @actionLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the action'**
  String get actionLoadFailed;

  /// No description provided for @tapToRetry.
  ///
  /// In en, this message translates to:
  /// **'Tap to try again'**
  String get tapToRetry;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
