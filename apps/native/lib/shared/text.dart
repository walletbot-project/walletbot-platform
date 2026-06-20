/// Text helpers shared by the data layer and the agent tool layer.
library;

/// Normalization used for name-based entity resolution. Mirrored from
/// packages/shared/src/tools/parsing.ts — keep in sync with the TS version.
String normalizeName(String value) => value.trim().toLowerCase();
