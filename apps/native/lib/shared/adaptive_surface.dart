import 'dart:math' as math;

import 'package:app/shared/breakpoints.dart';
import 'package:flutter/material.dart';

/// How a surface presented with [presentSurface] is framed on screen.
enum SurfaceStyle { bottomSheet, sideSheet, centeredDialog, fullscreen }

/// Presents [builder] in an [AdaptiveSurfaceRoute]: framed as [compact] below
/// the medium breakpoint and as [wide] at or above it. The route re-frames
/// itself in place when the window is resized across the breakpoint — the
/// content keeps its element position (and therefore its State) through the
/// morph.
///
/// Like `showModalBottomSheet`, the builder runs under the navigator, so
/// providers scoped below it (e.g. the account-scoped repositories) are not
/// reachable from the builder's context — pass them in explicitly.
Future<T?> presentSurface<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  SurfaceStyle compact = SurfaceStyle.bottomSheet,
  SurfaceStyle wide = SurfaceStyle.sideSheet,
  bool isDismissible = true,
  bool useRootNavigator = false,
  Color? backgroundColor,
}) {
  return Navigator.of(context, rootNavigator: useRootNavigator).push(
    AdaptiveSurfaceRoute<T>(
      builder: builder,
      compactStyle: compact,
      wideStyle: wide,
      isDismissible: isDismissible,
      backgroundColor: backgroundColor,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// Exposes the [SurfaceStyle] the enclosing [AdaptiveSurfaceRoute] is
/// currently rendering, so content can adapt its scaffolding (e.g. use a
/// [DraggableScrollableSheet] only when framed as a bottom sheet).
class AdaptiveSurfaceScope extends InheritedWidget {
  const AdaptiveSurfaceScope({
    super.key,
    required this.style,
    required super.child,
  });

  final SurfaceStyle style;

  static SurfaceStyle? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdaptiveSurfaceScope>()?.style;

  @override
  bool updateShouldNotify(AdaptiveSurfaceScope oldWidget) =>
      oldWidget.style != style;
}

/// A modal route that frames its content per the current window size class
/// and re-frames live on resize.
///
/// State preservation relies on two invariants — keep them if you edit this:
/// - [buildPage] must produce the same widget-type chain for every style
///   (only constraint/alignment/shape *values* may differ), so the content's
///   element never moves when the style changes.
/// - [buildTransitions] must likewise keep one widget-type chain; per-style
///   variation goes in the tweens, never in the wrapper types. Swapping a
///   wrapper type re-inflates the page subtree and destroys its State.
class AdaptiveSurfaceRoute<T> extends PopupRoute<T> {
  AdaptiveSurfaceRoute({
    required this.builder,
    required this.compactStyle,
    required this.wideStyle,
    required String barrierLabel,
    this.backgroundColor,
    bool isDismissible = true,
  }) : _barrierLabel = barrierLabel,
       _dismissible = isDismissible;

  final WidgetBuilder builder;
  final SurfaceStyle compactStyle;
  final SurfaceStyle wideStyle;
  final Color? backgroundColor;
  final String _barrierLabel;
  final bool _dismissible;

  static const double _sideSheetWidth = 400;
  static const double _dialogMaxWidth = 560;

  @override
  Color? get barrierColor => Colors.black54;

  @override
  bool get barrierDismissible => _dismissible;

  @override
  String? get barrierLabel => _barrierLabel;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  SurfaceStyle _styleOf(BuildContext context) =>
      windowSizeClassOf(context) == WindowSizeClass.compact
      ? compactStyle
      : wideStyle;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final style = _styleOf(context);
    final size = MediaQuery.sizeOf(context);
    final colors = Theme.of(context).colorScheme;

    final Alignment alignment;
    final BoxConstraints constraints;
    final ShapeBorder shape;
    var safeTop = true;
    var safeBottom = false;
    var safeSides = false;

    switch (style) {
      case SurfaceStyle.bottomSheet:
        alignment = Alignment.bottomCenter;
        // Tight infinite width clamps to the parent's max: full-bleed width,
        // content-driven height.
        constraints = const BoxConstraints.tightFor(width: double.infinity);
        shape = const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        );
      case SurfaceStyle.sideSheet:
        alignment = Alignment.centerRight;
        constraints = BoxConstraints.tightFor(
          width: math.min(_sideSheetWidth, size.width * 0.9),
          height: double.infinity,
        );
        shape = const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(left: Radius.circular(16)),
        );
        safeBottom = true;
        safeSides = true;
      case SurfaceStyle.centeredDialog:
        alignment = Alignment.center;
        constraints = BoxConstraints(
          maxWidth: _dialogMaxWidth,
          maxHeight: size.height * 0.85,
        );
        shape = const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
        );
        safeBottom = true;
        safeSides = true;
      case SurfaceStyle.fullscreen:
        alignment = Alignment.center;
        constraints = const BoxConstraints.tightFor(
          width: double.infinity,
          height: double.infinity,
        );
        shape = const RoundedRectangleBorder();
        // Fullscreen content owns its own SafeArea, like a normal route.
        safeTop = false;
    }

    return SafeArea(
      top: safeTop,
      bottom: safeBottom,
      left: safeSides,
      right: safeSides,
      child: Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: constraints,
          child: Material(
            color: backgroundColor ?? colors.surface,
            elevation: 1,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: AdaptiveSurfaceScope(
              style: style,
              child: Builder(builder: builder),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final style = _styleOf(context);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final Tween<Offset> offset;
    Animatable<double> fade = ConstantTween(1.0);
    Animatable<double> scale = ConstantTween(1.0);
    switch (style) {
      case SurfaceStyle.bottomSheet:
      case SurfaceStyle.fullscreen:
        offset = Tween(begin: const Offset(0, 1), end: Offset.zero);
      case SurfaceStyle.sideSheet:
        offset = Tween(begin: const Offset(1, 0), end: Offset.zero);
      case SurfaceStyle.centeredDialog:
        offset = Tween(begin: Offset.zero, end: Offset.zero);
        fade = Tween(begin: 0.0, end: 1.0);
        scale = Tween(begin: 0.95, end: 1.0);
    }

    return FadeTransition(
      opacity: curved.drive(fade),
      child: ScaleTransition(
        scale: curved.drive(scale),
        child: SlideTransition(position: curved.drive(offset), child: child),
      ),
    );
  }
}
