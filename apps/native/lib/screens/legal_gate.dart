import 'package:app/auth/auth_controller.dart';
import 'package:app/database.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/legal/legal_acceptance_controller.dart';
import 'package:app/legal/legal_consent_checks.dart';
import 'package:app/screens/account_switcher.dart';
import 'package:app/screens/auth_scaffold.dart';
import 'package:app/user_settings/default_currency_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Terms/Privacy acceptance gate: what an account sees instead of the app
/// until it has accepted the current documents.
///
/// Same surface as the sign-in screens ([AuthBackdrop] + [AuthPanel]) but
/// vertically centred, and it never dead-ends: while the grace period runs the
/// prompt can wait ("Later"), and once it is blocking there is still a way to
/// another account or out of this one.
class LegalGateScreen extends StatefulWidget {
  const LegalGateScreen({super.key});

  @override
  State<LegalGateScreen> createState() => _LegalGateScreenState();
}

class _LegalGateScreenState extends State<LegalGateScreen> {
  bool _ageConfirmed = false;
  bool _accepted = false;
  bool _submitting = false;

  Future<void> _submit() async {
    final controller = context.read<LegalAcceptanceController>();
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;

    setState(() => _submitting = true);
    try {
      await controller.accept(
        documents: controller.verdict.pending,
        ageConfirmed: _ageConfirmed,
      );
    } catch (e) {
      debugPrint('legal: accept failed: $e');
      messenger.showSnackBar(SnackBar(content: Text(l10n.legalAcceptFailed)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openAccounts() async {
    await showAccountSwitcher(
      context,
      defaultCurrency: context.read<DefaultCurrencyController>(),
      database: context.read<AppDatabase>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final controller = context.watch<LegalAcceptanceController>();
    final verdict = controller.verdict;
    final auth = context.watch<AuthController>();
    // Nothing pending can still be rendered for a frame while the parent
    // rebuilds; fall back to both documents rather than crash on an empty list.
    final pending = verdict.pending.isEmpty
        ? LegalDocumentKind.values
        : verdict.pending;

    final title = verdict.firstAcceptance
        ? l10n.legalFirstTitle
        : pending.length > 1
        ? l10n.legalUpdatedBothTitle
        : pending.first == LegalDocumentKind.privacy
        ? l10n.legalUpdatedPrivacyTitle
        : l10n.legalUpdatedTermsTitle;
    final subtitle = verdict.firstAcceptance
        ? l10n.legalFirstSubtitle
        : verdict.blocking
        ? l10n.legalUpdatedSubtitle
        : l10n.legalUpdatedSubtitleGrace;

    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AuthBackdrop()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                child: ConstrainedBox(
                  // Centred in the window, top-aligned scrolling once the
                  // panel is taller than it — the web scaffold does the same.
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 480),
                      child: AuthPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AuthPanelTitle(
                              icon: Icons.policy_rounded,
                              title: title,
                              subtitle: subtitle,
                            ),
                            const SizedBox(height: 14),
                            LegalConsentChecks(
                              documents: pending,
                              ageConfirmed: _ageConfirmed,
                              accepted: _accepted,
                              enabled: !_submitting,
                              onAgeConfirmedChanged: (value) =>
                                  setState(() => _ageConfirmed = value),
                              onAcceptedChanged: (value) =>
                                  setState(() => _accepted = value),
                            ),
                            const SizedBox(height: 14),
                            AuthPrimaryActionButton(
                              submitting: _submitting,
                              label: l10n.legalAcceptAction,
                              onPressed: _ageConfirmed && _accepted
                                  ? _submit
                                  : null,
                            ),
                            if (!verdict.blocking)
                              TextButton(
                                onPressed: _submitting
                                    ? null
                                    : controller.dismissForSession,
                                child: Text(l10n.legalLater),
                              ),
                            const SizedBox(height: 4),
                            Wrap(
                              alignment: WrapAlignment.center,
                              children: [
                                if (auth.accounts.length > 1)
                                  TextButton(
                                    onPressed: _submitting
                                        ? null
                                        : () => _openAccounts(),
                                    child: Text(l10n.legalUseAnotherAccount),
                                  ),
                                TextButton(
                                  onPressed: _submitting
                                      ? null
                                      : () => auth.signOut(),
                                  child: Text(l10n.signOut),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
