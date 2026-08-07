import 'package:flutter/material.dart';

/// Shared surface + elevation tokens for the app's raised "card" surfaces
/// (transaction rows, the transaction detail receipt). Keeping them here means
/// the list and the detail view read with the same contrast and lift.
///
/// Light mode leans on the drop shadow to separate the card from the page, so
/// the fill stays on the near-white `surface`. Dark mode can't rely on shadows
/// the same way — a black shadow barely reads against a dark scaffold — so it
/// lifts the fill to `surfaceContainer` for contrast *and* uses a higher
/// elevation so the (still subtle) shadow around the lighter fill is enough to
/// convey the lift.

/// Fill color for a raised card.
Color raisedCardColor(ColorScheme colors, Brightness brightness) =>
    brightness == Brightness.dark ? colors.surfaceContainer : colors.surface;

/// Elevation for a raised card. Dark mode uses a higher value so the lift is
/// still perceptible against the dark scaffold background.
double raisedCardElevation(Brightness brightness) =>
    brightness == Brightness.dark ? 3 : 1;
