import 'package:flutter/widgets.dart';

/// Material 3 window size classes. Compact is phone-sized; medium covers
/// small tablets and split-screen; expanded is large tablets and desktop.
enum WindowSizeClass { compact, medium, expanded }

/// Width thresholds (dp) between the window size classes. [expanded] gates
/// the divided (split) views, so it sits above the Material default (900) to
/// keep the single-column layout until there's comfortable room for two.
abstract final class Breakpoints {
  static const double medium = 600;
  static const double expanded = 1000;

  /// Window height (dp) below which the account, category and tag detail
  /// sheets open taller (see [detailSheetInitialSize]).
  static const double shortHeight = 760;
}

/// Initial size for the account, category and tag detail sheets. At 60% a
/// short window is filled by the header block alone, so the transactions list
/// below it starts out of view.
double detailSheetInitialSize(BuildContext context) =>
    MediaQuery.sizeOf(context).height < Breakpoints.shortHeight ? 0.85 : 0.6;

/// Resolves the window size class from the full window width. Registers a
/// MediaQuery dependency, so callers rebuild when the window is resized
/// across a breakpoint.
WindowSizeClass windowSizeClassOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= Breakpoints.expanded) return WindowSizeClass.expanded;
  if (width >= Breakpoints.medium) return WindowSizeClass.medium;
  return WindowSizeClass.compact;
}
