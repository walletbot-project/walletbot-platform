/**
 * Central dictionary of all user-facing strings.
 * Organized by feature > context > key.
 *
 * When we add multi-language support, this becomes the "en" locale
 * and we add parallel dictionaries for other locales.
 */
export const en = {
    // --- Common ---
    'common.save': 'Save',
    'common.cancel': 'Cancel',
    'common.delete': 'Delete',
    'common.edit': 'Edit',
    'common.add': 'Add',
    'common.close': 'Close',
    'common.confirm': 'Confirm',
    'common.search': 'Search',
    'common.loading': 'Loading...',
    'common.error': 'Something went wrong',
    'common.retry': 'Retry',
    'common.empty': 'Nothing here yet',
    'common.back': 'Back',
    'common.next': 'Next',
    'common.done': 'Done',
    'common.yes': 'Yes',
    'common.no': 'No',
    'common.or': 'or',
    'common.all': 'All',
    'common.none': 'None',
    'common.optional': 'Optional',
    'common.required': 'Required',
    'common.signOut': 'Sign out',

    // --- Auth ---
    'auth.login.title': 'Welcome',
    'auth.login.subtitle': 'Sign in to continue',
    'auth.login.google': 'Continue with Google',

    // --- Accounts ---
    'accounts.title': 'Accounts',
    'accounts.add': 'Add Account',
    'accounts.edit': 'Edit Account',
    'accounts.delete': 'Delete Account',
    'accounts.delete.confirm':
        'Are you sure? This account must have no transactions.',
    'accounts.name': 'Account Name',
    'accounts.name.placeholder': 'e.g., Bank, Cash, Credit Card',
    'accounts.type': 'Account Type',
    'accounts.type.asset': 'Asset',
    'accounts.type.asset.description': 'Money you have (bank, cash, savings)',
    'accounts.type.liability': 'Liability',
    'accounts.type.liability.description': 'Money you owe (credit card, loan)',
    'accounts.currency': 'Default Currency',
    'accounts.icon': 'Icon',
    'accounts.setDefault': 'Set as Default',
    'accounts.isDefault': 'Default Account',
    'accounts.balance': 'Balance',
    'accounts.empty': 'No accounts yet',
    'accounts.error.hasTransactions':
        'Cannot delete an account that has transactions',
    'accounts.error.notFound': 'Account not found',
    'accounts.error.notAuthorized': 'Not authorized',

    // Default account names
    'accounts.default.cash': 'Cash',
    'accounts.default.bank': 'Bank',
    'accounts.default.creditCard': 'Credit Card',

    // --- Categories ---
    'categories.title': 'Categories',
    'categories.add': 'Add Category',
    'categories.edit': 'Edit Category',
    'categories.delete': 'Delete Category',
    'categories.delete.confirm':
        'Are you sure? Transactions with this category will be moved to "Other".',
    'categories.name': 'Category Name',
    'categories.name.placeholder': 'e.g., Groceries, Rent',
    'categories.icon': 'Icon',
    'categories.color': 'Color',
    'categories.parent': 'Parent Category',
    'categories.parent.none': 'None (top-level)',
    'categories.empty': 'No categories',
    'categories.error.notFound': 'Category not found',
    'categories.error.notAuthorized': 'Not authorized',
    'categories.error.systemReadonly': 'System categories cannot be deleted',

    // System category names
    'categories.system.groceries': 'Groceries',
    'categories.system.transport': 'Transport',
    'categories.system.dining': 'Dining',
    'categories.system.entertainment': 'Entertainment',
    'categories.system.utilities': 'Utilities',
    'categories.system.health': 'Health',
    'categories.system.shopping': 'Shopping',
    'categories.system.other': 'Other',
    'categories.system.salary': 'Salary',
    'categories.system.freelance': 'Freelance',
    'categories.system.investment': 'Investment',
    'categories.system.gift': 'Gift',

    // --- Transactions ---
    'transactions.title': 'Transactions',
    'transactions.add': 'Add Transaction',
    'transactions.edit': 'Edit Transaction',
    'transactions.delete': 'Delete Transaction',
    'transactions.delete.confirm':
        'Are you sure you want to delete this transaction?',
    'transactions.type': 'Type',
    'transactions.type.expense': 'Expense',
    'transactions.type.income': 'Income',
    'transactions.type.transfer': 'Transfer',
    'transactions.amount': 'Amount',
    'transactions.amount.placeholder': '0.00',
    'transactions.description': 'Description',
    'transactions.description.placeholder': 'What was this for?',
    'transactions.category': 'Category',
    'transactions.account': 'Account',
    'transactions.fromAccount': 'From Account',
    'transactions.toAccount': 'To Account',
    'transactions.date': 'Date',
    'transactions.notes': 'Notes',
    'transactions.notes.placeholder': 'Add a note...',
    'transactions.tags': 'Tags',
    'transactions.empty': 'No transactions yet',
    'transactions.error.notFound': 'Transaction not found',
    'transactions.error.notAuthorized': 'Not authorized',
    'transactions.error.positiveAmount': 'Amount must be positive',
    'transactions.error.accountRequired': 'Account is required',

    // --- Tags ---
    'tags.title': 'Tags',
    'tags.add': 'Add Tag',
    'tags.edit': 'Edit Tag',
    'tags.delete': 'Delete Tag',
    'tags.delete.confirm':
        'Are you sure? This tag will be removed from all transactions.',
    'tags.name': 'Tag Name',
    'tags.name.placeholder': 'e.g., vacation, reimbursable',
    'tags.color': 'Color',
    'tags.empty': 'No tags yet',
    'tags.error.notFound': 'Tag not found',
    'tags.error.duplicate': 'A tag with this name already exists',

    // --- Dashboard ---
    'dashboard.title': 'Dashboard',
    'dashboard.totalExpenses': 'Total Expenses',
    'dashboard.totalIncome': 'Total Income',
    'dashboard.netFlow': 'Net Flow',
    'dashboard.byCategory': 'By Category',
    'dashboard.recentTransactions': 'Recent Transactions',

    // --- Currency ---
    'currency.USD': 'US Dollar',
    'currency.ARS': 'Argentine Peso',
    'currency.EUR': 'Euro',
    'currency.BRL': 'Brazilian Real',

    // --- Settings ---
    'settings.title': 'Settings',
    'settings.defaultCurrency': 'Default Currency',
    'settings.language': 'Language',

    // --- Toasts ---
    'toast.success.saved': 'Saved successfully',
    'toast.success.deleted': 'Deleted successfully',
    'toast.success.updated': 'Updated successfully',
    'toast.error.generic': 'Something went wrong. Please try again.',
    'toast.loading': 'Saving...',
} as const

export type TranslationKey = keyof typeof en
