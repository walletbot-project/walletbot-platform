import 'package:drift/drift.dart';

import '../../database.dart';
import '../../voice/agent_generated.dart' show kAgentContextMemoriesCap;
import '../ids.dart';
import 'repository_base.dart';

/// Reads and writes for the agent's long-term memory (`agent_memories`,
/// synced — see the v4 schema step). The write contract matches every other
/// repository: dirty + updatedAt on writes, archive + tombstone on deletes.
class AgentMemoryRepository extends RepositoryBase {
  AgentMemoryRepository(super.db);

  /// Longest memory accepted — memories are one-liners, not documents.
  /// Mirrors MAX_CONTENT_CHARS in `convex/v1/memories/mutations.ts`.
  static const maxContentChars = 500;

  /// Active memories, insertion order (the order the prompt renders them in).
  Future<List<AgentMemory>> listActive() =>
      (db.select(db.agentMemories)
            ..where((m) => m.archived.equals(false))
            ..orderBy([
              (m) => OrderingTerm(expression: m.createdAt),
              (m) => OrderingTerm(expression: m.id),
            ])
            ..limit(kAgentContextMemoriesCap))
          .get();

  /// Exact-id lookup; finds archived memories too. Null when missing.
  Future<AgentMemory?> getById(String id) => (db.select(
    db.agentMemories,
  )..where((m) => m.id.equals(id))).getSingleOrNull();

  String _normalized(String raw) {
    final content = raw.trim();
    if (content.isEmpty) {
      throw const FormatException('Memory content cannot be empty');
    }
    return content.length > maxContentChars
        ? content.substring(0, maxContentChars)
        : content;
  }

  /// Creates a memory and returns its id. Throws a [StateError] carrying the
  /// "consolidate first" message when the active set is at its cap — the
  /// agent is instructed to merge/rewrite instead of appending forever.
  Future<String> create({required String content, String? id}) async {
    final active = await listActive();
    if (active.length >= kAgentContextMemoriesCap) {
      throw StateError(
        'Memory limit reached — consolidate first: merge or rewrite existing '
        'memories (updateMemory) and delete obsolete ones (forgetMemory) '
        'before adding new ones',
      );
    }
    final memoryId = id ?? newUuid();
    final now = currentMs;
    await db
        .into(db.agentMemories)
        .insert(
          AgentMemoriesCompanion.insert(
            id: memoryId,
            content: _normalized(content),
            createdAt: now,
            updatedAt: now,
            dirty: const Value(true),
          ),
          mode: InsertMode.insertOrReplace,
        );
    return memoryId;
  }

  /// Rewrites a memory's content. Returns false when the id names no active
  /// memory.
  Future<bool> update(String id, {required String content}) async {
    final existing = await getById(id);
    if (existing == null || existing.archived) return false;
    await (db.update(db.agentMemories)..where((m) => m.id.equals(id))).write(
      AgentMemoriesCompanion(
        content: Value(_normalized(content)),
        updatedAt: Value(currentMs),
        dirty: const Value(true),
      ),
    );
    return true;
  }

  /// Soft delete: `archived = true` + tombstone, atomically. Idempotent.
  Future<void> archive(String id) async {
    final now = currentMs;
    await db.transaction(() async {
      await (db.update(db.agentMemories)..where((m) => m.id.equals(id))).write(
        AgentMemoriesCompanion(
          archived: const Value(true),
          updatedAt: Value(now),
          dirty: const Value(true),
        ),
      );
      await markDeleted('agentMemories', id);
    });
  }
}
