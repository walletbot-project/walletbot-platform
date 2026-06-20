import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'sync_engine.dart';
import 'sync_status.dart';

/// Tiny status indicator for the home AppBar. Shows the current sync state
/// and lets the user force a sync by tapping. Hidden when the engine has
/// never run (i.e. local-only accounts).
class SyncStatusPill extends StatelessWidget {
  const SyncStatusPill({super.key});

  @override
  Widget build(BuildContext context) {
    final engine = context.watch<SyncEngine>();
    final status = engine.status;

    final (icon, label, color) = switch (status) {
      SyncStatus.idle => (
        Icons.cloud_outlined,
        'Sync',
        Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      SyncStatus.syncing => (
        Icons.sync_rounded,
        'Syncing…',
        Theme.of(context).colorScheme.primary,
      ),
      SyncStatus.synced => (
        Icons.cloud_done_rounded,
        'Synced',
        Theme.of(context).colorScheme.primary,
      ),
      SyncStatus.error => (
        Icons.cloud_off_rounded,
        'Sync error',
        Theme.of(context).colorScheme.error,
      ),
    };

    return Tooltip(
      message: _tooltipFor(status, engine),
      child: InkWell(
        onTap: status == SyncStatus.syncing
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

  String _tooltipFor(SyncStatus status, SyncEngine engine) {
    switch (status) {
      case SyncStatus.idle:
        return 'Tap to sync';
      case SyncStatus.syncing:
        return 'Sync in progress';
      case SyncStatus.synced:
        final last = engine.lastSyncedAt;
        if (last == null) return 'Synced. Tap to sync again.';
        final ago = DateTime.now().difference(last);
        return 'Last synced ${_formatAgo(ago)} ago. Tap to sync again.';
      case SyncStatus.error:
        final err = engine.lastError;
        return err == null
            ? 'Sync error. Tap to retry.'
            : 'Sync error: $err. Tap to retry.';
    }
  }

  String _formatAgo(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}
