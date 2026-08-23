import 'package:flutter/material.dart';

/// The frame the auth-adjacent screens share: the painted backdrop, the
/// translucent panel, its title row and its 54px primary action.
///
/// Extracted verbatim from `login.dart`, where they were private, so the
/// Terms/Privacy acceptance gate is the same surface as signing in instead of
/// a second look-alike. `apps/web/src/components/auth/auth-scaffold.tsx` is
/// the web counterpart.

/// The gridded, gradient-washed backdrop behind every auth screen.
class AuthBackdrop extends StatelessWidget {
  const AuthBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AuthBackdropPainter(Theme.of(context).colorScheme),
    );
  }
}

class _AuthBackdropPainter extends CustomPainter {
  const _AuthBackdropPainter(this.colors);

  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    final base = Paint()..color = colors.surface;
    canvas.drawRect(Offset.zero & size, base);

    final gridPaint = Paint()
      ..color = colors.outlineVariant.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    const step = 34.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final accentA = Paint()
      ..shader =
          RadialGradient(
            colors: [
              colors.tertiaryContainer.withValues(alpha: 0.72),
              colors.tertiaryContainer.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.12, size.height * 0.14),
              radius: size.shortestSide * 0.46,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.12, size.height * 0.14),
      size.shortestSide * 0.46,
      accentA,
    );

    final accentB = Paint()
      ..shader =
          RadialGradient(
            colors: [
              colors.secondaryContainer.withValues(alpha: 0.64),
              colors.secondaryContainer.withValues(alpha: 0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.92, size.height * 0.76),
              radius: size.shortestSide * 0.5,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.92, size.height * 0.76),
      size.shortestSide * 0.5,
      accentB,
    );

    final ribbon = Paint()
      ..color = colors.primary.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18;
    final path = Path()
      ..moveTo(-40, size.height * 0.68)
      ..quadraticBezierTo(
        size.width * 0.32,
        size.height * 0.53,
        size.width * 0.66,
        size.height * 0.64,
      )
      ..quadraticBezierTo(
        size.width * 0.86,
        size.height * 0.71,
        size.width + 40,
        size.height * 0.56,
      );
    canvas.drawPath(path, ribbon);
  }

  @override
  bool shouldRepaint(covariant _AuthBackdropPainter oldDelegate) {
    return oldDelegate.colors != colors;
  }
}

/// The translucent card the auth flows live in.
class AuthPanel extends StatelessWidget {
  const AuthPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.1),
            blurRadius: 30,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}

/// A panel's leading icon tile + headline + one-line subtitle.
class AuthPanelTitle extends StatelessWidget {
  const AuthPanelTitle({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: colors.onPrimaryContainer, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
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
    );
  }
}

/// The 54px, 16dp-shaped primary action the auth panels use instead of the
/// default M3 pill. [onPressed] null and [submitting] are different states: an
/// unmet precondition stays a dead button, not a spinner.
class AuthPrimaryActionButton extends StatelessWidget {
  const AuthPrimaryActionButton({
    super.key,
    required this.submitting,
    required this.label,
    required this.onPressed,
  });

  final bool submitting;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton(
        onPressed: submitting ? null : onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: submitting
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }
}
