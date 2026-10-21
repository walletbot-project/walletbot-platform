import 'package:drift/drift.dart';
import 'package:sqlite3/common.dart';

/// SQLite's `lower()` and `LIKE` only fold ASCII, so "Crédito" never matched
/// "credito" and "CAFÉ" never matched "café". Text search folds both sides
/// through [foldForSearch] instead: lowercase, accents and ñ stripped.
const searchFoldFunction = 'search_fold';

const _foldedLetters = {
  'á': 'a',
  'à': 'a',
  'â': 'a',
  'ä': 'a',
  'ã': 'a',
  'å': 'a',
  'é': 'e',
  'è': 'e',
  'ê': 'e',
  'ë': 'e',
  'í': 'i',
  'ì': 'i',
  'î': 'i',
  'ï': 'i',
  'ó': 'o',
  'ò': 'o',
  'ô': 'o',
  'ö': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'û': 'u',
  'ü': 'u',
  'ñ': 'n',
  'ç': 'c',
  'ý': 'y',
  'ÿ': 'y',
};

bool _isCombiningMark(int rune) => rune >= 0x0300 && rune <= 0x036F;

String foldForSearch(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    if (_isCombiningMark(rune)) continue;
    final char = String.fromCharCode(rune);
    buffer.write(_foldedLetters[char] ?? char);
  }
  return buffer.toString();
}

/// Registers [searchFoldFunction] on a raw connection. Every connection that
/// runs transaction queries needs it, including in-memory test databases.
void registerSearchFunctions(CommonDatabase database) {
  database.createFunction(
    functionName: searchFoldFunction,
    argumentCount: const AllowedArgumentCount(1),
    deterministic: true,
    function: (args) {
      final value = args[0];
      return value is String ? foldForSearch(value) : value;
    },
  );
}

Expression<String> searchFold(Expression<String> value) =>
    FunctionCallExpression<String>(searchFoldFunction, [value]);
