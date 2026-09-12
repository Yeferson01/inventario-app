import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/catalog/application/catalog_barcode_lookup_service.dart';
import 'package:inventario_frontend/features/catalog/data/datasources/catalog_local_dao.dart';
import 'package:inventario_frontend/features/inventory/application/business_product_creation_models.dart';
import 'package:inventario_frontend/features/inventory/application/business_product_creation_service.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_product_creation_models.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_product_creation_service.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_product_from_master_sync_service.dart';
import 'package:inventario_frontend/features/sync/application/local_sync_outbox_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/local_sync_outbox_dao.dart';

void main() {
  late AppDatabase database;
  late BusinessProductCreationService service;

  const context = BusinessProductCreationContext(
    businessId: 'business-a',
    branchId: 'branch-a',
    profileId: 'profile-a',
    appDeviceId: 'device-a',
    deviceInstallationId: 'installation-a',
    effectivePermissions: {'products.create', 'products.update'},
  );

  setUp(() async {
    database = AppDatabase.executor(NativeDatabase.memory());
    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(
            id: 'business-a',
            name: 'Business A',
          ),
        );

    final catalogDao = CatalogLocalDao(database);
    final creationService = InventoryProductCreationService(database);
    final outboxService = LocalSyncOutboxService(LocalSyncOutboxDao(database));
    service = BusinessProductCreationService(
      barcodeLookupService: CatalogBarcodeLookupService(
        lookupByBarcode: catalogDao.lookupByBarcode,
      ),
      productSyncService: InventoryProductFromMasterSyncService(
        database: database,
        productCreationService: creationService,
        outboxService: outboxService,
      ),
    );
  });

  tearDown(() => database.close());

  test('business code creates once and a retry returns the existing Product',
      () async {
    final first = await service.createOrUse(
      context: context,
      code: 'ARROZ-001',
      fields: const BusinessProductOwnedFields(
        name: 'Arroz local',
        purchasePrice: 4,
        salePrice: 6,
        minimumStock: 3,
      ),
    );
    final second = await service.createOrUse(
      context: const BusinessProductCreationContext(
        businessId: 'business-a',
        branchId: 'branch-a',
        profileId: 'profile-a',
        deviceInstallationId: 'installation-a',
        effectivePermissions: {},
      ),
      code: 'arroz 001',
      fields: const BusinessProductOwnedFields(
        name: 'No debe crearse',
        purchasePrice: 10,
        salePrice: 20,
      ),
    );

    expect(first.outcome, BusinessProductCreationOutcome.createdManual);
    expect(first.masterProductId, isNull);
    expect(first.outboxMutationCount, 2);
    expect(second.outcome, BusinessProductCreationOutcome.existing);
    expect(second.productId, first.productId);
    expect(await database.select(database.products).get(), hasLength(1));
    expect(
      await database.select(database.localProductBarcodes).get(),
      hasLength(1),
    );
    final batchCount = await database
        .customSelect('select count(*) as total from local_sync_batches')
        .getSingle();
    expect(batchCount.read<int>('total'), 1);
  });

  test('master match persists master identity and business-owned fields',
      () async {
    await database.into(database.localMasterProductsCatalog).insert(
          LocalMasterProductsCatalogCompanion.insert(
            id: 'master-a',
            name: const Value('Arroz maestro'),
            brand: const Value('Marca global'),
            packageSize: const Value(500),
            packageUnit: const Value('g'),
          ),
        );
    await database.customStatement(
      '''
      insert into local_product_barcodes (
        id, scope, master_product_id, barcode, barcode_normalized,
        barcode_type, is_primary, status, source
      ) values (?, 'global', ?, ?, ?, 'ean13', 1, 'active', 'test')
      ''',
      ['global-a', 'master-a', '7701234567890', '7701234567890'],
    );

    final result = await service.createOrUse(
      context: context,
      code: '7701234567890',
      fields: const BusinessProductOwnedFields(
        name: 'Arroz del negocio',
        purchasePrice: 7,
        salePrice: 9,
        minimumStock: 5,
        unit: 'bolsa',
      ),
    );

    final product = await (database.select(database.products)
          ..where((row) => row.id.equals(result.productId!)))
        .getSingle();
    final businessCode = await (database.select(database.localProductBarcodes)
          ..where((row) => row.scope.equals('business')))
        .getSingle();
    final mutationOrder = await database.customSelect(
      '''
      select entity_table
      from local_sync_mutations
      order by client_sequence asc
      ''',
    ).get();

    expect(result.outcome, BusinessProductCreationOutcome.createdFromMaster);
    expect(result.outboxMutationCount, 2);
    expect(product.masterProductId, 'master-a');
    expect(product.name, 'Arroz del negocio');
    expect(product.minimumStock, 5);
    expect(product.purchasePrice, 7);
    expect(product.salePrice, 9);
    expect(businessCode.productId, result.productId);
    expect(businessCode.masterProductId, 'master-a');
    expect(
      mutationOrder.map((row) => row.read<String>('entity_table')).toList(),
      ['products', 'product_barcodes'],
    );
    expect(
      await database.select(database.localProductStockBalances).get(),
      isEmpty,
    );
  });

  test('alternate master codes reuse one Product per business', () async {
    await database.into(database.localMasterProductsCatalog).insert(
          LocalMasterProductsCatalogCompanion.insert(
            id: 'master-aliases',
            name: const Value('Producto con alias'),
          ),
        );
    await database.into(database.localProductBarcodes).insert(
          LocalProductBarcodesCompanion.insert(
            id: 'global-primary',
            scope: 'global',
            masterProductId: const Value('master-aliases'),
            barcode: '7701111111111',
            barcodeNormalized: '7701111111111',
            barcodeType: const Value('ean13'),
            isPrimary: const Value(true),
          ),
        );
    await database.into(database.localProductBarcodes).insert(
          LocalProductBarcodesCompanion.insert(
            id: 'global-alias',
            scope: 'global',
            masterProductId: const Value('master-aliases'),
            barcode: '7702222222222',
            barcodeNormalized: '7702222222222',
            barcodeType: const Value('ean13'),
          ),
        );

    final first = await service.createOrUse(
      context: context,
      code: '7701111111111',
      fields: const BusinessProductOwnedFields(
        name: 'Producto A',
        purchasePrice: 1,
        salePrice: 2,
      ),
    );
    final alias = await service.createOrUse(
      context: context,
      code: '7702222222222',
      fields: const BusinessProductOwnedFields(
        name: 'No debe duplicarse',
        purchasePrice: 3,
        salePrice: 4,
      ),
    );

    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(id: 'business-b', name: 'Business B'),
        );
    final otherBusiness = await service.createOrUse(
      context: const BusinessProductCreationContext(
        businessId: 'business-b',
        branchId: 'branch-b',
        profileId: 'profile-b',
        appDeviceId: 'device-b',
        deviceInstallationId: 'installation-b',
        effectivePermissions: {'products.create'},
      ),
      code: '7701111111111',
      fields: const BusinessProductOwnedFields(
        name: 'Producto B',
        purchasePrice: 5,
        salePrice: 6,
      ),
    );

    final businessAProducts = await (database.select(database.products)
          ..where((row) => row.businessId.equals('business-a')))
        .get();
    final businessBProducts = await (database.select(database.products)
          ..where((row) => row.businessId.equals('business-b')))
        .get();
    final batchCount = await database
        .customSelect('select count(*) as total from local_sync_batches')
        .getSingle();

    expect(first.outcome, BusinessProductCreationOutcome.createdFromMaster);
    expect(alias.outcome, BusinessProductCreationOutcome.existing);
    expect(alias.productId, first.productId);
    expect(businessAProducts, hasLength(1));
    expect(businessAProducts.single.stockQuantity, 0);
    expect(otherBusiness.outcome,
        BusinessProductCreationOutcome.createdFromMaster);
    expect(otherBusiness.productId, isNot(first.productId));
    expect(businessBProducts, hasLength(1));
    expect(batchCount.read<int>('total'), 2);
    expect(
      await database.select(database.localProductStockBalances).get(),
      isEmpty,
    );
  });

  test('concurrent alternate master codes create one Product per business',
      () async {
    await _insertMasterWithBarcodes(
      database,
      masterProductId: 'master-concurrent',
      barcodes: const ['7703000000001', '7703000000002'],
    );

    final catalogDao = CatalogLocalDao(database);
    final bothLookupsStarted = Completer<void>();
    var lookupCount = 0;
    final concurrentService = _buildCreationService(
      database,
      lookupByBarcode: ({
        required businessId,
        required barcode,
        required allowMasterMatch,
      }) async {
        lookupCount++;
        if (lookupCount == 2) {
          bothLookupsStarted.complete();
        }
        await bothLookupsStarted.future;
        return catalogDao.lookupByBarcode(
          businessId: businessId,
          barcode: barcode,
          allowMasterMatch: allowMasterMatch,
        );
      },
    );

    final results = await Future.wait([
      concurrentService.createOrUse(
        context: context,
        code: '7703000000001',
        fields: const BusinessProductOwnedFields(
          name: 'Ganador A',
          purchasePrice: 1,
          salePrice: 2,
        ),
        clientSequenceStart: 100,
      ),
      concurrentService.createOrUse(
        context: context,
        code: '7703000000002',
        fields: const BusinessProductOwnedFields(
          name: 'Ganador B',
          purchasePrice: 3,
          salePrice: 4,
        ),
        clientSequenceStart: 200,
      ),
    ]);

    final products = await (database.select(database.products)
          ..where(
            (row) =>
                row.businessId.equals('business-a') &
                row.masterProductId.equals('master-concurrent'),
          ))
        .get();
    final businessBarcodes = await (database.select(
      database.localProductBarcodes,
    )..where((row) => row.scope.equals('business')))
        .get();

    expect(products, hasLength(1));
    expect(results.map((result) => result.productId).toSet(), {
      products.single.id,
    });
    expect(results.map((result) => result.barcode).toSet(), {
      '7703000000001',
      '7703000000002',
    });
    expect(
      results.map((result) => result.outcome).toSet(),
      {
        BusinessProductCreationOutcome.createdFromMaster,
        BusinessProductCreationOutcome.existing,
      },
    );
    expect(businessBarcodes, hasLength(1));
    expect(businessBarcodes.single.productId, products.single.id);
  });

  test('different masters are not serialized behind one global lock', () async {
    await _insertMasterWithBarcodes(
      database,
      masterProductId: 'master-parallel-a',
      barcodes: const ['7704000000001'],
    );
    await _insertMasterWithBarcodes(
      database,
      masterProductId: 'master-parallel-b',
      barcodes: const ['7704000000002'],
    );

    final bothCreatesStarted = Completer<void>();
    final releaseCreates = Completer<void>();
    var createCount = 0;
    final concurrentService = _buildCreationService(
      database,
      beforeCreate: (_) async {
        createCount++;
        if (createCount == 2) {
          bothCreatesStarted.complete();
        }
        await releaseCreates.future;
      },
    );

    final first = concurrentService.createOrUse(
      context: context,
      code: '7704000000001',
      fields: const BusinessProductOwnedFields(
        name: 'Master paralelo A',
        purchasePrice: 1,
        salePrice: 2,
      ),
    );
    final second = concurrentService.createOrUse(
      context: context,
      code: '7704000000002',
      fields: const BusinessProductOwnedFields(
        name: 'Master paralelo B',
        purchasePrice: 1,
        salePrice: 2,
      ),
    );

    final enteredIndependently = await _completesBeforeRelease(
      bothCreatesStarted,
      releaseCreates,
    );
    final results = await Future.wait([first, second]);

    expect(enteredIndependently, isTrue);
    expect(
      results.every(
        (result) =>
            result.outcome == BusinessProductCreationOutcome.createdFromMaster,
      ),
      isTrue,
    );
  });

  test('the same master in different businesses uses independent locks',
      () async {
    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(id: 'business-b', name: 'Business B'),
        );
    await _insertMasterWithBarcodes(
      database,
      masterProductId: 'master-shared-parallel',
      barcodes: const ['7705000000001'],
    );

    final bothCreatesStarted = Completer<void>();
    final releaseCreates = Completer<void>();
    var createCount = 0;
    final concurrentService = _buildCreationService(
      database,
      beforeCreate: (_) async {
        createCount++;
        if (createCount == 2) {
          bothCreatesStarted.complete();
        }
        await releaseCreates.future;
      },
    );
    const otherContext = BusinessProductCreationContext(
      businessId: 'business-b',
      branchId: 'branch-b',
      profileId: 'profile-b',
      appDeviceId: 'device-b',
      deviceInstallationId: 'installation-b',
      effectivePermissions: {'products.create'},
    );

    final first = concurrentService.createOrUse(
      context: context,
      code: '7705000000001',
      fields: const BusinessProductOwnedFields(
        name: 'Producto A',
        purchasePrice: 1,
        salePrice: 2,
      ),
    );
    final second = concurrentService.createOrUse(
      context: otherContext,
      code: '7705000000001',
      fields: const BusinessProductOwnedFields(
        name: 'Producto B',
        purchasePrice: 1,
        salePrice: 2,
      ),
    );

    final enteredIndependently = await _completesBeforeRelease(
      bothCreatesStarted,
      releaseCreates,
    );
    final results = await Future.wait([first, second]);

    expect(enteredIndependently, isTrue);
    expect(results.map((result) => result.productId).toSet(), hasLength(2));
    expect(await database.select(database.products).get(), hasLength(2));
  });

  test('a failed master creation releases its keyed lock for retry', () async {
    await _insertMasterWithBarcodes(
      database,
      masterProductId: 'master-retry',
      barcodes: const ['7706000000001'],
    );

    var shouldFail = true;
    final retryService = _buildCreationService(
      database,
      beforeCreate: (_) async {
        if (shouldFail) {
          shouldFail = false;
          throw StateError('controlled first failure');
        }
      },
    );
    const fields = BusinessProductOwnedFields(
      name: 'Producto retry',
      purchasePrice: 1,
      salePrice: 2,
    );

    final failed = await retryService.createOrUse(
      context: context,
      code: '7706000000001',
      fields: fields,
    );
    final retried = await retryService.createOrUse(
      context: context,
      code: '7706000000001',
      fields: fields,
    );

    expect(
      failed.outcome,
      BusinessProductCreationOutcome.localPersistenceFailure,
    );
    expect(retried.outcome, BusinessProductCreationOutcome.createdFromMaster);
    expect(await database.select(database.products).get(), hasLength(1));
  });

  test(
      'manual Product without code is immediately local and queues Product only',
      () async {
    final result = await service.createOrUse(
      context: context,
      fields: const BusinessProductOwnedFields(
        name: 'Servicio sin código',
        purchasePrice: 1,
        salePrice: 2,
      ),
    );

    expect(result.outcome, BusinessProductCreationOutcome.createdManual);
    expect(result.barcode, isNull);
    expect(result.outboxMutationCount, 1);
    expect(
      await (database.select(database.products)
            ..where((row) => row.id.equals(result.productId!)))
          .getSingleOrNull(),
      isNotNull,
    );
    expect(await database.select(database.localProductBarcodes).get(), isEmpty);
  });

  test('new creation and manual-to-master link use effective permissions',
      () async {
    final denied = await service.createOrUse(
      context: const BusinessProductCreationContext(
        businessId: 'business-a',
        branchId: 'branch-a',
        profileId: 'profile-a',
        deviceInstallationId: 'installation-a',
        effectivePermissions: {},
      ),
      code: 'NEW-001',
      fields: const BusinessProductOwnedFields(
        name: 'Nuevo',
        purchasePrice: 1,
        salePrice: 2,
      ),
    );
    expect(denied.outcome, BusinessProductCreationOutcome.permissionDenied);
    expect(await database.select(database.products).get(), isEmpty);

    final manual = await service.createOrUse(
      context: context,
      fields: const BusinessProductOwnedFields(
        name: 'Producto por vincular',
        purchasePrice: 1,
        salePrice: 2,
      ),
    );
    await database.into(database.localMasterProductsCatalog).insert(
          LocalMasterProductsCatalogCompanion.insert(
            id: 'master-link',
            name: const Value('Master para vínculo'),
          ),
        );

    final deniedLink = await service.linkExistingProductToMaster(
      context: const BusinessProductCreationContext(
        businessId: 'business-a',
        branchId: 'branch-a',
        profileId: 'profile-a',
        deviceInstallationId: 'installation-a',
        effectivePermissions: {'products.create'},
      ),
      productId: manual.productId!,
      masterProductId: 'master-link',
    );
    final linked = await service.linkExistingProductToMaster(
      context: context,
      productId: manual.productId!,
      masterProductId: 'master-link',
    );

    expect(
      deniedLink.outcome,
      BusinessProductCreationOutcome.permissionDenied,
    );
    expect(
      linked.outcome,
      BusinessProductCreationOutcome.linkedExistingProduct,
    );
    expect(linked.productId, manual.productId);
    expect(linked.masterProductId, 'master-link');
  });

  test('minimum stock update is local, scoped and queued once', () async {
    await database.into(database.products).insert(
          ProductsCompanion.insert(
            id: 'product-a',
            businessId: const Value('business-a'),
            name: 'Arroz',
            salePrice: 10,
            minimumStock: const Value(2),
          ),
        );

    const input = BusinessProductMinimumStockUpdateInput(
      context: context,
      productId: 'product-a',
      minimumStock: 5,
    );
    final result = await service.updateMinimumStock(input);
    final product = await (database.select(database.products)
          ..where((row) => row.id.equals('product-a')))
        .getSingle();
    final mutation = await database
        .customSelect(
          'select * from local_sync_mutations',
        )
        .getSingle();
    final batch = await database
        .customSelect(
          'select * from local_sync_batches',
        )
        .getSingle();
    final payload = jsonDecode(mutation.read<String>('payload_json'))
        as Map<String, dynamic>;
    final beforePayload =
        jsonDecode(mutation.read<String>('before_payload_json'))
            as Map<String, dynamic>;

    expect(result.outcome, BusinessProductMinimumStockUpdateOutcome.updated);
    expect(result.outboxMutationCount, 1);
    expect(product.minimumStock, 5);
    expect(product.syncStatus, SyncStatus.pendingUpdate);
    expect(mutation.read<String>('entity_table'), 'products');
    expect(mutation.read<String>('entity_id'), 'product-a');
    expect(mutation.read<String>('operation'), 'update');
    expect(mutation.read<String>('business_id'), 'business-a');
    expect(mutation.read<String>('branch_id'), 'branch-a');
    expect(mutation.read<String>('profile_id'), 'profile-a');
    expect(mutation.read<String>('app_device_id'), 'device-a');
    expect(payload['minimum_stock'], 5);
    expect(beforePayload['minimum_stock'], 2);
    expect(batch.read<String>('domain'), 'catalog');

    final unchanged = await service.updateMinimumStock(input);
    expect(
      unchanged.outcome,
      BusinessProductMinimumStockUpdateOutcome.unchanged,
    );
    expect(
      (await database
              .customSelect(
                'select count(*) as mutation_count from local_sync_mutations',
              )
              .getSingle())
          .read<int>('mutation_count'),
      1,
    );
  });

  test('minimum stock update rejects invalid, unauthorized and cross-business',
      () async {
    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(id: 'business-b', name: 'Business B'),
        );
    await database.into(database.products).insert(
          ProductsCompanion.insert(
            id: 'product-b',
            businessId: const Value('business-b'),
            name: 'Producto B',
            salePrice: 10,
            minimumStock: const Value(9),
          ),
        );

    final invalid = await service.updateMinimumStock(
      const BusinessProductMinimumStockUpdateInput(
        context: context,
        productId: 'product-b',
        minimumStock: -1,
      ),
    );
    final denied = await service.updateMinimumStock(
      const BusinessProductMinimumStockUpdateInput(
        context: BusinessProductCreationContext(
          businessId: 'business-a',
          branchId: 'branch-a',
          profileId: 'profile-a',
          deviceInstallationId: 'installation-a',
          effectivePermissions: {},
        ),
        productId: 'product-b',
        minimumStock: 4,
      ),
    );
    final crossBusiness = await service.updateMinimumStock(
      const BusinessProductMinimumStockUpdateInput(
        context: context,
        productId: 'product-b',
        minimumStock: 4,
      ),
    );
    final productB = await (database.select(database.products)
          ..where((row) => row.id.equals('product-b')))
        .getSingle();

    expect(
      invalid.outcome,
      BusinessProductMinimumStockUpdateOutcome.validationFailure,
    );
    expect(
      denied.outcome,
      BusinessProductMinimumStockUpdateOutcome.permissionDenied,
    );
    expect(
      crossBusiness.outcome,
      BusinessProductMinimumStockUpdateOutcome.notFound,
    );
    expect(productB.minimumStock, 9);
    expect(await database.select(database.localSyncBatches).get(), isEmpty);
  });
}

