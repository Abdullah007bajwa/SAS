import 'package:drift/drift.dart';

/// Mixin providing common synchronization and audit columns for all synchronized tables.
mixin SyncColumns on Table {
  TextColumn get syncId => text().unique()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get isSynced => integer().withDefault(const Constant(0))();
}
