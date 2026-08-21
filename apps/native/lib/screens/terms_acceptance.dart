import 'dart:async';

import 'package:app/l10n/l10n.dart';
import 'package:app/legal/terms_acceptance.dart';
import 'package:app/legal/terms_checkbox.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

/// Acceptance step for accounts whose acceptance of the legal documents needs
/// attention, shown by `_TermsGate` (main.dart) instead of the app. Blocking
/// when the controller says [TermsGateStatus.required] (never accepted, below
/// the min floor, grace expired); dismissible — a "Not now" action and the
/// grace deadline in the copy — on [TermsGateStatus.requested] (old but
/// still-valid acceptance). The native counterpart of the web `TermsGate`
/// (apps/web/src/components/auth/terms-gate.tsx).
class TermsAcceptanceScreen extends StatefulWidget {
  const TermsAcceptanceScreen({super.key});

  @override
  State<TermsAcceptanceScreen> createState() => _TermsAcceptanceScreenState();
}

class _TermsAcceptanceScreenState extends State<TermsAcceptanceScreen> {
  bool _accepted = false;
  bool _submitting = false;

  Future<void> _continue() async {
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await context.read<TermsAcceptanceController>().accept();
      // On success the controller flips to `cleared` and `_TermsGate`
      // replaces this screen with the app.
    } catch (e) {
      debugPrint('terms: accept failed: $e');
      messenger.showSnackBar(SnackBar(content: Text(l10n.termsAcceptFailed)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final terms = context.watch<TermsAcceptanceController>();
    final dismissible = terms.status == TermsGateStatus.requested;
    final graceEndsAt = terms.graceEndsAt;
    final deadline = dismissible && graceEndsAt != null
        ? DateFormat.yMMMMd(
            context.localeName,
          ).format(DateTime.fromMillisecondsSinceEpoch(graceEndsAt))
        : null;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                // Mirrors `_Panel` in screens/login.dart so the gate reads as
                // part of the same auth surface.
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.8),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow.withValues(alpha: 0.1),
                        blurRadius: 30,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: colors.primaryContainer,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                Icons.verified_user_rounded,
                                color: colors.onPrimaryContainer,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.l10n.termsGateTitle,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w900),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    context.l10n.termsGateDescription,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colors.onSurfaceVariant,
                                      fontWeight: FontWeight.w600,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (deadline != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            context.l10n.termsDeadline(deadline),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        TermsAcceptanceCheckbox(
                          value: _accepted,
                          enabled: !_submitting,
                          onChanged: (value) =>
                              setState(() => _accepted = value),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 54,
                          child: FilledButton(
                            onPressed: _submitting || !_accepted
                                ? null
                                : () => unawaited(_continue()),
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _submitting
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(context.l10n.termsContinue),
                          ),
                        ),
                        if (dismissible) ...[
                          const SizedBox(height: 6),
                          Center(
                            child: TextButton(
                              onPressed: _submitting
                                  ? null
                                  : () => context
                                        .read<TermsAcceptanceController>()
                                        .dismissPrompt(),
                              child: Text(context.l10n.termsLater),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