BusinessProductCreationService _buildCreationService(
  AppDatabase database, {
  CatalogLocalLookupFn? lookupByBarcode,
  Future<void> Function(CreateProductFromMasterInput input)? beforeCreate,
}) {
  final catalogDao = CatalogLocalDao(database);
  final creationService = InventoryProductCreationService(database);
  final outboxService = LocalSyncOutboxService(LocalSyncOutboxDao(database));
  final syncService = _ControlledProductSyncService(
    database: database,
    productCreationService: creationService,
    outboxService: outboxService,
    beforeCreate: beforeCreate,
  );

  return BusinessProductCreationService(
    barcodeLookupService: CatalogBarcodeLookupService(
      lookupByBarcode: lookupByBarcode ?? catalogDao.lookupByBarcode,
    ),
    productSyncService: syncService,
  );
}

Future<void> _insertMasterWithBarcodes(
  AppDatabase database, {
  required String masterProductId,
  required List<String> barcodes,
}) async {
  await database.into(database.localMasterProductsCatalog).insert(
        LocalMasterProductsCatalogCompanion.insert(
          id: masterProductId,
          name: Value('Master $masterProductId'),
        ),
      );
  for (var index = 0; index < barcodes.length; index++) {
    final barcode = barcodes[index];
    await database.into(database.localProductBarcodes).insert(
          LocalProductBarcodesCompanion.insert(
            id: 'global-$masterProductId-$index',
            scope: 'global',
            masterProductId: Value(masterProductId),
            barcode: barcode,
            barcodeNormalized: barcode,
            barcodeType: const Value('ean13'),
            isPrimary: Value(index == 0),
          ),
        );
  }
}

Future<bool> _completesBeforeRelease(
  Completer<void> entered,
  Completer<void> release,
) async {
  var completed = false;
  try {
    await entered.future.timeout(const Duration(seconds: 2));
    completed = true;
  } on TimeoutException {
    completed = false;
  } finally {
    if (!release.isCompleted) {
      release.complete();
    }
  }
  return completed;
}

class _ControlledProductSyncService
    extends InventoryProductFromMasterSyncService {
  _ControlledProductSyncService({
    required super.database,
    required super.productCreationService,
    required super.outboxService,
    this.beforeCreate,
  });

  final Future<void> Function(CreateProductFromMasterInput input)? beforeCreate;

  @override
  Future<InventoryProductFromMasterSyncResult> createProductAndQueueSync(
    CreateProductFromMasterInput input,
  ) async {
    await beforeCreate?.call(input);
    return super.createProductAndQueueSync(input);
  }
}
