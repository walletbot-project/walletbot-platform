import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:app/auth/account.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/screens/account_switcher.dart';

import 'sync_engine.dart';
import 'sync_status.dart';

/// Tiny status indicator for the home AppBar. Shows the current sync state
/// and lets the user force a sync by tapping. On a local account there is
/// nothing to sync, so tapping opens the flow that promotes it to an online
/// account instead.
class SyncStatusPill extends StatelessWidget {
  const SyncStatusPill({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SyncEngine>();
    final status = engine.status;
    final active = context.watch<AuthController>().activeAccount;
    final isLocal = active?.type == AccountType.local;

    final (icon, label, color) = switch (status) {
      SyncStatus.idle => (
        Icons.cloud_outlined,
        context.l10n.sync,
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      SyncStatus.syncing => (
        Icons.sync_rounded,
        context.l10n.syncing,
        Theme.of(context).colorScheme.primary,
      ),
      SyncStatus.synced => (
        Icons.cloud_done_rounded,
        context.l10n.synced,
        Theme.of(context).colorScheme.primary,
      ),
      SyncStatus.error => (
        Icons.cloud_off_rounded,
        context.l10n.syncError,
        Theme.of(context).colorScheme.error,
      ),
    };

    return Tooltip(
      message: isLocal
          ? context.l10n.promoteBackUpData
          : _tooltipFor(context, status, engine),
      child: InkWell(
        onTap: isLocal
            ? () => unawaited(
                openLocalPromotion(
                  context,
                  active!,
                  context.read<AppDatabase>(),
                ),
              )
            : status == SyncStatus.syncing
            ? null
            : () => unawaited(engine.sync()),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (status == SyncStatus.syncing)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _tooltipFor(
    BuildContext context,
    SyncStatus status,
    SyncEngine engine,
  ) {
    switch (status) {
      case SyncStatus.idle:
        return context.l10n.tapToSync;
      case SyncStatus.syncing:
        return context.l10n.syncInProgress;
      case SyncStatus.synced:
        final last = engine.lastSyncedAt;
        if (last == null) return context.l10n.syncedTapAgain;
        final ago = DateTime.now().difference(last);
        return context.l10n.lastSynced(_formatAgo(context, ago));
      case SyncStatus.error:
        final err = engine.lastError;
        return err == null
            ? context.l10n.syncErrorRetry
            : context.l10n.syncErrorDetails(err);
    }
  }

  String _formatAgo(BuildContext context, Duration d) {
    if (d.inSeconds < 60) return context.l10n.durationSeconds(d.inSeconds);
    if (d.inMinutes < 60) return context.l10n.durationMinutes(d.inMinutes);
    if (d.inHours < 24) return context.l10n.durationHours(d.inHours);
    return context.l10n.durationDays(d.inDays);
  }
}
