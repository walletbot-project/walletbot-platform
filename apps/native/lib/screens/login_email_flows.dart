part of 'login.dart';

/// Forgot-password panel: an email form that flips to a "check your inbox"
/// state once the reset email was requested. The reset link opens the web
/// app in the browser; the user returns here to sign in with the new
/// password.
class _ForgotPasswordPanel extends StatelessWidget {
  const _ForgotPasswordPanel({
    required this.submitting,
    required this.emailSent,
    required this.sentToEmail,
    required this.formKey,
    required this.emailController,
    required this.onSubmit,
    required this.onBack,
  });

  final bool submitting;
  final bool emailSent;
  final String sentToEmail;
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;

    if (emailSent) {
      return AuthPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthPanelTitle(
              icon: Icons.mark_email_read_rounded,
              title: l10n.resetPasswordTitle,
              subtitle: l10n.resetEmailSent(sentToEmail),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.resetEmailSentReturnHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 16),
            AuthPrimaryActionButton(
              submitting: false,
              label: l10n.backToSignIn,
              onPressed: onBack,
            ),
          ],
        ),
      );
    }

    return AuthPanel(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthPanelTitle(
              icon: Icons.lock_reset_rounded,
              title: l10n.resetPasswordTitle,
              subtitle: l10n.resetPasswordSubtitle,
            ),
            const SizedBox(height: 18),
            _LoginTextField(
              controller: emailController,
              enabled: !submitting,
              label: l10n.email,
              icon: Icons.alternate_email_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onSubmitted: (_) => onSubmit(),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (email.isEmpty) return l10n.enterEmail;
                if (!email.contains('@')) return l10n.enterValidEmail;
                return null;
              },
            ),
            const SizedBox(height: 16),
            AuthPrimaryActionButton(
              submitting: submitting,
              label: l10n.sendResetLink,
              onPressed: onSubmit,
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton(
                onPressed: submitting ? null : onBack,
                child: Text(l10n.backToSignIn),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Verification-pending panel shown after a sign-up, or a sign-in blocked by
/// an unverified email. The verification link opens the web app in the
/// browser; "I verified" returns to the sign-in form (email prefilled).
class _VerifyEmailPendingPanel extends StatelessWidget {
  const _VerifyEmailPendingPanel({
    required this.submitting,
    required this.email,
    required this.resendCooldown,
    required this.onResend,
    required this.onSignIn,
  });

  final bool submitting;
  final String email;
  final int resendCooldown;
  final VoidCallback onResend;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final canResend = resendCooldown <= 0 && !submitting;

    return AuthPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthPanelTitle(
            icon: Icons.mark_email_unread_rounded,
            title: l10n.verifyEmailTitle,
            subtitle: l10n.verifyEmailSent(email),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.verifyEmailInstructions,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          AuthPrimaryActionButton(
            submitting: submitting,
            label: l10n.verifyEmailDone,
            onPressed: onSignIn,
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: canResend ? onResend : null,
              child: Text(
                resendCooldown > 0
                    ? l10n.resendVerificationCooldown(resendCooldown)
                    : l10n.resendVerificationEmail,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
