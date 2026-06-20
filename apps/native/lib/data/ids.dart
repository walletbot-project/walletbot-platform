import 'package:uuid/uuid.dart';

/// Single entity-id scheme for all local writes (replaces the three schemes
/// that coexisted before: microsecond timestamps in the insight views, hand
/// rolled RFC-4122 in the voice tools, and package:uuid in account creation).
String newUuid() => const Uuid().v4();
