import 'dart:async';

import 'package:app/shared/breakpoints.dart';
import 'package:flutter/material.dart';

/// Divided-view host implementing the app's large-screen pattern (see the
/// Activity screen, where the choreography originated, and
/// `test/shared/route_pane_handoff_test.dart` / the host's own test for the
/// mechanism proofs).
///
/// - **Small windows: nothing changes.** [list] renders exactly as it always
///   has, and the detail is presented as a REAL modal bottom sheet route —
///   constructed precisely the way `showModalBottomSheet(isScrollControlled:
///   true, showDragHandle: true)` does it, so transition, scrim, drag
///   behavior, back handling, and semantics are the platform's own.
/// - **Expanded windows: the divided view.** The list takes the left half of
///   the window, a full-height divider, and the detail renders inline in the
///   right half. Never an overlay on top.
/// - **Resizes are seamless and state-preserving in both directions.** The
///   detail widget must carry a GlobalKey (owned by the caller, stable per
///   selection); the host guarantees the keyed widget is inflated somewhere
///   in every frame — pane, offstage bridge, or sheet — so the Element
///   reparents within a frame and its State (mid-edit fields included)
///   survives every handoff.
class AdaptiveDetailView extends StatefulWidget {
  const AdaptiveDetailView({
    super.key,
    required this.list,
    required this.hasDetail,
    required this.detailBuilder,
    required this.onSheetDismissed,
    required this.placeholder,
    required this.isActiveTab,
  });

  /// The always-visible view, exactly as it renders on small windows today
  /// (its own Scaffold/app bar included). On expanded windows the same
  /// widget becomes the left half of the divided view.
  final Widget list;

  /// Whether a detail is currently selected. Must agree with
  /// [detailBuilder] returning non-null.
  final bool hasDetail;

  /// Builds the current detail, or null when nothing is selected. The
  /// returned widget MUST have a GlobalKey that is stable for a given
  /// selection and fresh for a new one. [inSheet] is true when the detail is
  /// framed as a modal bottom sheet (keep the drag-to-size scaffolding and
  /// self-popping) and false when embedded in the split pane (plain panel,
  /// exits via callback).
  final Widget? Function(BuildContext context, {required bool inSheet})
  detailBuilder;

  /// Called when the modal sheet is dismissed by the user (drag, scrim tap,
  /// back, or a self-pop). Clear the selection here.
  final VoidCallback onSheetDismissed;

  /// Shown in the right pane when nothing is selected.
  final Widget placeholder;

  /// Whether this view is the one the user is looking at. Gates the
  /// bridge-frame back-button safety net so a hidden tab never swallows the
  /// back button.
  final bool isActiveTab;

  @override
  State<AdaptiveDetailView> createState() => _AdaptiveDetailViewState();
}

class _AdaptiveDetailViewState extends State<AdaptiveDetailView> {
  /// The live sheet route, when the detail is presented as one. Nulled
  /// BEFORE a programmatic removal so the completion handler can tell a user
  /// dismissal (report it) from a resize handoff (keep the selection).
  ModalBottomSheetRoute<void>? _sheetRoute;

  /// Set when [AdaptiveDetailView.hasDetail] flips on while the window is
  /// small: the upcoming sheet is a user-initiated open and must play the
  /// normal entrance animation. Resize handoffs present instantly instead.
  bool _openIsUserInitiated = false;

  bool get _split => windowSizeClassOf(context) == WindowSizeClass.expanded;

  @override
  void didUpdateWidget(AdaptiveDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.hasDetail && widget.hasDetail && !_split) {
      _openIsUserInitiated = true;
    }
  }

  /// Presents the detail as a real modal bottom sheet route — the exact
  /// construction `showModalBottomSheet` performs. [instant] zeroes only the
  /// entrance (used when the sheet takes over from the pane on shrink);
  /// dismissal always plays the standard exit animation.
  void _pushSheet({required bool instant}) {
    final navigator = Navigator.of(context);
    final localizations = MaterialLocalizations.of(context);
    final route = ModalBottomSheetRoute<void>(
      builder: (sheetContext) =>
          widget.detailBuilder(sheetContext, inSheet: true) ??
          const SizedBox.shrink(),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: true,
      showDragHandle: true,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      modalBarrierColor: Theme.of(context).bottomSheetTheme.modalBarrierColor,
      sheetAnimationStyle: instant
          ? const AnimationStyle(duration: Duration.zero)
          : null,
    );
    _sheetRoute = route;
    unawaited(
      navigator.push(route).then((_) {
        // Only a USER dismissal reaches here with the route still owned — a
        // resize handoff nulls _sheetRoute first.
        if (!mounted || !identical(_sheetRoute, route)) return;
        _sheetRoute = null;
        widget.onSheetDismissed();
        setState(() {});
      }),
    );
    // Rebuild so the offstage bridge (if up) is dropped in the same frame
    // the sheet claims the GlobalKey — the Element moves, State intact.
    setState(() {});
  }

  /// Keeps the sheet route in sync with (window class × selection).
  /// Idempotent; runs post-frame, scheduled by build on mismatch.
  void _reconcileSheet() {
    if (!mounted) return;
    final needsSheet = !_split && widget.hasDetail;
    final route = _sheetRoute;
    if (needsSheet && route == null) {
      _pushSheet(instant: !_openIsUserInitiated);
      _openIsUserInitiated = false;
    } else if (!needsSheet && route != null) {
      // Null first: the completion handler must treat this as a handoff (or
      // a cleared selection), not a user dismissal.
      _sheetRoute = null;
      Navigator.of(context).removeRoute(route);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final split = _split;
    final needsSheet = !split && widget.hasDetail;
    if (needsSheet != (_sheetRoute != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reconcileSheet());
    }

    if (split) {
      // The pane may only claim the GlobalKey once the sheet has released
      // it: in the frame right after a grow — before the post-frame handoff
      // removes the sheet — inflating it here would steal the Element out of
      // the still-visible sheet. The sheet covers that frame, so the
      // placeholder is never actually seen.
      final detail = _sheetRoute == null
          ? widget.detailBuilder(context, inSheet: false)
          : null;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              Expanded(child: widget.list),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(child: detail ?? widget.placeholder),
            ],
          ),
        ),
      );
    }

    // Small windows: the view renders exactly as it always has. The offstage
    // bridge exists only during handoff frames — after a shrink (or a fresh
    // selection), before the sheet route claims the GlobalKey — so the
    // detail is built somewhere in every frame and its State survives. It
    // paints nothing.
    final bridge = widget.hasDetail && _sheetRoute == null
        ? widget.detailBuilder(context, inSheet: true)
        : null;
    final body = Stack(
      fit: StackFit.expand,
      children: [
        widget.list,
        if (bridge != null) Positioned.fill(child: Offstage(child: bridge)),
      ],
    );

    // The sheet handles back natively. This safety net covers only the
    // transient bridge frames, and only while this view is visible: back
    // then closes the detail instead of leaving the app.
    final interceptPop = bridge != null && widget.isActiveTab;
    return PopScope(
      canPop: !interceptPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onSheetDismissed();
      },
      child: body,
    );
  }
}
