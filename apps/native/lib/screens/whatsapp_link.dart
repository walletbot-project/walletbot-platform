import 'package:app/components/grouped_card.dart';
import 'package:app/convex/convex_client.dart';
import 'package:app/l10n/l10n.dart';
import 'package:app/whatsapp/whatsapp_link_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Connect or disconnect the user's WhatsApp number.
///
/// Owns its [WhatsappLinkController] rather than reading one from the app-wide
/// provider tree: nothing is cached, so there is no state worth keeping alive
/// between visits, and creating it here means the screen always opens against
/// fresh backend state.
class WhatsappLinkScreen extends StatelessWidget {
  const WhatsappLinkScreen({required this.isRemote, this.client, super.key});

  /// False for local-only accounts, which have no backend user to link to.
  final bool isRemote;

  /// The account's Convex connection, handed over by value because this route
  /// is pushed from the account switcher, which sits above the account-scoped
  /// providers. Null for a local account (and in widget tests), where nothing
  /// here touches the network.
  final ConvexClient? client;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<WhatsappLinkController>(
      create: (_) =>
          WhatsappLinkController(isRemote: isRemote, client: client)..load(),
      child: const _WhatsappLinkView(),
    );
  }
}

class _WhatsappLinkView extends StatelessWidget {
  const _WhatsappLinkView();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WhatsappLinkController>();

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.whatsappTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [_body(context, controller)],
      ),
    );
  }

  Widget _body(BuildContext context, WhatsappLinkController controller) {
    // A local account cannot link: there is no backend user on the other side.
    // Say so plainly instead of offering a button that would fail.
    if (!controller.isRemote) {
      return _MessageCard(
        icon: Icons.cloud_off_rounded,
        title: context.l10n.whatsappLocalAccountTitle,
        body: context.l10n.whatsappLocalAccountBody,
      );
    }

    return switch (controller.state) {
      WhatsappLinkState.loading => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      ),
      WhatsappLinkState.failed => _RetryCard(
        title: context.l10n.whatsappLoadFailed,
        action: context.l10n.tapToRetry,
        onRetry: controller.load,
      ),
      WhatsappLinkState.ready => _ready(context, controller),
    };
  }

  Widget _ready(BuildContext context, WhatsappLinkController controller) {
    // The deployment has no business number, so no code could be delivered
    // anywhere. Nothing actionable to show.
    if (!controller.available && !controller.isLinked) {
      return _MessageCard(
        icon: Icons.block_rounded,
        title: context.l10n.whatsappUnavailableTitle,
        body: context.l10n.whatsappUnavailableBody,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.isLinked)
          _LinkedNumbers(controller: controller)
        else
          _NotLinked(controller: controller),
      ],
    );
  }
}

class _NotLinked extends StatelessWidget {
  const _NotLinked({required this.controller});

  final WhatsappLinkController controller;

  @override
  Widget build(BuildContext context) {
    final code = controller.code;
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MessageCard(
          icon: Icons.chat_bubble_outline_rounded,
          title: context.l10n.whatsappNotConnectedTitle,
          body: context.l10n.whatsappNotConnectedBody,
        ),
        const SizedBox(height: 24),
        if (code == null)
          FilledButton.icon(
            onPressed: controller.busy ? null : () => _create(context),
            icon: const Icon(Icons.link_rounded),
            label: Text(context.l10n.whatsappConnect),
          )
        else ...[
          GroupedCard(
            borderRadius: groupedRadius(0, 1),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.whatsappCodeLabel,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Selectable so a user on a desktop-sized window can copy it
                  // by hand even if the clipboard button is unavailable.
                  SelectableText(
                    code.code,
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.whatsappCodeExpiryHint,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // The deep link is what keeps this flow user-initiated: it opens
          // WhatsApp with the code already typed, so the user's own tap opens
          // the 24h service window. Wallet Bot never messages first.
          if (code.deepLink != null)
            FilledButton.icon(
              onPressed: () => _open(context, code.deepLink!),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(context.l10n.whatsappOpenWhatsapp),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _copy(context, code.code),
            icon: const Icon(Icons.copy_rounded),
            label: Text(context.l10n.whatsappCopyCode),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: controller.dismissCode,
            child: Text(context.l10n.cancel),
          ),
        ],
      ],
    );
  }

  Future<void> _create(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.whatsappCodeFailed;
    try {
      await controller.createCode();
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _open(BuildContext context, String deepLink) async {
    final messenger = ScaffoldMessenger.of(context);
    final failed = context.l10n.whatsappOpenFailed;
    final uri = Uri.tryParse(deepLink);
    if (uri == null) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
      return;
    }
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) messenger.showSnackBar(SnackBar(content: Text(failed)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }

  Future<void> _copy(BuildContext context, String code) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = context.l10n.whatsappCodeCopied;
    await Clipboard.setData(ClipboardData(text: code));
    messenger.showSnackBar(SnackBar(content: Text(copied)));
  }
}

class _LinkedNumbers extends StatelessWidget {
  const _LinkedNumbers({required this.controller});

  final WhatsappLinkController controller;

  @override
  Widget build(BuildContext context) {
    final numbers = controller.numbers;
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MessageCard(
          icon: Icons.check_circle_outline_rounded,
          title: context.l10n.whatsappConnectedTitle,
          body: context.l10n.whatsappConnectedBody,
        ),
        const SizedBox(height: 24),
        for (var i = 0; i < numbers.length; i++) ...[
          GroupedCard(
            borderRadius: groupedRadius(i, numbers.length),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // `+` prefixed for readability only. The stored
                        // identity is the raw wa_id and is never rebuilt from
                        // a formatted number.
                        Text('+${numbers[i].waId}', style: textTheme.bodyLarge),
                        if (numbers[i].linkedAt != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            context.l10n.whatsappLinkedOn(
                              MaterialLocalizations.of(
                                context,
                              ).formatFullDate(numbers[i].linkedAt!),
                            ),
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: controller.busy
                        ? null
                        : () => _confirmUnlink(context, numbers[i].waId),
                    child: Text(context.l10n.whatsappDisconnect),
                  ),
                ],
              ),
            ),
          ),
          if (i != numbers.length - 1) const SizedBox(height: kGroupSpacing),
        ],
      ],
    );
  }

  Future<void> _confirmUnlink(BuildContext context, String waId) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.whatsappDisconnect),
        content: Text(l10n.whatsappDisconnectConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.whatsappDisconnect),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await controller.unlink(waId: waId);
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.whatsappDisconnectFailed)),
      );
    }
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GroupedCard(
      borderRadius: groupedRadius(0, 1),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 22, color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.bodyLarge),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryCard extends StatelessWidget {
  const _RetryCard({
    required this.title,
    required this.action,
    required this.onRetry,
  });

  final String title;
  final String action;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return GroupedCard(
      borderRadius: groupedRadius(0, 1),
      onTap: onRetry,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: colors.error),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    action,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
