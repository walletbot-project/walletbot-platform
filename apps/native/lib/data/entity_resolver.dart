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

/// Id-or-fuzzy-name resolution used by the agent tools (UI navigates by id
/// and never needs this). Semantics — preserved exactly from the original
/// tool executors:
///
///  1. exact id match first (archived rows included);
///  2. otherwise a normalized (trim + lowercase) exact name match against
///     *active* rows — resolved only when the match is unique;
///  3. multiple name matches → [Ambiguous] with the candidates;
///  4. nothing → [NotFound].
class EntityResolver {
  EntityResolver(this.db);

  final AppDatabase db;

  Future<ResolveResult<Account>> account(String idOrName) async {
    final byId = await (db.select(db.accounts)
          ..where((t) => t.id.equals(idOrName)))
        .getSingleOrNull();
    if (byId != null) return Resolved(byId);

    final candidates = await (db.select(db.accounts)
          ..where((t) => t.archived.equals(false)))
        .get();
    return _byName(idOrName, candidates, (a) => a.id, (a) => a.name);
  }

  Future<ResolveResult<Category>> category(String idOrName) async {
    final byId = await (db.select(db.categories)
          ..where((t) => t.id.equals(idOrName)))
        .getSingleOrNull();
    if (byId != null) return Resolved(byId);

    final candidates = await (db.select(db.categories)
          ..where((t) => t.archived.equals(false)))
        .get();
    return _byName(idOrName, candidates, (c) => c.id, (c) => c.name);
  }

  Future<ResolveResult<Tag>> tag(String idOrName) async {
    final byId = await (db.select(db.tags)
          ..where((t) => t.id.equals(idOrName)))
        .getSingleOrNull();
    if (byId != null) return Resolved(byId);

    final candidates = await (db.select(db.tags)
          ..where((t) => t.archived.equals(false)))
        .get();
    return _byName(idOrName, candidates, (t) => t.id, (t) => t.name);
  }

  ResolveResult<T> _byName<T>(
    String idOrName,
    List<T> candidates,
    String Function(T) idOf,
    String Function(T) nameOf,
  ) {
    final target = normalizeName(idOrName);
    final matches =
        candidates.where((c) => normalizeName(nameOf(c)) == target).toList();
    if (matches.length == 1) return Resolved(matches.first);
    if (matches.length > 1) {
      return Ambiguous(
        [for (final m in matches) (id: idOf(m), name: nameOf(m))],
      );
    }
    return const NotFound();
  }
}
