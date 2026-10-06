import 'dart:ui' show lerpDouble;

import 'package:app/components/grouped_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// An M3 expressive grouped list the user reorders like home-screen icons:
/// long-press a row to lift it, drag, and the others slide aside to preview
/// where it will land. Dropping calls [onReorder] with the whole list in its
/// new order; the list shows that order immediately and keeps it until the
/// caller's stream catches up. Taps still reach the rows.
///
/// Long-press starts the drag on every platform (desktop's default drag
/// handles are off) so the gesture is the same everywhere.
class ReorderableGroupedList<T> extends StatefulWidget {
  const ReorderableGroupedList({
    super.key,
    required this.items,
    required this.idOf,
    required this.itemBuilder,
    required this.onReorder,
    required this.reorderFailedMessage,
    this.padding,
  });

  final List<T> items;
  final String Function(T item) idOf;

  /// Builds one row, given the corner shape for its place in the group.
  final Widget Function(BuildContext context, T item, BorderRadius radius)
  itemBuilder;

  /// Persists the new order. A thrown error restores the previous order and
  /// shows [reorderFailedMessage].
  final Future<void> Function(List<T> itemsInOrder) onReorder;
  final String reorderFailedMessage;
  final EdgeInsets? padding;

  @override
  State<ReorderableGroupedList<T>> createState() =>
      _ReorderableGroupedListState<T>();
}

class _ReorderableGroupedListState<T> extends State<ReorderableGroupedList<T>> {
  /// The order just dropped, shown until [widget.items] reflects the write.
  List<T>? _pending;
  bool _writeDone = false;

  List<T> get _visible => _pending ?? widget.items;

  @override
  void didUpdateWidget(covariant ReorderableGroupedList<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pending = _pending;
    if (pending == null) return;
    // Once the write has landed, the next list from the caller is the truth
    // (it may also carry edits synced meanwhile).
    if (_writeDone || _sameOrder(widget.items, pending)) _pending = null;
  }

  bool _sameOrder(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (widget.idOf(a[i]) != widget.idOf(b[i])) return false;
    }
    return true;
  }

  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final next = List<T>.of(_visible);
    next.insert(newIndex, next.removeAt(oldIndex));
    setState(() {
      _pending = next;
      _writeDone = false;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onReorder(next);
      if (!mounted) return;
      _writeDone = true;
    } catch (e, st) {
      debugPrint('Error reordering: $e\n$st');
      if (!mounted) return;
      setState(() => _pending = null);
      messenger.showSnackBar(
        SnackBar(content: Text(widget.reorderFailedMessage)),
      );
    }
  }

  /// The lifted row: fully rounded, raised, and slightly enlarged so it reads
  /// as picked up.
  Widget _decorateProxy(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(animation.value);
        return Transform.scale(
          scale: lerpDouble(1, 1.03, t)!,
          child: Material(
            elevation: lerpDouble(0, 8, t)!,
            color: Colors.transparent,
            shadowColor: Theme.of(context).colorScheme.shadow,
            borderRadius: BorderRadius.circular(kGroupOuterRadius),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    return ReorderableListView.builder(
      padding: widget.padding,
      itemCount: items.length,
      buildDefaultDragHandles: false,
      proxyDecorator: _decorateProxy,
      onReorderStart: (_) => HapticFeedback.mediumImpact(),
      // CI and release builds use Flutter 3.41, whose callback reports the
      // insertion slot before removing the dragged row.
      onReorder: (oldIndex, newIndex) => _handleReorder(
        oldIndex,
        newIndex > oldIndex ? newIndex - 1 : newIndex,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey(widget.idOf(item)),
          index: index,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: index == items.length - 1 ? 0 : kGroupSpacing,
            ),
            child: widget.itemBuilder(
              context,
              item,
              groupedRadius(index, items.length),
            ),
          ),
        );
      },
    );
  }
}
