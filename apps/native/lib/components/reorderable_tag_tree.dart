import 'package:app/components/grouped_card.dart';
import 'package:app/database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;

/// One tag and its sub-tags, in display order.
class TagTreeNode {
  TagTreeNode(this.tag);

  final Tag tag;
  final List<TagTreeNode> children = [];
}

/// Groups [tags] into their tree, keeping the given order inside each level.
/// A tag whose parent is missing (archived, or not in [tags]) shows at the top
/// level.
List<TagTreeNode> buildTagTree(List<Tag> tags) {
  final nodesById = {for (final t in tags) t.id: TagTreeNode(t)};
  final roots = <TagTreeNode>[];
  for (final tag in tags) {
    final node = nodesById[tag.id]!;
    final parent = nodesById[tag.parentId];
    if (parent != null) {
      parent.children.add(node);
    } else {
      roots.add(node);
    }
  }
  return roots;
}

/// The tag tree, reorderable by level like home-screen icons: long-press a
/// tag's chip to lift it together with its sub-tags, drag, and its siblings
/// slide aside to preview where the family will land. A tag only ever moves
/// among its siblings, so the hierarchy never changes here.
///
/// Built on [LongPressDraggable]/[DragTarget] rather than
/// [ReorderableListView]: that list resolves a drop by comparing edges of the
/// lifted item against its own original slot, so a tall item (a family) that
/// is dragged past its target snaps back to where it started. Here each
/// family is a target that only accepts its siblings, and the last previewed
/// slot is kept until the finger lifts.
class ReorderableTagTree extends StatelessWidget {
  const ReorderableTagTree({
    super.key,
    required this.roots,
    required this.chipBuilder,
    required this.onReorder,
    required this.reorderFailedMessage,
    required this.moveUpLabel,
    required this.moveDownLabel,
    this.padding = EdgeInsets.zero,
  });

  final List<TagTreeNode> roots;

  /// Builds a tag's chip. Taps on it still reach the chip.
  final Widget Function(BuildContext context, Tag tag) chipBuilder;

  /// Persists one level's new order: the children of `parentId` (top-level
  /// tags when null), as ids. A thrown error restores the previous order and
  /// shows [reorderFailedMessage].
  final Future<void> Function(String? parentId, List<String> idsInOrder)
  onReorder;
  final String reorderFailedMessage;

  /// Screen-reader actions for moving a tag one place among its siblings.
  final String moveUpLabel;
  final String moveDownLabel;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: padding,
      children: [_TagLevel(parentId: null, nodes: roots, tree: this)],
    );
  }
}

/// What a lifted chip carries: which tag, and which level it belongs to.
class _TagDrag {
  const _TagDrag(this.id, this.parentId);

  final String id;
  final String? parentId;
}

const double _siblingSpacing = 8;
const double _childIndent = 20;
const Duration _slide = Duration(milliseconds: 160);

/// The siblings under [parentId]. Owns the drag of its own tags only.
class _TagLevel extends StatefulWidget {
  const _TagLevel({
    required this.parentId,
    required this.nodes,
    required this.tree,
  });

  final String? parentId;
  final List<TagTreeNode> nodes;
  final ReorderableTagTree tree;

  @override
  State<_TagLevel> createState() => _TagLevelState();
}

class _TagLevelState extends State<_TagLevel> {
  final Map<String, GlobalKey> _familyKeys = {};

  /// The order just dropped, shown until [widget.nodes] reflects the write.
  List<String>? _pending;
  bool _writeDone = false;

  /// The lifted tag, the slot its gap currently opens at (an index among the
  /// other siblings), and the gap's height (the lifted family's).
  String? _draggingId;
  int? _slot;
  double _gapHeight = 0;

  /// Where the finger went down inside the lifted chip. Drag targets report
  /// the feedback's top-left corner; adding this gives the finger itself,
  /// which is what decides the drop.
  Offset _grab = Offset.zero;

  GlobalKey _keyFor(String id) =>
      _familyKeys.putIfAbsent(id, () => GlobalKey(debugLabel: 'tag-$id'));

  List<TagTreeNode> get _visible {
    final pending = _pending;
    if (pending == null) return widget.nodes;
    final byId = {for (final n in widget.nodes) n.tag.id: n};
    return [
      for (final id in pending)
        if (byId[id] != null) byId[id]!,
      // Anything that appeared meanwhile keeps its place at the end.
      for (final n in widget.nodes)
        if (!pending.contains(n.tag.id)) n,
    ];
  }

  @override
  void didUpdateWidget(covariant _TagLevel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pending = _pending;
    if (pending == null) return;
    final ids = [for (final n in widget.nodes) n.tag.id];
    // Once the write has landed, the next list from the caller is the truth.
    if (_writeDone || _sameOrder(ids, pending)) _pending = null;
  }

