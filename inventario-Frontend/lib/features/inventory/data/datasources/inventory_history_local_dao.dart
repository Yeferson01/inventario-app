import 'package:drift/drift.dart';
import 'dart:convert';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';
import '../models/inventory_history_models.dart';

// Compare every storage representation on one UTC epoch-millisecond axis.
// Drift stores DateTime as Unix seconds; hydrated history stores ISO text.
// Numeric values below 100 billion are seconds, larger values milliseconds.
const _occurredEpochMillisSql = '''
  case
    when typeof(m.occurred_at) in ('integer', 'real') then
      case when m.occurred_at < 100000000000
        then m.occurred_at * 1000 else m.occurred_at end
    else round((julianday(m.occurred_at) - 2440587.5) * 86400000)
  end
''';

int _sqlEpochMillis(DateTime value) =>
    (value.toUtc().microsecondsSinceEpoch + 500) ~/ 1000;

class InventoryHistoryLocalDao {
  InventoryHistoryLocalDao(this._db);

  static const domain = 'inventory_movements';

  final AppDatabase _db;

  String _serverAuthoritativeMetadata(Object? rawMetadata) {
    final metadata = <String, dynamic>{};

    if (rawMetadata != null) {
      if (rawMetadata is! String) {
        throw const FormatException(
          'Inventory movement metadata_json must be a JSON object.',
        );
      }

      final normalized = rawMetadata.trim();

      if (normalized.isNotEmpty) {
        final decoded = jsonDecode(normalized);

        if (decoded is! Map) {
          throw const FormatException(
            'Inventory movement metadata_json must be a JSON object.',
          );
        }

        for (final entry in decoded.entries) {
          metadata[entry.key.toString()] = entry.value;
        }
      }
    }

    metadata['server_authoritative_history'] = true;

    return jsonEncode(metadata);
  }

  Future<void> applyRefreshPage({
    required String businessId,
    required String branchId,
    required InventoryHistoryRemotePage page,
    required bool canViewCosts,
    DateTime? refreshedAt,
  }) {
    return _db.transaction(() async {
      for (final row in page.rows) {
        await _mergeRemoteRow(row, canViewCosts: canViewCosts);
      }
      final existing = await _state(
        businessId: businessId,
        branchId: branchId,
      );
      final existingCursor = _cursor(existing);
      final tail = existingCursor ?? page.nextCursor;
      await _writeState(
        businessId: businessId,
        branchId: branchId,
        cursor: tail,
        hasMore: existingCursor == null
            ? page.hasMore
            : _asBool(existing?['has_more']),
        lastRefreshedAt: (refreshedAt ?? DateTime.now()).toUtc(),
        preserveLastRefreshedAt: false,
      );
    });
  }

  Future<void> applyOlderPage({
    required String businessId,
    required String branchId,
    required InventoryHistoryRemotePage page,
    required bool canViewCosts,
  }) {
    return _db.transaction(() async {
      for (final row in page.rows) {
        await _mergeRemoteRow(row, canViewCosts: canViewCosts);
      }
      final existing = await _state(
        businessId: businessId,
        branchId: branchId,
      );
      final tail = page.nextCursor ?? _cursor(existing);
      await _writeState(
        businessId: businessId,
        branchId: branchId,
        cursor: tail,
        hasMore: page.rows.isNotEmpty && page.hasMore,
        lastRefreshedAt: null,
        preserveLastRefreshedAt: true,
      );
    });
  }

  Future<InventoryHistoryCoverage> getCoverage({
    required String businessId,
    required String branchId,
  }) async {
    final state = await _state(
      businessId: businessId,
      branchId: branchId,
    );
    final count = await _db.customSelect(
      '''
      select count(*) as value
      from local_inventory_movements
      where business_id = ? and branch_id = ? and deleted_at is null
      ''',
      variables: [Variable<String>(businessId), Variable<String>(branchId)],
      readsFrom: {_db.localInventoryMovements},
    ).getSingle();
    return InventoryHistoryCoverage(
      hasCachedRows: count.read<int>('value') > 0,
      hasMoreRemote: state == null ? true : _asBool(state['has_more']),
      oldestCursor: _cursor(state),
      lastRefreshedAt: _asDateTime(state?['last_refreshed_at']),
    );
  }

