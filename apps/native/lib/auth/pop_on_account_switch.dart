import 'package:app/auth/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Pops its route as soon as the active account is no longer the one the
/// route was opened for (switch, sign-out, or a freshly added account). The
/// child often captures account-scoped objects at push time; once the account
/// changes those are disposed, so the route must not stay on screen.
///
/// Pass the account id that was active when the route was pushed. Use `null`
/// when the route was opened with no active account (e.g. the login screen
/// surfaced from the account switcher) so it pops once any account becomes
/// active.
class PopOnAccountSwitch extends StatelessWidget {
  const PopOnAccountSwitch({
    super.key,
    required this.accountId,
    required this.child,
  });

  final String? accountId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final activeId = context.watch<AuthController>().activeAccount?.id;
    if (activeId != accountId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        Navigator.of(context).pop();
      });
    }
    return child;
  }
}
