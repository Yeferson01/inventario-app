import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_seen_record_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/reconciliation_issue_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';

void main() {
  test('migrates 16 to 17 preserving existing data and enabling graph FK',
      () async {
    final source = AppDatabase.executor(NativeDatabase.memory());
    await source.customStatement(
        "insert into businesses (id, name) values ('prior-business', 'Prior')");
    final schemaRows = await source.customSelect('''
      select sql from sqlite_master
      where sql is not null and name not like 'sqlite_%'
        and tbl_name <> 'local_sync_batch_dependencies'
      order by case type when 'table' then 0 when 'index' then 1
                         when 'trigger' then 2 else 3 end, rowid
    ''').get();
    final statements = schemaRows
        .map((row) => row.read<String>('sql'))
        .toList(growable: false);
    await source.close();

    final database = AppDatabase.executor(NativeDatabase.memory(
      setup: (raw) {
        for (final statement in statements) {
          raw.execute(statement);
        }
        raw.execute(
            "insert into businesses (id, name) values ('prior-business', 'Prior')");
        raw.execute('pragma user_version = 16');
      },
    ));
    addTearDown(database.close);
    final business = await database
        .customSelect("select name from businesses where id = 'prior-business'")
        .getSingle();
    expect(business.read<String>('name'), 'Prior');
    expect(database.schemaVersion, 17);
    expect(await _columnNames(database, 'local_sync_batch_dependencies'),
        contains('completion_snapshot_id'));
    final fk = await database.customSelect('pragma foreign_keys').getSingle();
    expect(fk.read<int>('foreign_keys'), 1);
  });
  test('migrates schema 8 to 17 without replacing existing balance IDs',
      () async {
    final executor = NativeDatabase.memory(
      setup: (rawDatabase) {
        for (final statement in _schema8SetupStatements) {
          rawDatabase.execute(statement);
        }
      },
    );
    final database = AppDatabase.executor(executor);

    addTearDown(database.close);

    final balance = await database.customSelect(
      'select * from local_product_stock_balances where id = ?',
      variables: [const Variable<String>('random-local-uuid')],
    ).getSingle();

    expect(database.schemaVersion, 17);
    expect(
        await _columnNames(database, 'local_sync_batch_dependencies'),
        containsAll([
          'prerequisite_mutation_id',
          'dependent_batch_id',
          'relation_type',
          'completion_snapshot_id',
          'created_at'
        ]));
    expect(
        await _columnNames(database, 'purchases'),
        containsAll([
          'total_cents',
          'financial_finalized_at',
          'monetary_contract_version'
        ]));
    expect(await _columnNames(database, 'purchase_items'),
        containsAll(['unit_cost_cents', 'subtotal_cents']));
    final legacyPurchase = await database
        .customSelect(
          "select total_cents, financial_finalized_at from purchases where id = 'legacy-purchase'",
        )
        .getSingle();
    expect(legacyPurchase.readNullable<int>('total_cents'), isNull);
    expect(legacyPurchase.readNullable<DateTime>('financial_finalized_at'),
        isNull);
    expect(balance.read<String>('id'), 'random-local-uuid');
    expect(balance.read<int>('quantity_on_hand'), 8);

    final balanceColumns = await _columnNames(
      database,
      'local_product_stock_balances',
    );
    expect(
      balanceColumns,
      containsAll(<String>{
        'remote_balance_id',
        'remote_quantity_on_hand',
        'remote_quantity_reserved',
        'remote_quantity_available',
        'remote_average_cost',
        'remote_snapshot_id',
        'deleted_at',
      }),
    );

    final saleItemColumns = await _columnNames(database, 'sale_items');
    expect(saleItemColumns, contains('deleted_at'));
    expect(saleItemColumns, contains('unit_cost_snapshot'));
    final legacySaleItem = await database.customSelect(
      'select unit_cost_snapshot from sale_items where id = ?',
      variables: [const Variable<String>('legacy-sale-item')],
    ).getSingle();
    expect(legacySaleItem.readNullable<double>('unit_cost_snapshot'), isNull);
    final productColumns = await _columnNames(database, 'products');
    expect(productColumns, contains('master_product_id'));
    final movementColumns =
        await _columnNames(database, 'local_inventory_movements');
    expect(
      movementColumns,
      containsAll(<String>{
        'previous_stock',
        'new_stock',
        'created_by',
        'device_id',
        'reversed_movement_id',
      }),
    );

    final recoveryTables = await database.customSelect(
      '''
      select name from sqlite_master
      where type = 'table' and name in (
        'local_operational_bootstrap_checkpoints',
        'local_operational_bootstrap_seen_records',
        'local_reconciliation_issues',
        'local_authorized_operational_contexts',
        'local_history_hydration_states',
        'local_report_snapshots'
      )
      ''',
    ).get();
    expect(recoveryTables, hasLength(6));
    expect(
      await _columnNames(database, 'local_reconciliation_issues'),
      containsAll(<String>{
        'sale_id',
        'cash_register_id',
        'cash_session_id',
        'scope_resolution_status',
        'scope_evidence_type',
      }),
    );

    final reportColumns =
        await _columnNames(database, 'local_report_snapshots');
    expect(
      reportColumns,
      containsAll(<String>{
        'profile_id',
        'business_id',
        'branch_id',
        'report_type',
        'filter_key',
        'payload_json',
        'authorization_validated_at',
        'capability_fingerprint',
      }),
    );
    await _verifyRecoveryDaosAfterMigration(database);

    await expectLater(
      database.customStatement(
        '''
        insert into local_product_stock_balances (
          id, business_id, branch_id, product_id
        ) values (?, ?, ?, ?)
        ''',
        const ['second-id', 'business-a', 'branch-x', 'product-p'],
      ),
      throwsA(anything),
    );
  });

  test('migrates current schema 12 to 17 additively', () async {
    final executor = NativeDatabase.memory(
      setup: (rawDatabase) {
        for (final statement in _schema10CostSetupStatements) {
          rawDatabase.execute(statement);
        }
        for (final statement in _schema12UpgradeStatements) {
          rawDatabase.execute(statement);
        }
      },
    );
    final database = AppDatabase.executor(executor);
    addTearDown(database.close);

    expect(database.schemaVersion, 17);
    expect(
      await _columnNames(database, 'local_report_snapshots'),
      containsAll(<String>{
        'profile_id',
        'business_id',
        'branch_id',
        'report_type',
        'filter_key',
        'payload_json',
      }),
    );
    final legacyMovement = await database.customSelect(
      'select id, quantity_change from local_inventory_movements where id = ?',
      variables: [const Variable<String>('legacy-movement')],
    ).getSingle();
    expect(legacyMovement.read<String>('id'), 'legacy-movement');
    expect(legacyMovement.read<int>('quantity_change'), 4);
  });
  test('migrates historical schema 13 to 17 preserving report snapshots',
      () async {
    final database = AppDatabase.executor(NativeDatabase.memory(
      setup: (rawDatabase) {
        for (final statement in _schema10CostSetupStatements.where(
          (statement) => statement != 'pragma user_version = 10',
        )) {
          rawDatabase.execute(statement);
        }
        for (final statement in _schema12UpgradeStatements.where(
          (statement) => statement != 'pragma user_version = 12',
        )) {
          rawDatabase.execute(statement);
        }
        for (final statement in _schema13UpgradeStatements) {
          rawDatabase.execute(statement);
        }
      },
    ));
    addTearDown(database.close);

    expect(database.schemaVersion, 17);
    final report = await database.customSelect('''
      select payload_json from local_report_snapshots where id = 'legacy-report'
    ''').getSingle();
    expect(report.read<String>('payload_json'), '{}');
    expect(await database.select(database.localCashMovements).get(), isEmpty);
    final version =
        await database.customSelect('pragma user_version').getSingle();
    expect(version.read<int>('user_version'), 17);
  });
  test('migrates schema 9 to 17 preserving Product identity', () async {
    final executor = NativeDatabase.memory(
      setup: (rawDatabase) {
        for (final statement in _schema9IdentitySetupStatements) {
          rawDatabase.execute(statement);
        }
      },
    );
    final database = AppDatabase.executor(executor);
    addTearDown(database.close);

    expect(database.schemaVersion, 17);
    final product = await database.customSelect(
      'select id, name, master_product_id from products where id = ?',
      variables: [const Variable<String>('legacy-product')],
    ).getSingle();
    expect(product.read<String>('id'), 'legacy-product');
    expect(product.read<String>('name'), 'Legacy Product');
    expect(product.readNullable<String>('master_product_id'), isNull);

    final indexes = await database.customSelect(
      '''
      select name from sqlite_master
      where type = 'index'
        and name in (
          'idx_products_business_master_product',
          'idx_local_product_barcodes_business_lookup',
          'idx_local_product_barcodes_global_lookup'
        )
      ''',
    ).get();
    expect(indexes, hasLength(3));
  });

  test('HY-28 migrates schema 10 to 17 preserving existing movements',
      () async {
    final executor = NativeDatabase.memory(
      setup: (rawDatabase) {
        for (final statement in _schema10CostSetupStatements) {
          rawDatabase.execute(statement);
        }
      },
    );
    final database = AppDatabase.executor(executor);
    addTearDown(database.close);

    expect(database.schemaVersion, 17);
    final legacySaleItem = await database.customSelect(
      'select unit_cost_snapshot from sale_items where id = ?',
      variables: [const Variable<String>('legacy-sale-item')],
    ).getSingle();
    expect(legacySaleItem.readNullable<double>('unit_cost_snapshot'), isNull);
    final movement = await database.customSelect(
      'select * from local_inventory_movements where id = ?',
      variables: [const Variable<String>('legacy-movement')],
    ).getSingle();
    expect(movement.read<String>('idempotency_key'), 'legacy-key');
    expect(movement.read<int>('quantity_change'), 4);
    expect(movement.readNullable<int>('previous_stock'), isNull);
    expect(movement.readNullable<String>('device_id'), isNull);
  });

  test('enables SQLite foreign keys on every AppDatabase connection', () async {
    final database = AppDatabase.executor(NativeDatabase.memory());
    addTearDown(database.close);

    final row = await database.customSelect('pragma foreign_keys').getSingle();

    expect(row.data.values.single, 1);
  });
}