  Future<List<InventoryMovementHistoryEntry>> loadHistory({
    required InventoryHistoryLocalQuery query,
    required bool canViewCosts,
  }) async {
    final clauses = <String>[
      'm.business_id = ?',
      'm.branch_id = ?',
      'm.deleted_at is null',
    ];
    final variables = <Variable>[
      Variable<String>(query.businessId),
      Variable<String>(query.branchId),
    ];
    if (query.productId != null) {
      clauses.add('m.product_id = ?');
      variables.add(Variable<String>(query.productId!));
    }
    if (query.effectiveType != null) {
      clauses.add('''
        case
          when lower(coalesce(m.reference_type, '')) in (
            'manual_initial_stock', 'initial_stock'
          ) then 'initial_stock'
          when nullif(lower(trim(source_type)), '') is not null
            then lower(trim(m.source_type))
          else lower(trim(m.movement_type))
        end = ?
      ''');
      variables
          .add(Variable<String>(query.effectiveType!.trim().toLowerCase()));
    }
    if (query.from != null) {
      clauses.add('($_occurredEpochMillisSql) >= ?');
      variables.add(Variable<int>(_sqlEpochMillis(query.from!)));
    }
    if (query.to != null) {
      clauses.add('($_occurredEpochMillisSql) <= ?');
      variables.add(Variable<int>(_sqlEpochMillis(query.to!)));
    }
    if (query.cursor != null) {
      clauses.add('''
        (($_occurredEpochMillisSql) < ? or
          (($_occurredEpochMillisSql) = ? and m.id < ?))
      ''');
      final cursorMillis = _sqlEpochMillis(query.cursor!.occurredAt);
      variables
        ..add(Variable<int>(cursorMillis))
        ..add(Variable<int>(cursorMillis))
        ..add(Variable<String>(query.cursor!.id));
    }
    final limit = query.limit.clamp(1, 200);
    variables.add(Variable<int>(limit));

    final rows = await _db
        .customSelect(
          '''
      select
        m.*,
        p.name as product_name,
        coalesce(
          (
            select pb.barcode
            from local_product_barcodes pb
            where pb.scope = 'business'
              and pb.business_id = m.business_id
              and pb.product_id = m.product_id
              and pb.status = 'active'
              and pb.deleted_at is null
            order by
              pb.is_primary desc,
              pb.updated_at desc,
              pb.id desc
            limit 1
          ),
          p.barcode
        ) as product_barcode,
        case
          when lower(coalesce(m.reference_type, '')) in (
            'manual_initial_stock', 'initial_stock'
          ) then 'initial_stock'
          when nullif(lower(trim(m.source_type)), '') is not null
            then lower(trim(m.source_type))
          else lower(trim(m.movement_type))
        end as effective_type
      from local_inventory_movements m
      left join products p
        on p.id = m.product_id
       and p.business_id = m.business_id
      where ${clauses.join(' and ')}
      order by ($_occurredEpochMillisSql) desc, m.id desc
      limit ?
      ''',
          variables: variables,
          readsFrom: {
            _db.localInventoryMovements,
            _db.products,
            _db.localProductBarcodes,
          },
        )
        .get();

    return rows.map((row) {
      final data = row.data;
      return InventoryMovementHistoryEntry(
        id: data['id'].toString(),
        businessId: data['business_id'].toString(),
        branchId: data['branch_id'].toString(),
        productId: data['product_id'].toString(),
        productName: data['product_name']?.toString(),
        productBarcode: data['product_barcode']?.toString(),
        movementType: data['movement_type'].toString(),
        sourceType: data['source_type']?.toString(),
        effectiveType: data['effective_type'].toString(),
        sourceId: data['source_id']?.toString(),
        referenceType: data['reference_type']?.toString(),
        referenceId: data['reference_id']?.toString(),
        quantityDelta: (data['quantity_change'] as num).toInt(),
        occurredAt: _asDateTime(data['occurred_at']) ??
            (throw const FormatException(
                'Invalid inventory movement timestamp.')),
        previousStock: (data['previous_stock'] as num?)?.toInt(),
        newStock: (data['new_stock'] as num?)?.toInt(),
        createdBy: data['created_by']?.toString(),
        deviceId: data['device_id']?.toString(),
        reversedMovementId: data['reversed_movement_id']?.toString(),
        unitCost: canViewCosts ? (data['unit_cost'] as num?)?.toDouble() : null,
      );
    }).toList(growable: false);
  }

