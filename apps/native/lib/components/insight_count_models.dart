import 'package:app/database.dart';

class CategoryWithCount {
  const CategoryWithCount({
    required this.category,
    required this.transactionCount,
  });

  final Category category;
  final int transactionCount;
}

class TagWithCount {
  const TagWithCount({required this.tag, required this.transactionCount});

  final Tag tag;
  final int transactionCount;
}
