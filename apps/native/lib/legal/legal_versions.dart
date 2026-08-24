import 'package:app/database.dart' show LegalDocumentKind;
import 'package:flutter/foundation.dart';

/// Current/minimum accepted version of one legal document.
@immutable
class LegalDocumentVersions {
  const LegalDocumentVersions({required this.current, required this.min});

  /// What a fresh acceptance records, and what the user is asked for.
  final String current;

  /// The floor that still grants access. Accepting anything `>= min` keeps the
  /// app usable (the grace period) and only earns a dismissible nudge.
  final String min;

  static LegalDocumentVersions? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final current = raw['current'];
    final min = raw['min'];
    if (current is! String || current.isEmpty) return null;
    if (min is! String || min.isEmpty) return null;
    return LegalDocumentVersions(current: current, min: min);
  }

  Map<String, Object?> toJson() => {'current': current, 'min': min};

  @override
  bool operator ==(Object other) =>
      other is LegalDocumentVersions &&
      other.current == current &&
      other.min == min;

  @override
  int get hashCode => Object.hash(current, min);
}

/// Versions of both legal documents.
///
/// The backend is authoritative and serves these on `/v1/config`
/// (`packages/backend/convex/config/helpers.ts`, from
/// `packages/shared/src/legal.ts`). [bundled] is the fail-open fallback for a
/// device that has never reached the endpoint — a local-only account gets no
/// authenticated call at all, so without a bundled copy its first run could
/// not ask for acceptance offline.
///
/// KEEP [bundled] IN LOCKSTEP with `LEGAL_VERSIONS` in
/// `packages/shared/src/legal.ts`. Same rule as `minSupportedVersion`: a
/// document change is a coordinated bump.
@immutable
class LegalVersions {
  const LegalVersions({required this.terms, required this.privacy});

  final LegalDocumentVersions terms;
  final LegalDocumentVersions privacy;

  static const LegalVersions bundled = LegalVersions(
    terms: LegalDocumentVersions(current: '2026-08-23', min: '2026-08-23'),
    privacy: LegalDocumentVersions(current: '2026-08-23', min: '2026-08-23'),
  );

  LegalDocumentVersions of(LegalDocumentKind document) =>
      switch (document) {
        LegalDocumentKind.terms => terms,
        LegalDocumentKind.privacy => privacy,
      };

  /// Parses the `legal` block of a config verdict. Returns null unless BOTH
  /// documents parse — a half-read block would silently mix a server version
  /// with a bundled one.
  static LegalVersions? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final terms = LegalDocumentVersions.fromJson(raw['terms']);
    final privacy = LegalDocumentVersions.fromJson(raw['privacy']);
    if (terms == null || privacy == null) return null;
    return LegalVersions(terms: terms, privacy: privacy);
  }

  Map<String, Object?> toJson() => {
    'terms': terms.toJson(),
    'privacy': privacy.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is LegalVersions &&
      other.terms == terms &&
      other.privacy == privacy;

  @override
  int get hashCode => Object.hash(terms, privacy);
}

/// Lexicographic comparison — versions are ordered strings (`2026-08-06`,
/// optionally suffixed), never semver. `compareVersions`-style parsing would
/// read `2026-08-06` as major 2026 and throw the rest away.
bool isLegalVersionAtLeast(String version, String floor) =>
    version.compareTo(floor) >= 0;

/// What the user still owes for one document.
enum LegalDocumentAcceptanceStatus {
  /// Accepted [LegalDocumentVersions.current] or newer: nothing to ask.
  current,

  /// Accepted at least the floor but not the current text: dismissible nudge.
  outdated,

  /// Never accepted, or only below the floor: blocking.
  missing,
}

LegalDocumentAcceptanceStatus legalDocumentAcceptanceStatus({
  required LegalDocumentVersions versions,
  required String? accepted,
}) {
  if (accepted == null) return LegalDocumentAcceptanceStatus.missing;
  if (isLegalVersionAtLeast(accepted, versions.current)) {
    return LegalDocumentAcceptanceStatus.current;
  }
  return isLegalVersionAtLeast(accepted, versions.min)
      ? LegalDocumentAcceptanceStatus.outdated
      : LegalDocumentAcceptanceStatus.missing;
}

const String _legalSiteUrl = 'https://www.walletbot.live';

/// Public URL of a document, as routed by `apps/landing`
/// (`src/pages/{en,es}/{privacy,terms}.astro`), in the app's active language.
String legalDocumentUrl(LegalDocumentKind document, String localeTag) {
  final locale =
      localeTag.trim().toLowerCase().replaceAll('_', '-').startsWith('es')
      ? 'es'
      : 'en';
  final page = document == LegalDocumentKind.terms ? 'terms' : 'privacy';
  return '$_legalSiteUrl/$locale/$page';
}
