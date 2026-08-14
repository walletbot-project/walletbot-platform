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
/// A [MaterialPageRoute] that appears instantly but pops with the standard
/// platform animation. Used when a full-screen route takes over already
/// on-screen content during a resize handoff — an entrance animation would
/// read as a glitch — while a user-initiated back must still play the normal
/// transition.
class InstantEntranceMaterialPageRoute<T> extends MaterialPageRoute<T> {
  InstantEntranceMaterialPageRoute({required super.builder});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);
}

class AdaptiveDetailView extends StatefulWidget {
  const AdaptiveDetailView({
    super.key,
    required this.list,
    required this.hasDetail,
    required this.detailBuilder,
    required this.onSheetDismissed,
    required this.placeholder,
    required this.isActiveTab,
    this.hasForm = false,
    this.formBuilder,
    this.onFormDismissed,
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

  /// Whether a creation/edit form is open. The form occupies the same pane
  /// as the detail on expanded windows and is presented as a REAL full-screen
  /// [MaterialPageRoute] on smaller ones, with the same state-preserving
  /// resize handoffs. The pane hosts one occupant at a time: callers must
  /// clear the detail selection when opening the form and vice versa; when
  /// both are set the form wins.
  final bool hasForm;

  /// Builds the current form, or null when none is open. Same GlobalKey
  /// contract as [detailBuilder]. [inRoute] is true when the form is framed
  /// as its own pushed route (keep the original self-popping exits and any
  /// provider re-wrapping the route needs) and false when rendered inline
  /// (pane or handoff bridge — exits must go through callbacks).
  final Widget? Function(BuildContext context, {required bool inRoute})?
  formBuilder;

  /// Called when the form route is closed by the user (back, or a self-pop
  /// on save/cancel). Clear the form state here.
  final VoidCallback? onFormDismissed;

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

  /// The live form route, when the form is presented as one. Same ownership
  /// protocol as [_sheetRoute].
  MaterialPageRoute<void>? _formRoute;

  /// Same as [_openIsUserInitiated], for the form. While pending it also
  /// suppresses the form bridge: a fresh open has no State to preserve, and
  /// skipping the bridge lets the route play its normal entrance animation
  /// over the list, exactly like the original push.
  bool _formOpenIsUserInitiated = false;

  bool get _split => windowSizeClassOf(context) == WindowSizeClass.expanded;

  @override
  void didUpdateWidget(AdaptiveDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.hasDetail && widget.hasDetail && !_split) {
      _openIsUserInitiated = true;
    }
    if (!oldWidget.hasForm && widget.hasForm && !_split) {
      _formOpenIsUserInitiated = true;
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
    final userInitiated = _openIsUserInitiated;
    _openIsUserInitiated = false; // consumed, whatever the decision
    if (needsSheet && route == null) {
      _pushSheet(instant: !userInitiated);
    } else if (!needsSheet && route != null) {
      // Null first: the completion handler must treat this as a handoff (or
      // a cleared selection), not a user dismissal.
      _sheetRoute = null;
      Navigator.of(context).removeRoute(route);
      setState(() {});
    }
  }

  /// Presents the form as a real full-screen route: normal entrance for user
  /// opens, instant when taking over from the pane on shrink. Exits always
  /// animate normally.
  void _pushFormRoute({required bool instant}) {
    Widget buildPage(BuildContext routeContext) =>
        widget.formBuilder?.call(routeContext, inRoute: true) ??
        const SizedBox.shrink();
    final route = instant
        ? InstantEntranceMaterialPageRoute<void>(builder: buildPage)
        : MaterialPageRoute<void>(builder: buildPage);
    _formRoute = route;
    unawaited(
      Navigator.of(context).push(route).then((_) {
        // Only a USER exit (back, or the form popping itself on save/cancel)
        // reaches here with the route still owned.
        if (!mounted || !identical(_formRoute, route)) return;
        _formRoute = null;
        widget.onFormDismissed?.call();
        setState(() {});
      }),
    );
    setState(() {});
  }

  /// Keeps the form route in sync with (window class × form-open), like
  /// [_reconcileSheet] does for the detail sheet.
  void _reconcileForm() {
    if (!mounted) return;
    final needsForm = !_split && widget.hasForm;
    final route = _formRoute;
    final userInitiated = _formOpenIsUserInitiated;
    _formOpenIsUserInitiated = false; // consumed, whatever the decision
    if (needsForm && route == null) {
      _pushFormRoute(instant: !userInitiated);
    } else if (!needsForm && route != null) {
      _formRoute = null;
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
    final needsForm = !split && widget.hasForm;
    if (needsForm != (_formRoute != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reconcileForm());
    }

    if (split) {
      // A pane occupant may only claim its GlobalKey once its route/sheet
      // has released it: in the frame right after a grow — before the
      // post-frame handoff removes it — inflating here would steal the
      // Element out of the still-visible route. That route covers the window
      // for that frame, so the fallback is never actually seen.
      final form = widget.hasForm && _formRoute == null
          ? widget.formBuilder?.call(context, inRoute: false)
          : null;
      final detail = _sheetRoute == null
          ? widget.detailBuilder(context, inSheet: false)
          : null;
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              Expanded(child: widget.list),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(child: form ?? detail ?? widget.placeholder),
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
    // The form's bridge is VISIBLE (it paints the same full-screen page its
    // route shows, so the handoff swap is invisible), and suppressed for
    // user-initiated opens: fresh forms have no State to preserve, and the
    // route then plays its normal entrance over the list, as always. Inline
    // config (inRoute: false) so exits stay callback-wired even mid-bridge.
    final formBridge =
        widget.hasForm && _formRoute == null && !_formOpenIsUserInitiated
        ? widget.formBuilder?.call(context, inRoute: false)
        : null;
    final body = Stack(
      fit: StackFit.expand,
      children: [
        widget.list,
        if (bridge != null) Positioned.fill(child: Offstage(child: bridge)),
        if (formBridge != null) Positioned.fill(child: formBridge),
      ],
    );

    // The routes handle back natively. This safety net covers only the
    // transient bridge frames, and only while this view is visible: back
    // then closes the bridged occupant instead of leaving the app.
    final interceptPop =
        (bridge != null || formBridge != null) && widget.isActiveTab;
    return PopScope(
      canPop: !interceptPop,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (formBridge != null) {
          widget.onFormDismissed?.call();
        } else {
          widget.onSheetDismissed();
        }
      },
      child: body,
    );
  }
}
