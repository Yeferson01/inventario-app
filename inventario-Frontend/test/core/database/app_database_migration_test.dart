import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_seen_record_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/reconciliation_issue_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';

void main() {
  test('migrates schema 8 to 9 without replacing existing balance IDs',
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

    expect(database.schemaVersion, 9);
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

    final recoveryTables = await database.customSelect(
      '''
      select name from sqlite_master
      where type = 'table' and name in (
        'local_operational_bootstrap_checkpoints',
        'local_operational_bootstrap_seen_records',
        'local_reconciliation_issues',
        'local_authorized_operational_contexts'
      )
      ''',
    ).get();
    expect(recoveryTables, hasLength(4));

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

const _schema8SetupStatements = <String>[
  'pragma user_version = 8',
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
    sync_status integer not null default 0,
    local_status text not null default 'dirty', created_at integer not null
  )
  ''',
];
