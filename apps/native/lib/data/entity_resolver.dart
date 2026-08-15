import 'package:drift/drift.dart';

import '../database.dart';
import '../shared/text.dart';

/// Outcome of resolving a user-supplied "id or name" reference.
sealed class ResolveResult<T> {
  const ResolveResult();
}

class Resolved<T> extends ResolveResult<T> {
  const Resolved(this.value);
  final T value;
}

class NotFound<T> extends ResolveResult<T> {
  const NotFound();
}

class Ambiguous<T> extends ResolveResult<T> {
  const Ambiguous(this.candidates);
  final List<({String id, String name})> candidates;
}

/// Id-or-name resolution used by the agent tools (UI navigates by id and
/// never needs this):
///
///  1. exact id match first (archived rows included);
///  2. otherwise a normalized exact name match against *active* rows, done
///     in SQL (`LOWER(TRIM(name)) = target`) so we never load a whole table
///     into memory — resolved only when the match is unique;
///  3. multiple name matches → [Ambiguous] with the candidates;
///  4. nothing → [NotFound].
///
/// Note: the name match uses SQLite's `LOWER` (ASCII-only) and `TRIM` (spaces
/// only), so mixed-case non-ASCII names (e.g. "CAFÉ" vs "café") may not match.
/// Acceptable here — the agent can fall back to the list tools.
class EntityResolver {
  EntityResolver(this.db, this.defaultCurrency);

  final AppDatabase db;

  /// The user's default currency, used to break a name-collision tie between
  /// two accounts that differ only by currency.
  final String Function() defaultCurrency;

  Future<ResolveResult<Account>> account(String idOrName) async {
    final byId = await (db.select(
      db.accounts,
    )..where((t) => t.id.equals(idOrName))).getSingleOrNull();
    if (byId != null) return Resolved(byId);

    final matches =
        await (db.select(db.accounts)
              ..where((t) => t.archived.equals(false))
              ..where(
                (t) => t.name.trim().lower().equals(normalizeName(idOrName)),
              ))
            .get();
    final result = _result(matches, (a) => a.id, (a) => a.name);
    if (result is Ambiguous<Account>) {
      final byDefaultCurrency = matches
          .where((a) => a.currency == defaultCurrency())
          .toList();
      if (byDefaultCurrency.length == 1) {
        return Resolved(byDefaultCurrency.first);
      }
    }
    return result;
  }

  Future<ResolveResult<Category>> category(String idOrName) async {
    final byId = await (db.select(
      db.categories,
    )..where((t) => t.id.equals(idOrName))).getSingleOrNull();
    if (byId != null) return Resolved(byId);

    final matches =
        await (db.select(db.categories)
              ..where((t) => t.archived.equals(false))
              ..where(
                (t) => t.name.trim().lower().equals(normalizeName(idOrName)),
              ))
            .get();
    return _result(matches, (c) => c.id, (c) => c.name);
  }

  Future<ResolveResult<Tag>> tag(String idOrName) async {
    final byId = await (db.select(
      db.tags,
    )..where((t) => t.id.equals(idOrName))).getSingleOrNull();
    if (byId != null) return Resolved(byId);

    final matches =
        await (db.select(db.tags)
              ..where((t) => t.archived.equals(false))
              ..where(
                (t) => t.name.trim().lower().equals(normalizeName(idOrName)),
              ))
            .get();
    return _result(matches, (t) => t.id, (t) => t.name);
  }

  ResolveResult<T> _result<T>(
    List<T> matches,
    String Function(T) idOf,
    String Function(T) nameOf,
  ) {
    if (matches.length == 1) return Resolved(matches.first);
    if (matches.length > 1) {
      return Ambiguous([
        for (final m in matches) (id: idOf(m), name: nameOf(m)),
      ]);
    }
    return const NotFound();
  }
}
