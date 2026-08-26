import 'package:flutter/foundation.dart';

import '../app_config/client_info.dart';
import '../data/data.dart';
import '../shared/money.dart' show centsToDouble;
import 'agent_generated.dart';

/// Builds the mint request for the live-token fetch: platform identity, the
/// user's locale/timezone, and the USER_CONTEXT snapshot rendered into the
/// system prompt (packages/backend/convex/live/createToken.ts).
///
/// Native builds the snapshot from Drift — its own source of truth, always
/// fresh even when sync lags. Best-effort by design: a failed read drops its
/// section rather than blocking the session; the server treats every field as
/// optional and re-caps everything.
///
/// The web mirror is apps/web/src/lib/agent-context.ts — keep the shapes in
/// step (they are validated by v1/live/actions.ts and sanitizeAgentContext).
Future<Map<String, Object?>> buildLiveTokenMintArgs({
  required AppRepositories repositories,
  required ClientInfo clientInfo,
  required String localeTag,
  String? userName,
  String? userEmail,
  String? defaultCurrency,
  String? language,
  String? theme,
}) async {
  final context = <String, Object?>{
    'userName': ?_nonEmpty(userName),
    'userEmail': ?_nonEmpty(userEmail),
    'settings': {
      'defaultCurrency': ?_nonEmpty(defaultCurrency),
      'language': ?language,
      'theme': ?theme,
    },
  };

  try {
    final accounts = await repositories.accounts.listActive();
    context['accounts'] = [
      for (final account in accounts.take(kAgentContextAccountsCap))
        {'id': account.id, 'name': account.name, 'currency': account.currency},
    ];

    final categories = await repositories.categories.listActive();
    context['categories'] = [
      for (final category in categories.take(kAgentContextCategoriesCap))
        {'id': category.id, 'name': category.name},
    ];

    final tags = await repositories.tags.listActive();
    context['tags'] = [
      for (final tag in tags.take(kAgentContextTagsCap))
        {
          'id': tag.id,
          'name': tag.name,
          if (tag.parentId != null) 'parentId': tag.parentId,
        },
    ];

    final accountNames = {for (final a in accounts) a.id: a.name};
    final categoryNames = {for (final c in categories) c.id: c.name};
    final recent = await repositories.transactions.list(
      const TransactionFilter(),
      limit: kAgentContextRecentTransactionsCap,
      ordering: TxnOrdering.dateDesc,
    );
    context['recentTransactions'] = [
      for (final txn in recent)
        {
          'name': txn.name,
          'amount': centsToDouble(txn.amount),
          'currency': txn.currency,
          'type': txn.type,
          if (accountNames[txn.accountId] != null)
            'account': accountNames[txn.accountId],
          if (categoryNames[txn.categoryId] != null)
            'category': categoryNames[txn.categoryId],
          'date': _formatLocalDate(txn.date.toInt()),
        },
    ];

    final memories = await repositories.agentMemories.listActive();
    context['memories'] = [
      for (final memory in memories.take(kAgentContextMemoriesCap))
        {'id': memory.id, 'content': memory.content},
    ];
  } catch (e) {
    // The snapshot is a nicety; the session must connect without it.
    debugPrint('[voice] context payload build failed: $e');
  }

  return {
    'platform': clientInfo.platform,
    'appVersion': clientInfo.appVersion,
    'locale': localeTag,
    // Dart has no dependency-free IANA timezone; the server computes the
    // date line from the UTC offset instead (D8).
    'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
    'context': context,
  };
}

String? _nonEmpty(String? value) =>
    value == null || value.isEmpty ? null : value;

String _pad(int value) => value.toString().padLeft(2, '0');

/// Local wall-clock "YYYY-MM-DD HH:mm" for the snapshot's movement lines.
String _formatLocalDate(int ms) {
  final date = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${date.year}-${_pad(date.month)}-${_pad(date.day)} '
      '${_pad(date.hour)}:${_pad(date.minute)}';
}