Future<void> _verifyRecoveryDaosAfterMigration(AppDatabase database) async {
  const scope = OperationalBootstrapScope(
    profileId: 'profile-p',
    businessId: 'business-a',
    branchId: 'branch-x',
    appDeviceId: 'device-d',
    bundle: 'product_operational',
    dataset: 'products',
  );
  final now = DateTime.utc(2026, 8, 15);
  final checkpoints = OperationalBootstrapCheckpointLocalDao(database);
  await checkpoints.beginOrRestart(
    scope: scope,
    snapshotId: 'snapshot-1',
    snapshotAt: now,
    authorizationValidatedAt: now,
  );
  expect((await checkpoints.get(scope))?['status'], 'started');

  final seen = OperationalBootstrapSeenRecordLocalDao(database);
  const record = SeenRecordDraft(
    snapshotId: 'snapshot-1',
    profileId: 'profile-p',
    businessId: 'business-a',
    branchId: 'branch-x',
    bundle: 'product_operational',
    dataset: 'products',
    entityId: 'product-p',
  );
  await seen.recordSeen(record);
  expect(await seen.exists(record), isTrue);

  final issues = ReconciliationIssueLocalDao(database);
  await issues.openIssue(
    const ReconciliationIssueDraft(
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-x',
      domain: 'inventory',
      issueType: 'missing_source_item_id',
      severity: 'blocking',
      message: 'missing source item',
    ),
  );
  expect(
    await issues.getOpenBlockingIssues(
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-x',
    ),
    hasLength(1),
  );

  final contexts = AuthorizedOperationalContextLocalDao(database);
  await contexts.replaceContext(
    AuthorizedOperationalContextProjection(
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-x',
      effectivePermissions: const ['inventory.read'],
      effectiveRoles: const ['cashier'],
      applicableMembershipIds: const ['membership-1'],
      authorizationValidatedAt: now,
      snapshotId: 'snapshot-1',
    ),
  );
  expect(
    await contexts.getEffectivePermissions(
      profileId: 'profile-p',
      businessId: 'business-a',
      branchId: 'branch-x',
    ),
    ['inventory.read'],
  );
}