  Future<void> _mergeRemoteRow(
    InventoryHistoryRemoteRow row, {
    required bool canViewCosts,
  }) async {
    final current = await _db.customSelect(
      '''
      select business_id, branch_id, sync_status, local_status, metadata_json
      from local_inventory_movements where id = ?
      ''',
      variables: [Variable<String>(row.id)],
      readsFrom: {_db.localInventoryMovements},
    ).getSingleOrNull();
    final now = DateTime.now().toUtc();
    if (current == null) {
      await _statement(
        '''
        insert into local_inventory_movements (
          id, business_id, branch_id, product_id, movement_type,
          quantity_change, unit_cost, previous_stock, new_stock,
          created_by, device_id, reversed_movement_id,
          source_type, source_id, reference_type, reference_id,
          idempotency_key, sync_status, local_status, version,
	  metadata_json,
	  occurred_at, created_at, updated_at, last_synced_at
        ) values (
          ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
          1, 'synced', 1, ?, ?, ?, ?, ?
        )
        ''',
        [
          row.id,
          row.businessId,
          row.branchId,
          row.productId,
          row.movementType,
          row.quantityDelta,
          canViewCosts ? row.unitCost : null,
          row.previousStock,
          row.newStock,
          row.createdBy,
          row.deviceId,
          row.reversedMovementId,
          row.sourceType,
          row.sourceId,
          row.referenceType,
          row.referenceId,
          row.idempotencyKey,
          _serverAuthoritativeMetadata(null),
          row.occurredAt,
          row.occurredAt,
          now,
          now,
        ],
      );
      return;
    }

    if (current.data['business_id']?.toString() != row.businessId ||
        current.data['branch_id']?.toString() != row.branchId) {
      throw StateError(
        'Inventory movement identity collides with another local scope.',
      );
    }

    final isPending = current.data['sync_status'] != 1 ||
        current.data['local_status']?.toString() != 'synced';
    if (isPending) {
      await _statement(
        '''
        update local_inventory_movements set
          previous_stock = ?, new_stock = ?, created_by = ?, device_id = ?,
          reversed_movement_id = ?,
          unit_cost = case when ? then ? else unit_cost end,
          updated_at = ?
        where id = ?
        ''',
        [
          row.previousStock,
          row.newStock,
          row.createdBy,
          row.deviceId,
          row.reversedMovementId,
          canViewCosts,
          row.unitCost,
          now,
          row.id,
        ],
      );
      return;
    }

    await _statement(
      '''
      update local_inventory_movements set
        business_id = ?, branch_id = ?, product_id = ?, movement_type = ?,
        quantity_change = ?,
        unit_cost = case when ? then ? else unit_cost end,
        previous_stock = ?, new_stock = ?, created_by = ?, device_id = ?,
        reversed_movement_id = ?, source_type = ?, source_id = ?,
        reference_type = ?, reference_id = ?,
	metadata_json = ?,
	occurred_at = ?, updated_at = ?, last_synced_at = ?, deleted_at = null
      where id = ?
      ''',
      [
        row.businessId,
        row.branchId,
        row.productId,
        row.movementType,
        row.quantityDelta,
        canViewCosts,
        row.unitCost,
        row.previousStock,
        row.newStock,
        row.createdBy,
        row.deviceId,
        row.reversedMovementId,
        row.sourceType,
        row.sourceId,
        row.referenceType,
        row.referenceId,
        _serverAuthoritativeMetadata(current.data['metadata_json']),
        row.occurredAt,
        now,
        now,
        row.id,
      ],
    );
  }

  Future<Map<String, Object?>?> _state({
    required String businessId,
    required String branchId,
  }) async {
    final row = await _db.customSelect(
      '''
      select * from local_history_hydration_states
      where business_id = ? and branch_id = ? and domain = ?
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
        const Variable<String>(domain),
      ],
      readsFrom: {_db.localHistoryHydrationStates},
    ).getSingleOrNull();
    return row?.data;
  }

  Future<void> _writeState({
    required String businessId,
    required String branchId,
    required InventoryHistoryCursor? cursor,
    required bool hasMore,
    required DateTime? lastRefreshedAt,
    required bool preserveLastRefreshedAt,
  }) {
    final now = DateTime.now().toUtc();
    return _statement(
      '''
      insert into local_history_hydration_states (
        business_id, branch_id, domain, oldest_cursor_occurred_at,
        oldest_cursor_id, has_more, last_refreshed_at, created_at, updated_at
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?)
      on conflict(business_id, branch_id, domain) do update set
        oldest_cursor_occurred_at = excluded.oldest_cursor_occurred_at,
        oldest_cursor_id = excluded.oldest_cursor_id,
        has_more = excluded.has_more,
        last_refreshed_at = case when ?
          then local_history_hydration_states.last_refreshed_at
          else excluded.last_refreshed_at
        end,
        updated_at = excluded.updated_at
      ''',
      [
        businessId,
        branchId,
        domain,
        cursor?.occurredAt,
        cursor?.id,
        hasMore,
        lastRefreshedAt,
        now,
        now,
        preserveLastRefreshedAt,
      ],
    );
  }

  InventoryHistoryCursor? _cursor(Map<String, Object?>? state) {
    final occurredAt = _asDateTime(state?['oldest_cursor_occurred_at']);
    final id = state?['oldest_cursor_id']?.toString();
    if (occurredAt == null || id == null || id.isEmpty) return null;
    return InventoryHistoryCursor(occurredAt: occurredAt, id: id);
  }

  Future<void> _statement(String sql, List<Object?> parameters) {
    return _db.customStatement(
      sql,
      normalizeSqliteParameters(parameters),
    );
  }
}

DateTime? _asDateTime(Object? value) {
  return parseInventoryHistoryTimestamp(value);
}

bool _asBool(Object? value) => value == true || value == 1;
