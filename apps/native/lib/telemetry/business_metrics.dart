import 'dart:async';

import 'telemetry_client.dart';

class BusinessMetrics {
  const BusinessMetrics(this._telemetry);

  final TelemetryClient? _telemetry;

  void userAccountCreated({required String authMethod}) {
    _trackMetric(
      'business.user_accounts.created_count',
      attributes: {'auth_method': authMethod},
    );
  }

  void financialAccountCreated({
    required String createdBy,
    String ingestPath = 'direct_client',
  }) {
    _trackMetric(
      'business.financial_accounts.created_count',
      attributes: {'created_by': createdBy, 'ingest_path': ingestPath},
    );
  }

  void movementCreated({
    required String movementType,
    required String createdBy,
    String ingestPath = 'direct_client',
  }) {
    _trackMetric(
      'business.movements.created_count',
      attributes: {
        'movement_type': movementType,
        'created_by': createdBy,
        'ingest_path': ingestPath,
      },
    );
  }

  void transferCreated({
    required String createdBy,
    required bool crossCurrency,
    String ingestPath = 'direct_client',
  }) {
    _trackMetric(
      'business.transfers.created_count',
      attributes: {
        'created_by': createdBy,
        'ingest_path': ingestPath,
        'cross_currency': crossCurrency,
      },
    );
  }

  void _trackMetric(String name, {required Map<String, Object?> attributes}) {
    unawaited(
      _telemetry?.trackMetric(
        name,
        type: 'counter',
        value: 1,
        unit: 'count',
        attributes: attributes,
      ),
    );
  }
}
