import 'dart:async';

import 'package:app/shared/breakpoints.dart';
import 'package:flutter/material.dart';

/// How a surface opened with [showAdaptiveModal] is currently framed.
enum AdaptiveModalStyle { bottomSheet, dialog }

/// Exposes the framing the enclosing [showAdaptiveModal] surface is currently
/// using, so content can adapt its own scaffolding — e.g. use a
/// [DraggableScrollableSheet] only when framed as a bottom sheet.
class AdaptiveModalScope extends InheritedWidget {
  const AdaptiveModalScope({
    super.key,
    required this.style,
    required super.child,
  });

  final AdaptiveModalStyle style;

  static AdaptiveModalStyle? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdaptiveModalScope>()?.style;

  @override
  bool updateShouldNotify(AdaptiveModalScope oldWidget) =>
      oldWidget.style != style;
}

/// A [DialogRoute] that appears instantly but leaves with the standard
/// animation. Used when the dialog takes over from another presentation on
/// resize: the content is already on screen, so an entrance animation would
/// read as a glitch, while a later user dismissal must still animate normally.
///
/// [DialogRoute] derives its reverse duration from [transitionDuration], so
/// zeroing the entrance via `animationStyle` alone would also zero the exit —
/// hence the explicit override. Mirrors [InstantEntranceMaterialPageRoute] in
/// `adaptive_detail_view.dart`.
class _InstantEntranceDialogRoute<T> extends DialogRoute<T> {
  _InstantEntranceDialogRoute({
    required super.context,
    required super.builder,
    super.themes,
  }) : super(animationStyle: const AnimationStyle(duration: Duration.zero));

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 150);
}

/// Builds the modal bottom sheet route exactly as `showModalBottomSheet` does.
///
/// Shared by [showAdaptiveModal] and `AdaptiveDetailView` so every adaptive
/// surface in the app presents the identical platform sheet — transition,
/// scrim, drag handle, drag-to-dismiss, back handling and semantics all the
/// framework's own, never re-implemented.
///
/// [instant] zeroes the entrance only (the reverse duration is a separate
/// fallback), for when the sheet takes over content already on screen.
ModalBottomSheetRoute<T> buildAdaptiveSheetRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  required CapturedThemes capturedThemes,
  required bool isScrollControlled,
  bool showDragHandle = false,
  bool useSafeArea = false,
  Color? backgroundColor,
  ShapeBorder? shape,
  bool instant = false,
}) {
  final localizations = MaterialLocalizations.of(context);
  return ModalBottomSheetRoute<T>(
    builder: builder,
    capturedThemes: capturedThemes,
    isScrollControlled: isScrollControlled,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    backgroundColor: backgroundColor,
    shape: shape,
    barrierLabel: localizations.scrimLabel,
    barrierOnTapHint: localizations.scrimOnTapHint(
      localizations.bottomSheetLabel,
    ),
    modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
    sheetAnimationStyle: instant
        ? const AnimationStyle(duration: Duration.zero)
        : null,
  );
}

/// Builds the dialog route exactly as `showDialog` does, with the content
/// capped by [maxWidth] / [maxHeightFactor] and inset by [padding].
///
/// [padding] stands in for the chrome the sheet framing supplies and the
/// dialog does not: sheet content sits below a drag handle and above the
/// bottom safe area, so it is routinely written with no vertical padding of
/// its own, and would otherwise render flush against the dialog's rounded
/// corners. Pass [EdgeInsets.zero] for content that frames itself — anything
/// with its own app bar, for instance.
DialogRoute<T> buildAdaptiveDialogRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  required CapturedThemes capturedThemes,
  Color? backgroundColor,
  double maxWidth = 560,
  double maxHeightFactor = 0.8,
  EdgeInsets padding = const EdgeInsets.symmetric(vertical: 16),
  bool instant = false,
}) {
  Widget buildDialog(BuildContext dialogContext) => Dialog(
    backgroundColor: backgroundColor,
    clipBehavior: Clip.antiAlias,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: MediaQuery.sizeOf(dialogContext).height * maxHeightFactor,
      ),
      child: Padding(
        padding: padding,
        child: Builder(builder: builder),
      ),
    ),
  );

  return instant
      ? _InstantEntranceDialogRoute<T>(
          context: context,
          builder: buildDialog,
          themes: capturedThemes,
        )
      : DialogRoute<T>(
          context: context,
          builder: buildDialog,
          themes: capturedThemes,
        );
}