  bool _sameOrder(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<TagTreeNode> get _others => [
    for (final n in _visible)
      if (n.tag.id != _draggingId) n,
  ];

  void _startDrag(TagTreeNode node) {
    final box = _keyFor(node.tag.id).currentContext?.findRenderObject();
    setState(() {
      _draggingId = node.tag.id;
      // The gap opens where the family was, so nothing jumps on pick-up.
      _slot = _visible.indexOf(node);
      _gapHeight = box is RenderBox ? box.size.height : 0;
    });
  }

  /// The finger is over sibling [target]: its upper half puts the lifted tag
  /// before it, its lower half after it.
  void _hover(TagTreeNode target, _TagDrag drag, Offset feedbackTopLeft) {
    // Targets hear every drag passing over them, accepted or not; only a
    // sibling of this level moves this level's gap.
    if (drag.parentId != widget.parentId || drag.id != _draggingId) return;
    final box = _keyFor(target.tag.id).currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final local = box.globalToLocal(feedbackTopLeft + _grab);
    final index = _others.indexOf(target);
    if (index < 0) return;
    final slot = local.dy < box.size.height / 2 ? index : index + 1;
    if (slot != _slot) setState(() => _slot = slot);
  }

  void _endDrag() {
    final draggingId = _draggingId;
    final slot = _slot;
    // Read the siblings while the lifted tag is still excluded from them.
    final others = [for (final n in _others) n.tag.id];
    setState(() {
      _draggingId = null;
      _slot = null;
    });
    if (draggingId == null || slot == null) return;
    _commit(others..insert(slot, draggingId));
  }

  void _moveBy(TagTreeNode node, int delta) {
    final order = [for (final n in _visible) n.tag.id];
    final from = order.indexOf(node.tag.id);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= order.length) return;
    order.insert(to, order.removeAt(from));
    _commit(order);
  }

  Future<void> _commit(List<String> order) async {
    final current = [for (final n in _visible) n.tag.id];
    if (_sameOrder(order, current)) return;
    setState(() {
      _pending = order;
      _writeDone = false;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.tree.onReorder(widget.parentId, order);
      if (!mounted) return;
      _writeDone = true;
    } catch (e, st) {
      debugPrint('Error reordering tags: $e\n$st');
      if (!mounted) return;
      setState(() => _pending = null);
      messenger.showSnackBar(
        SnackBar(content: Text(widget.tree.reorderFailedMessage)),
      );
    }
  }

  Widget _gap(int slot) {
    final open = _draggingId != null && _slot == slot;
    return AnimatedContainer(
      duration: _slide,
      curve: Curves.easeOut,
      height: open ? _gapHeight + _siblingSpacing : 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final others = _others;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var j = 0; j <= others.length; j++) ...[
          _gap(j),
          if (j < others.length) _family(others[j], visible),
        ],
        // The lifted family stays mounted (its draggable owns the gesture)
        // but takes no room: the gap stands in for it.
        for (final n in visible)
          if (n.tag.id == _draggingId) _family(n, visible),
      ],
    );
  }

  Widget _family(TagTreeNode node, List<TagTreeNode> visible) {
    final index = visible.indexOf(node);
    final lifted = node.tag.id == _draggingId;
    final tree = widget.tree;
    return KeyedSubtree(
      key: ValueKey(node.tag.id),
      child: Visibility(
        visible: !lifted,
        maintainState: true,
        child: DragTarget<_TagDrag>(
          onWillAcceptWithDetails: (details) =>
              details.data.parentId == widget.parentId &&
              details.data.id != node.tag.id,
          onMove: (details) => _hover(node, details.data, details.offset),
          builder: (context, _, _) => Padding(
            key: _keyFor(node.tag.id),
            padding: const EdgeInsets.only(bottom: _siblingSpacing),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  customSemanticsActions: {
                    if (index > 0)
                      CustomSemanticsAction(label: tree.moveUpLabel): () =>
                          _moveBy(node, -1),
                    if (index < visible.length - 1)
                      CustomSemanticsAction(label: tree.moveDownLabel): () =>
                          _moveBy(node, 1),
                  },
                  child: Listener(
                    onPointerDown: (event) => _grab = event.localPosition,
                    child: LongPressDraggable<_TagDrag>(
                      data: _TagDrag(node.tag.id, widget.parentId),
                      // The feedback keeps the chip under the finger where it
                      // was grabbed; the finger decides the drop.
                      dragAnchorStrategy: childDragAnchorStrategy,
                      onDragStarted: () => _startDrag(node),
                      onDragEnd: (_) => _endDrag(),
                      feedback: _LiftedFamily(node: node, tree: tree),
                      child: tree.chipBuilder(context, node.tag),
                    ),
                  ),
                ),
                if (node.children.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: _childIndent,
                      top: _siblingSpacing,
                    ),
                    child: _TagLevel(
                      parentId: node.tag.id,
                      nodes: node.children,
                      tree: tree,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The picked-up family: its chip and every sub-tag, raised off the list.
class _LiftedFamily extends StatelessWidget {
  const _LiftedFamily({required this.node, required this.tree});

  final TagTreeNode node;
  final ReorderableTagTree tree;

  @override
  Widget build(BuildContext context) {
    // Shifted back by its padding so the lifted chip sits exactly over the
    // one that was grabbed.
    return Transform.translate(
      offset: const Offset(-_siblingSpacing, -_siblingSpacing),
      child: _card(context),
    );
  }

  Widget _card(BuildContext context) {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      shadowColor: Theme.of(context).colorScheme.shadow,
      borderRadius: BorderRadius.circular(kGroupOuterRadius),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(_siblingSpacing),
        child: _StaticFamily(node: node, tree: tree),
      ),
    );
  }
}

class _StaticFamily extends StatelessWidget {
  const _StaticFamily({required this.node, required this.tree});

  final TagTreeNode node;
  final ReorderableTagTree tree;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        tree.chipBuilder(context, node.tag),
        for (final child in node.children)
          Padding(
            padding: const EdgeInsets.only(
              left: _childIndent,
              top: _siblingSpacing,
            ),
            child: _StaticFamily(node: child, tree: tree),
          ),
      ],
    );
  }
}
