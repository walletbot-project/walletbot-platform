import 'dart:async';

import 'package:app/app_config/app_config_banner_list.dart';
import 'package:app/app_config/client_info.dart';
import 'package:app/auth/auth_controller.dart';
import 'package:app/database.dart' show LegalDocumentKind;
import 'package:app/l10n/l10n.dart';
import 'package:app/legal/legal_acceptance_payload.dart';
import 'package:app/legal/legal_consent_checks.dart';
import 'package:app/screens/auth_scaffold.dart';
import 'package:app/telemetry/business_metrics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

part 'login_email_flows.dart';

/// Sign in with Apple ships on iOS only. Apple requires it there because the
/// app offers another third-party sign-in (App Store Review Guideline 4.8);
/// everywhere else the button would have to run Apple's browser flow, which
/// needs a Services ID this project does not have.
final bool _appleSignInAvailable =
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

enum _EmailAuthMode { signIn, signUp }

enum _LoginPath { remote, local }

/// Which panel the remote path shows. [credentials] is the sign-in/sign-up
/// form; the other two replace it entirely until the user navigates back.
enum _RemoteFlow { credentials, forgotPassword, verifyPending }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.canDismiss = false});

  /// When true the screen was surfaced on top of an active account (via the
  /// account switcher's "add account" action), so it shows a close button that
  /// returns to the current account. When false it is the app root shown at
  /// first launch and offers no way out but signing in.
  final bool canDismiss;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _resendCooldownSeconds = 30;

  final _remoteFormKey = GlobalKey<FormState>();
  final _forgotFormKey = GlobalKey<FormState>();
  final _localFormKey = GlobalKey<FormState>();
  final _remoteNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _localNameController = TextEditingController();

  _LoginPath _path = _LoginPath.remote;
  _EmailAuthMode _emailMode = _EmailAuthMode.signIn;
  _RemoteFlow _remoteFlow = _RemoteFlow.credentials;
  bool _submitting = false;

  /// Sign-up consent. Never pre-ticked, and the sign-up button stays dead
  /// until both are: affirmative acceptance, not browse-wrap
  /// (docs/legal/README.md). Only the email sign-up path collects them —
  /// Google sign-in and local accounts reach the acceptance gate instead,
  /// which is where an already-registered user is never asked twice.
  bool _ageConfirmed = false;
  bool _acceptedLegal = false;

  /// Email echoed in the pending/sent copy of the new flows.
  String _pendingEmail = '';

  /// Forgot-password panel: false = form, true = success state.
  bool _resetEmailSent = false;

  /// Seconds until the resend-verification button re-enables. UX throttling
  /// only — the backend re-sends on blocked sign-in attempts regardless.
  int _resendCooldown = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _remoteNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _localNameController.dispose();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendCooldown = _resendCooldownSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendCooldown -= 1);
      if (_resendCooldown <= 0) timer.cancel();
    });
  }

  Future<void> _submitRemote() async {
    if (!_remoteFormKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final auth = context.read<AuthController>();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    try {
      if (_emailMode == _EmailAuthMode.signIn) {
        await auth.signInWithEmail(
          email: email,
          password: password,
          rejectExisting: widget.canDismiss,
        );
      } else {
        final clientInfo = context.read<ClientInfo?>();
        await auth.signUpWithEmail(
          name: _remoteNameController.text.trim(),
          email: email,
          password: password,
          rejectExisting: widget.canDismiss,
          // Both documents: a new account accepts the whole agreement, and the
          // button cannot be pressed unless both boxes are ticked.
          acceptance: LegalAcceptancePayload(
            documents: LegalDocumentKind.values,
            ageConfirmed: _ageConfirmed,
            platform: clientInfo?.platform ?? clientPlatform(),
            appVersion: clientInfo?.appVersion,
            locale: Localizations.localeOf(context).toLanguageTag(),
          ),
        );
      }
    } on AccountAlreadyAddedError {
      messenger.showSnackBar(SnackBar(content: Text(l10n.accountAlreadyAdded)));
    } on AccountExistsException {
      // Registering an existing address used to land on the verify-pending
      // screen waiting for mail the backend never sends. Say what happened
      // and drop the user into sign-in.
      if (mounted) {
        setState(() => _emailMode = _EmailAuthMode.signIn);
      }
      messenger.showSnackBar(SnackBar(content: Text(l10n.accountExistsSignIn)));
    } on EmailNotVerifiedException {
      // The backend already (re-)sent the verification email on this attempt.
      if (mounted) {
        setState(() {
          _pendingEmail = email;
          _remoteFlow = _RemoteFlow.verifyPending;
        });
        _startResendCooldown();
      }
      if (_emailMode == _EmailAuthMode.signIn) {
        // Repeat attempt (e.g. tapped "I verified" too early): say so.
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.emailStillNotVerified)),
        );
      }
    } catch (e) {
      // Generic, account-independent hint: many failed sign-ins are users who
      // actually registered with Google. Avoids leaking whether the email
      // exists or which provider it uses.
      final message = _emailMode == _EmailAuthMode.signIn
          ? l10n.emailSignInFailedGoogleHint
          : l10n.emailAuthFailed(_emailMode.actionLabel(l10n), e);
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitForgotPassword() async {
    if (!_forgotFormKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final auth = context.read<AuthController>();
    final email = _emailController.text.trim();

    try {
      await auth.requestPasswordReset(email: email);
      // Only reached when an email really went out, so the panel's copy can
      // name the address. It used to flip on any 200, and an address with no
      // account behind it answered 200 without sending anything.
      if (mounted) {
        setState(() {
          _pendingEmail = email;
          _resetEmailSent = true;
        });
      }
    } on AuthHttpError catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (e.code) {
            'account_not_found' => l10n.accountNotFoundForEmail(email),
            'rate_limited' => l10n.tooManyAttempts,
            'email_send_failed' => l10n.emailSendFailed,
            _ => l10n.resetRequestFailed(e),
          }),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.resetRequestFailed(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resendVerification() async {
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final auth = context.read<AuthController>();

    try {
      await auth.resendVerificationEmail(email: _pendingEmail);
      // Popping the screen mid-request disposes this State; _startResendCooldown
      // would then setState (and arm a timer) on a dead widget.
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.verificationEmailResent)),
      );
      // Only a confirmed send earns the cooldown — the outcomes below never
      // produce an email, so locking the button would just hide the reason.
      _startResendCooldown();
    } on AuthHttpError catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (e.code) {
            'account_not_found' => l10n.accountNotFoundForEmail(_pendingEmail),
            'email_already_verified' => l10n.emailAlreadyVerified,
            'rate_limited' => l10n.tooManyAttempts,
            'email_send_failed' => l10n.emailSendFailed,
            _ => l10n.resendVerificationFailed(e),
          }),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.resendVerificationFailed(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _openForgotPassword() {
    setState(() {
      _remoteFlow = _RemoteFlow.forgotPassword;
      _resetEmailSent = false;
    });
  }

  void _returnToSignIn() {
    setState(() {
      _remoteFlow = _RemoteFlow.credentials;
      _emailMode = _EmailAuthMode.signIn;
      _resetEmailSent = false;
    });
  }

  Future<void> _submitLocal() async {
    if (!_localFormKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final auth = context.read<AuthController>();
    final businessMetrics = context.read<BusinessMetrics?>();
    final l10n = context.l10n;
    try {
      await auth.addLocal(name: _localNameController.text.trim());
      businessMetrics?.userAccountCreated(authMethod: 'local');
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.localAccountFailed(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await context.read<AuthController>().signInWithApple(
        rejectExisting: widget.canDismiss,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      // Dismissing Apple's sheet is a choice, not a failure.
      if (e.code != AuthorizationErrorCode.canceled) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.appleSignInFailed(e))),
        );
      }
    } on AccountAlreadyAddedError {
      messenger.showSnackBar(SnackBar(content: Text(l10n.accountAlreadyAdded)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.appleSignInFailed(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await context.read<AuthController>().signInWithGoogle(
        rejectExisting: widget.canDismiss,
      );
    } on GoogleSignInException catch (e) {
      // The user dismissing the Google sheet isn't an error worth surfacing.
      if (e.code != GoogleSignInExceptionCode.canceled) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.googleSignInFailed(e))),
        );
      }
    } on AccountAlreadyAddedError {
      messenger.showSnackBar(SnackBar(content: Text(l10n.accountAlreadyAdded)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.googleSignInFailed(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: AuthBackdrop()),
          SafeArea(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _HeroHeader(),
                            const SizedBox(height: 22),
                            const AppConfigBannerList(
                              placement: 'auth',
                              bottomSpacing: 14,
                            ),
                            _PathPicker(
                              selected: _path,
                              enabled: !_submitting,
                              onChanged: (path) => setState(() => _path = path),
                            ),
                            const SizedBox(height: 14),
                            _AuthPathSwitcher(
                              path: _path,
                              remote: KeyedSubtree(
                                key: ValueKey(_remoteFlow),
                                child: switch (_remoteFlow) {
                                  _RemoteFlow.credentials => _RemoteLoginPanel(
                                    mode: _emailMode,
                                    submitting: _submitting,
                                    formKey: _remoteFormKey,
                                    nameController: _remoteNameController,
                                    emailController: _emailController,
                                    passwordController: _passwordController,
                                    ageConfirmed: _ageConfirmed,
                                    acceptedLegal: _acceptedLegal,
                                    onAgeConfirmedChanged: (value) =>
                                        setState(() => _ageConfirmed = value),
                                    onAcceptedLegalChanged: (value) =>
                                        setState(() => _acceptedLegal = value),
                                    onModeChanged: (mode) =>
                                        setState(() => _emailMode = mode),
                                    onSubmit: _submitRemote,
                                    onApple: _appleSignInAvailable
                                        ? _signInWithApple
                                        : null,
                                    onGoogle: _signInWithGoogle,
                                    onForgotPassword: _openForgotPassword,
                                  ),
                                  _RemoteFlow.forgotPassword =>
                                    _ForgotPasswordPanel(
                                      submitting: _submitting,
                                      emailSent: _resetEmailSent,
                                      sentToEmail: _pendingEmail,
                                      formKey: _forgotFormKey,
                                      emailController: _emailController,
                                      onSubmit: _submitForgotPassword,
                                      onBack: _returnToSignIn,
                                    ),
                                  _RemoteFlow.verifyPending =>
                                    _VerifyEmailPendingPanel(
                                      submitting: _submitting,
                                      email: _pendingEmail,
                                      resendCooldown: _resendCooldown,
                                      onResend: _resendVerification,
                                      onSignIn: _returnToSignIn,
                                    ),
                                },
                              ),
                              local: _LocalLoginPanel(
                                submitting: _submitting,
                                formKey: _localFormKey,
                                nameController: _localNameController,
                                onSubmit: _submitLocal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (widget.canDismiss)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      tooltip: context.l10n.close,
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // No clip and no drop shadow: the artwork already carries its
            // own rounded silhouette, and its transparent margins mean a
            // shadow would trace the 56px box instead of the icon — reading
            // as a dark rectangle behind it. Web's `AuthHeroHeader` matches.
            SizedBox(
              width: 56,
              height: 56,
              child: Image.asset(
                'assets/icon/icon-android.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.appTitle,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 0.96,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.loginIntro,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PathPicker extends StatelessWidget {
  const _PathPicker({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final _LoginPath selected;
  final bool enabled;
  final ValueChanged<_LoginPath> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          children: [
            Expanded(
              child: _PathSegment(
                icon: Icons.cloud_done_rounded,
                label: context.l10n.withAccount,
                selected: selected == _LoginPath.remote,
                enabled: enabled,
                onTap: () => onChanged(_LoginPath.remote),
              ),
            ),
            Expanded(
              child: _PathSegment(
                icon: Icons.phone_iphone_rounded,
                label: context.l10n.withoutAccount,
                selected: selected == _LoginPath.local,
                enabled: enabled,
                onTap: () => onChanged(_LoginPath.local),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PathSegment extends StatelessWidget {
  const _PathSegment({
    required this.icon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      height: 48,
      decoration: BoxDecoration(
        color: selected ? colors.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: colors.shadow.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: enabled ? onTap : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: selected ? colors.primary : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected ? colors.onSurface : colors.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthPathSwitcher extends StatelessWidget {
  const _AuthPathSwitcher({
    required this.path,
    required this.remote,
    required this.local,
  });

  final _LoginPath path;
  final Widget remote;
  final Widget local;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: KeyedSubtree(
        key: ValueKey(path),
        child: path == _LoginPath.remote ? remote : local,
      ),
    );
  }
}

class _RemoteLoginPanel extends StatelessWidget {
  const _RemoteLoginPanel({
    required this.mode,
    required this.submitting,
    required this.formKey,
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.ageConfirmed,
    required this.acceptedLegal,
    required this.onAgeConfirmedChanged,
    required this.onAcceptedLegalChanged,
    required this.onModeChanged,
    required this.onSubmit,
    required this.onApple,
    required this.onGoogle,
    required this.onForgotPassword,
  });

  final _EmailAuthMode mode;
  final bool submitting;
  final GlobalKey<FormState> formKey;
  final bool ageConfirmed;
  final bool acceptedLegal;
  final ValueChanged<bool> onAgeConfirmedChanged;
  final ValueChanged<bool> onAcceptedLegalChanged;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final ValueChanged<_EmailAuthMode> onModeChanged;
  final VoidCallback onSubmit;

  /// Null off iOS: Sign in with Apple is wired for the native Apple sheet
  /// only, and an Android build would need a Services ID and a browser round
  /// trip that nothing here sets up.
  final VoidCallback? onApple;
  final VoidCallback onGoogle;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return AuthPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthPanelTitle(
            icon: Icons.sync_rounded,
            title: context.l10n.withAccount,
            subtitle: context.l10n.withAccountDescription,
          ),
          const SizedBox(height: 18),
          Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: mode == _EmailAuthMode.signUp
                      ? Padding(
                          key: const ValueKey('remote-name'),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _LoginTextField(
                            controller: nameController,
                            enabled: !submitting,
                            label: context.l10n.name,
                            icon: Icons.badge_outlined,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty) {
                                return context.l10n.enterYourName;
                              }
                              return null;
                            },
                          ),
                        )
                      : const SizedBox.shrink(key: ValueKey('no-remote-name')),
                ),
                _LoginTextField(
                  controller: emailController,
                  enabled: !submitting,
                  label: context.l10n.email,
                  icon: Icons.alternate_email_rounded,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) return context.l10n.enterEmail;
                    if (!email.contains('@')) {
                      return context.l10n.enterValidEmail;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                _LoginTextField(
                  controller: passwordController,
                  enabled: !submitting,
                  label: context.l10n.password,
                  icon: Icons.lock_outline_rounded,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: [
                    mode == _EmailAuthMode.signIn
                        ? AutofillHints.password
                        : AutofillHints.newPassword,
                  ],
                  onSubmitted: (_) => onSubmit(),
                  validator: (value) {
                    final password = value ?? '';
                    if (password.isEmpty) return context.l10n.enterPassword;
                    if (password.length < 8) {
                      return context.l10n.passwordMinLength;
                    }
                    return null;
                  },
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: mode == _EmailAuthMode.signIn
                      ? Align(
                          key: const ValueKey('forgot-password'),
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: submitting ? null : onForgotPassword,
                            child: Text(context.l10n.forgotPassword),
                          ),
                        )
                      : const SizedBox(
                          key: ValueKey('no-forgot-password'),
                          height: 16,
                        ),
                ),
                if (mode == _EmailAuthMode.signUp) ...[
                  LegalConsentChecks(
                    documents: LegalDocumentKind.values,
                    ageConfirmed: ageConfirmed,
                    accepted: acceptedLegal,
                    enabled: !submitting,
                    onAgeConfirmedChanged: onAgeConfirmedChanged,
                    onAcceptedChanged: onAcceptedLegalChanged,
                  ),
                  const SizedBox(height: 10),
                ],
                AuthPrimaryActionButton(
                  submitting: submitting,
                  label: mode.primaryButtonLabel(context.l10n),
                  // Dead until both boxes are ticked on sign-up; a spinner
                  // would claim work is in flight that never started.
                  onPressed:
                      mode == _EmailAuthMode.signUp &&
                          !(ageConfirmed && acceptedLegal)
                      ? null
                      : onSubmit,
                ),
                const SizedBox(height: 10),
                Center(
                  child: _EmailModeToggleButton(
                    mode: mode,
                    enabled: !submitting,
                    onChanged: onModeChanged,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: Divider(color: colors.outlineVariant)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  context.l10n.or,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(child: Divider(color: colors.outlineVariant)),
            ],
          ),
          const SizedBox(height: 18),
          // Apple first: guideline 4.8 wants Sign in with Apple no less
          // prominent than the other third-party options on the screen.
          if (onApple != null) ...[
            _SocialSignInButton(
              onPressed: submitting ? null : onApple,
              // The Apple mark is a solid glyph with no colour of its own, so
              // it takes the button's foreground the way a text label does.
              icon: SvgPicture.asset(
                'assets/apple.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(
                  colors.onSurface,
                  BlendMode.srcIn,
                ),
              ),
              label: context.l10n.continueWithApple,
            ),
            const SizedBox(height: 12),
          ],
          _SocialSignInButton(
            onPressed: submitting ? null : onGoogle,
            icon: SvgPicture.asset(
              'assets/google.svg',
              width: 20,
              height: 20,
            ),
            label: context.l10n.continueWithGoogle,
          ),
        ],
      ),
    );
  }
}

/// One identity provider, styled the same for every provider so none reads as
/// the preferred one.
class _SocialSignInButton extends StatelessWidget {
  const _SocialSignInButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 54,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: colors.surface,
          side: BorderSide(color: colors.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: icon,
        label: Text(label),
      ),
    );
  }
}

class _LocalLoginPanel extends StatelessWidget {
  const _LocalLoginPanel({
    required this.submitting,
    required this.formKey,
    required this.nameController,
    required this.onSubmit,
  });

  final bool submitting;
  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return AuthPanel(
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthPanelTitle(
              icon: Icons.phone_iphone_rounded,
              title: context.l10n.withoutAccount,
              subtitle: context.l10n.localAccountDescription,
            ),
            const SizedBox(height: 18),
            _LoginTextField(
              controller: nameController,
              enabled: !submitting,
              label: context.l10n.name,
              icon: Icons.drive_file_rename_outline_rounded,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.name],
              onSubmitted: (_) => onSubmit(),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return context.l10n.enterName;
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            AuthPrimaryActionButton(
              submitting: submitting,
              label: context.l10n.continueLocally,
              onPressed: onSubmit,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmailModeToggleButton extends StatelessWidget {
  const _EmailModeToggleButton({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final _EmailAuthMode mode;
  final bool enabled;
  final ValueChanged<_EmailAuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final targetMode = mode == _EmailAuthMode.signIn
        ? _EmailAuthMode.signUp
        : _EmailAuthMode.signIn;
    final label = mode == _EmailAuthMode.signIn
        ? context.l10n.needAccountSignUp
        : context.l10n.haveAccountSignIn;

    return TextButton(
      onPressed: enabled ? () => onChanged(targetMode) : null,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label),
    );
  }
}

class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    required this.controller,
    required this.enabled,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.obscureText = false,
    this.onSubmitted,
    this.validator,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      obscureText: obscureText,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.66),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colors.error, width: 1.4),
        ),
      ),
    );
  }
}

extension on _EmailAuthMode {
  String primaryButtonLabel(AppLocalizations l10n) {
    return switch (this) {
      _EmailAuthMode.signIn => l10n.signIn,
      _EmailAuthMode.signUp => l10n.signUp,
    };
  }

  String actionLabel(AppLocalizations l10n) {
    return switch (this) {
      _EmailAuthMode.signIn => l10n.signInAction,
      _EmailAuthMode.signUp => l10n.signUpAction,
    };
  }
}