Future<Set<String>> _columnNames(AppDatabase database, String table) async {
  final rows = await database.customSelect('pragma table_info($table)').get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

const _schema12UpgradeStatements = <String>[
  'alter table sale_items add column unit_cost_snapshot real',
  'alter table local_inventory_movements add column previous_stock integer',
  'alter table local_inventory_movements add column new_stock integer',
  'alter table local_inventory_movements add column created_by text',
  'alter table local_inventory_movements add column device_id text',
  'alter table local_inventory_movements add column reversed_movement_id text',
  '''
  create table local_history_hydration_states (
    business_id text not null,
    branch_id text not null,
    domain text not null,
    oldest_cursor_occurred_at integer,
    oldest_cursor_id text,
    has_more integer not null default 1,
    last_refreshed_at integer,
    created_at integer not null,
    updated_at integer not null,
    primary key (business_id, branch_id, domain)
  )
  ''',
  'pragma user_version = 12',
];
const _schema13UpgradeStatements = <String>[
  '''
  create table local_report_snapshots (
    id text primary key not null,
    profile_id text not null,
    business_id text not null,
    branch_id text not null,
    report_type text not null,
    filter_key text not null,
    payload_json text not null,
    fetched_at integer not null,
    authoritative_as_of integer not null,
    authorization_validated_at integer not null,
    capability_fingerprint text not null,
    includes_sensitive_data integer not null default 0,
    includes_costs integer not null default 0,
    created_at integer not null,
    updated_at integer not null
  )
  ''',
  '''
  create unique index ux_local_report_snapshots_scope
  on local_report_snapshots (
    profile_id, business_id, branch_id, report_type, filter_key
  )
  ''',
  '''
  create index idx_local_report_snapshots_authorization
  on local_report_snapshots (
    profile_id, business_id, branch_id, authorization_validated_at
  )
  ''',
  '''
  insert into local_report_snapshots (
    id, profile_id, business_id, branch_id, report_type, filter_key,
    payload_json, fetched_at, authoritative_as_of,
    authorization_validated_at, capability_fingerprint, created_at, updated_at
  ) values (
    'legacy-report', 'profile-p', 'business-a', 'branch-x', 'sales_summary',
    'period-day', '{}', 1, 1, 1, 'reports.sales', 1, 1
  )
  ''',
  'pragma user_version = 13',
];
const _schema8SetupStatements = <String>[
  'pragma user_version = 8',
  'create table purchases (id text primary key not null, total real not null)',
  "insert into purchases (id, total) values ('legacy-purchase', 19.99)",
  'create table purchase_items (id text primary key not null, unit_cost real not null, subtotal real not null)',
  '''
  create table local_product_stock_balances (
    id text primary key not null,
    business_id text not null,
    branch_id text not null,
    product_id text not null,
    quantity_on_hand integer not null default 0,
    quantity_reserved integer not null default 0,
    quantity_available integer not null default 0,
    average_cost real,
    last_movement_at integer,
    remote_updated_at integer,
    last_synced_at integer,
    sync_status text not null default 'synced',
    metadata_json text,
    created_at integer not null,
    updated_at integer not null
  )
  ''',
  '''
  insert into local_product_stock_balances (
    id, business_id, branch_id, product_id, quantity_on_hand,
    quantity_available, created_at, updated_at
  ) values (
    'random-local-uuid', 'business-a', 'branch-x', 'product-p', 8, 8, 1, 1
  )
  ''',
  '''
  create unique index ux_local_product_stock_balances_scope
  on local_product_stock_balances (business_id, branch_id, product_id)
  ''',
  '''
  create table sale_items (
    id text primary key not null,
    sale_id text,
    product_id text,
    created_at integer not null,
    updated_at integer not null
  )
  ''',
  '''
  insert into sale_items (id, created_at, updated_at)
  values ('legacy-sale-item', 1, 1)
  ''',
  '''
  create table cash_registers (
    id text primary key not null, business_id text not null, branch_id text,
    idempotency_key text
  )
  ''',
  '''
  create table cash_sessions (
    id text primary key not null, business_id text not null, branch_id text,
    cash_register_id text not null, status text not null, opened_at integer,
    idempotency_key text, deleted_at integer
  )
  ''',
  '''
  create table sales (
    id text primary key not null, business_id text, branch_id text,
    created_at integer not null, cash_session_id text, idempotency_key text
  )
  ''',
  '''
  create table sale_payments (
    id text primary key not null, sale_id text not null, business_id text not null,
    branch_id text, created_at integer not null
  )
  ''',
  '''
  create table local_inventory_movements (
    id text primary key not null, idempotency_key text not null,
    business_id text not null, branch_id text, product_id text not null,
    movement_type text not null default 'purchase',
    quantity_change integer not null default 0,
    unit_cost real,
    sync_status integer not null default 0,
    local_status text not null default 'dirty',
    occurred_at integer not null default 1,
    created_at integer not null
  )
  ''',
  '''
  insert into local_inventory_movements (
    id, idempotency_key, business_id, branch_id, product_id,
    movement_type, quantity_change, occurred_at, created_at
  ) values (
    'legacy-movement', 'legacy-key', 'business-a', 'branch-x', 'product-p',
    'purchase', 4, 1, 1
  )
  ''',
  '''
  create table products (
    id text primary key not null,
    business_id text,
    category_id text,
    barcode text,
    name text not null,
    description text,
    purchase_price real not null default 0,
    sale_price real not null,
    stock_quantity integer not null default 0,
    minimum_stock integer not null default 0,
    unit text not null default 'unidad',
    status text not null default 'active',
    created_at integer not null,
    updated_at integer not null,
    deleted_at integer,
    simple_category text,
    sync_status integer not null default 0
  )
  ''',
  '''
  insert into products (
    id, business_id, name, sale_price, created_at, updated_at
  ) values (
    'legacy-product', 'business-a', 'Legacy Product', 10, 1, 1
  )
  ''',
  '''
  create table local_product_barcodes (
    id text primary key not null,
    scope text not null,
    business_id text,
    product_id text,
    master_product_id text,
    barcode text not null,
    barcode_normalized text not null,
    barcode_type text,
    is_primary integer not null default 0,
    status text not null default 'active',
    source text,
    confidence_score real,
    sync_status text not null default 'synced',
    local_status text not null default 'clean',
    version integer not null default 1,
    created_at integer not null default 1,
    updated_at integer not null default 1,
    deleted_at integer,
    last_synced_at integer,
    metadata_json text
  )
  ''',
];

final _schema9IdentitySetupStatements = <String>[
  ..._schema8SetupStatements,
  '''
  create table local_operational_bootstrap_checkpoints (
    id text primary key not null,
    profile_id text not null,
    business_id text not null,
    branch_id text not null,
    app_device_id text not null,
    bundle text not null,
    dataset text not null
  )
  ''',
  '''
  create table local_operational_bootstrap_seen_records (
    id text primary key not null,
    snapshot_id text not null,
    profile_id text not null,
    business_id text not null,
    branch_id text not null,
    bundle text not null,
    dataset text not null,
    entity_id text not null
  )
  ''',
  '''
  create table local_reconciliation_issues (
    id text primary key not null,
    profile_id text not null,
    business_id text not null,
    branch_id text not null,
    domain text not null,
    entity_type text,
    entity_id text,
    status text not null,
    severity text not null
  )
  ''',
  '''
  create table local_authorized_operational_contexts (
    id text primary key not null,
    profile_id text not null,
    business_id text not null,
    branch_id text not null
  )
  ''',
  'pragma user_version = 9',
];

final _schema10CostSetupStatements = <String>[
  ..._schema9IdentitySetupStatements.where(
    (statement) => statement != 'pragma user_version = 9',
  ),
  'alter table products add column master_product_id text',
  'pragma user_version = 10',
];