/// Presents [builder] as a real modal bottom sheet on compact windows and as a
/// real dialog at [Breakpoints.medium] and above, swapping between the two
/// **live** when the window is resized across the breakpoint.
///
/// Both presentations are the platform's own routes (see
/// [buildAdaptiveSheetRoute] / [buildAdaptiveDialogRoute]), so mobile behaves
/// precisely as it did before a call site was migrated.
///
/// On resize the open route is removed and the other pushed in the same
/// post-frame callback; both mark the overlay dirty, so the removal and the
/// insertion land in one build pass. The content is pinned by a [GlobalKey],
/// so its Element reparents between the two routes and its State (mid-edit
/// text fields included) survives the swap.
///
/// Like `showModalBottomSheet`, the builder runs under the navigator, so
/// providers scoped below it (e.g. the account-scoped repositories) are not
/// reachable from the builder's context — pass them in explicitly.
///
/// [isScrollControlled], [showDragHandle], [useSafeArea] and [sheetShape]
/// apply to the bottom-sheet framing only and carry the same meaning they do
/// on `showModalBottomSheet`; [dialogMaxWidth], [dialogMaxHeightFactor] and
/// [dialogPadding] apply to the dialog framing only.
Future<T?> showAdaptiveModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = false,
  bool useSafeArea = false,
  Color? backgroundColor,
  ShapeBorder? sheetShape,
  double dialogMaxWidth = 560,
  double dialogMaxHeightFactor = 0.8,
  EdgeInsets dialogPadding = const EdgeInsets.symmetric(vertical: 16),
  bool useRootNavigator = false,
}) {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final overlay = navigator.overlay;
  if (overlay == null) {
    throw FlutterError(
      'showAdaptiveModal requires the target Navigator to have an Overlay.',
    );
  }
  // Captured from the CALLING context, exactly as showModalBottomSheet and
  // showDialog do, so a local Theme/Directionality override survives the hop
  // above the navigator. Captured once and reused by both routes, so the
  // wrapper chain is identical across a swap.
  final themes = InheritedTheme.capture(from: context, to: navigator.context);

  final completer = Completer<T?>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _AdaptiveModalHost<T>(
      navigator: navigator,
      themes: themes,
      builder: builder,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      useSafeArea: useSafeArea,
      backgroundColor: backgroundColor,
      sheetShape: sheetShape,
      dialogMaxWidth: dialogMaxWidth,
      dialogMaxHeightFactor: dialogMaxHeightFactor,
      dialogPadding: dialogPadding,
      onClosed: (result) {
        if (completer.isCompleted) return;
        completer.complete(result);
        if (entry.mounted) entry.remove();
      },
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

/// Owns the open modal's identity across presentations: which route is
/// currently up, and the [GlobalKey] that carries the content's State from one
/// route to the other. Lives in the navigator's overlay and paints nothing.
class _AdaptiveModalHost<T> extends StatefulWidget {
  const _AdaptiveModalHost({
    required this.navigator,
    required this.themes,
    required this.builder,
    required this.isScrollControlled,
    required this.showDragHandle,
    required this.useSafeArea,
    required this.backgroundColor,
    required this.sheetShape,
    required this.dialogMaxWidth,
    required this.dialogMaxHeightFactor,
    required this.dialogPadding,
    required this.onClosed,
  });

  final NavigatorState navigator;
  final CapturedThemes themes;
  final WidgetBuilder builder;
  final bool isScrollControlled;
  final bool showDragHandle;
  final bool useSafeArea;
  final Color? backgroundColor;
  final ShapeBorder? sheetShape;
  final double dialogMaxWidth;
  final double dialogMaxHeightFactor;
  final EdgeInsets dialogPadding;
  final ValueChanged<T?> onClosed;

  @override
  State<_AdaptiveModalHost<T>> createState() => _AdaptiveModalHostState<T>();
}

class _AdaptiveModalHostState<T> extends State<_AdaptiveModalHost<T>> {
  /// Pins the content's Element so its State survives the route swap. One key
  /// for the whole lifetime of the modal.
  final GlobalKey _contentKey = GlobalKey(debugLabel: 'adaptiveModal');

  /// The live route. Nulled BEFORE a programmatic removal, so the completion
  /// handler can tell a user dismissal (report it, close for good) from a
  /// resize swap (keep the modal open in its new framing).
  ModalRoute<T>? _route;
  AdaptiveModalStyle? _routeStyle;

  /// Set once the modal is on its way out, so a queued reconcile can never
  /// push a replacement after the user dismissed it.
  bool _closed = false;

  AdaptiveModalStyle get _style =>
      windowSizeClassOf(context) == WindowSizeClass.compact
      ? AdaptiveModalStyle.bottomSheet
      : AdaptiveModalStyle.dialog;

  Widget _content(AdaptiveModalStyle style) => AdaptiveModalScope(
    key: _contentKey,
    style: style,
    child: Builder(builder: widget.builder),
  );

  void _push(AdaptiveModalStyle style, {required bool instant}) {
    final route = switch (style) {
      AdaptiveModalStyle.bottomSheet => buildAdaptiveSheetRoute<T>(
        context,
        builder: (_) => _content(AdaptiveModalStyle.bottomSheet),
        capturedThemes: widget.themes,
        isScrollControlled: widget.isScrollControlled,
        showDragHandle: widget.showDragHandle,
        useSafeArea: widget.useSafeArea,
        backgroundColor: widget.backgroundColor,
        shape: widget.sheetShape,
        instant: instant,
      ),
      AdaptiveModalStyle.dialog => buildAdaptiveDialogRoute<T>(
        context,
        builder: (_) => _content(AdaptiveModalStyle.dialog),
        capturedThemes: widget.themes,
        backgroundColor: widget.backgroundColor,
        maxWidth: widget.dialogMaxWidth,
        maxHeightFactor: widget.dialogMaxHeightFactor,
        padding: widget.dialogPadding,
        instant: instant,
      ),
    };
    _route = route;
    _routeStyle = style;
    unawaited(
      widget.navigator.push(route).then((result) {
        // Only a USER dismissal reaches here with the route still owned — a
        // resize swap nulls _route before removing it.
        if (!mounted || !identical(_route, route)) return;
        _route = null;
        _closed = true;
        widget.onClosed(result);
      }),
    );
  }

  /// Keeps the live route in sync with the window size class. Idempotent; runs
  /// post-frame, scheduled by [build] on mismatch.
  ///
  /// The removal and the push land in the same callback on purpose: both mark
  /// the overlay dirty, so they resolve in one build pass and the content's
  /// Element reparents straight from the old route to the new one. Splitting
  /// them across frames would drop the scrim for a frame and force the content
  /// through an offstage bridge.
  void _reconcile() {
    if (!mounted || _closed) return;
    final style = _style;
    if (_route != null && _routeStyle == style) return;
    final previous = _route;
    // Null first: the completion handler must treat this as a swap, not a
    // user dismissal.
    _route = null;
    if (previous != null) widget.navigator.removeRoute(previous);
    _push(style, instant: previous != null);
  }

  @override
  Widget build(BuildContext context) {
    // Reads MediaQuery, so a resize across the breakpoint rebuilds the host
    // and schedules the swap.
    final style = _style;
    if (!_closed && (_route == null || _routeStyle != style)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reconcile());
    }
    // The routes own every pixel; the host exists only to hold the modal's
    // identity across them.
    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    // The overlay entry went away without a dismissal (e.g. the navigator was
    // torn down under us): release the awaiting caller rather than leaving its
    // future hanging. Reported off-frame because dispose runs mid-unmount and
    // the callback removes the overlay entry.
    if (!_closed) {
      _closed = true;
      final onClosed = widget.onClosed;
      _route = null;
      scheduleMicrotask(() => onClosed(null));
    }
    super.dispose();
  }
}
