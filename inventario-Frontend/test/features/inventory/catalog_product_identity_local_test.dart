import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/catalog/data/datasources/catalog_local_dao.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_product_creation_models.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_product_creation_service.dart';

void main() {
  late AppDatabase database;
  late InventoryProductCreationService creationService;
  late CatalogLocalDao catalogDao;

  setUp(() async {
    database = AppDatabase.executor(NativeDatabase.memory());
    creationService = InventoryProductCreationService(database);
    catalogDao = CatalogLocalDao(database);
    await _insertBusiness(database, 'business-a');
    await _insertBusiness(database, 'business-b');
  });

  tearDown(() => database.close());

  test('creation from master persists master_product_id in Product and payload',
      () async {
    final result = await creationService.createLocalProductFromMaster(
      const CreateProductFromMasterInput(
        businessId: 'business-a',
        masterProduct: {
          'id': 'master-a',
          'name': 'Arroz Maestro',
        },
        barcodeRecord: {
          'barcode': '7701234567890',
          'barcode_normalized': '7701234567890',
          'barcode_type': 'ean13',
        },
        salePrice: 10,
      ),
    );

    final product = await (database.select(database.products)
          ..where((row) => row.id.equals(result.productId)))
        .getSingle();
    expect(product.masterProductId, 'master-a');
    expect(result.productPayload['master_product_id'], 'master-a');
    expect(
      result.pendingMutations.first.payload['master_product_id'],
      'master-a',
    );

    await database.into(database.localMasterProductsCatalog).insert(
          LocalMasterProductsCatalogCompanion.insert(
            id: 'master-link',
            name: const Value('Master linked'),
          ),
        );
    final manual = await creationService.createManualLocalProduct(
      const CreateManualLocalProductInput(
        businessId: 'business-a',
        name: 'Producto manual',
        purchasePrice: 1,
        salePrice: 2,
      ),
    );
    LinkLocalProductToMasterInput linkInput() {
      return LinkLocalProductToMasterInput(
        businessId: 'business-a',
        productId: manual.productId,
        masterProductId: 'master-link',
        barcodeRecord: const {
          'master_product_id': 'master-link',
          'barcode': '7709876543210',
          'barcode_normalized': '7709876543210',
          'barcode_type': 'ean13',
        },
      );
    }

    final firstLink = await creationService.linkLocalProductToMaster(
      linkInput(),
    );
    final secondLink = await creationService.linkLocalProductToMaster(
      linkInput(),
    );
    expect(firstLink.productId, manual.productId);
    expect(secondLink.businessBarcodeId, firstLink.businessBarcodeId);
    expect(secondLink.productPayload['master_product_id'], 'master-link');

    final linkedProducts = await (database.select(database.products)
          ..where((row) => row.id.equals(manual.productId)))
        .get();
    expect(linkedProducts, hasLength(1));
    expect(linkedProducts.single.masterProductId, 'master-link');

    final linkedCodes = await (database.select(database.localProductBarcodes)
          ..where(
            (row) =>
                row.businessId.equals('business-a') &
                row.productId.equals(manual.productId),
          ))
        .get();
    expect(linkedCodes, hasLength(1));
    expect(linkedCodes.single.masterProductId, 'master-link');
  });

  test(
      'internal codes are unique per business but reusable by another business',
      () async {
    final first = await creationService.createManualLocalProduct(
      const CreateManualLocalProductInput(
        businessId: 'business-a',
        name: 'Arroz A',
        barcode: 'ARROZ-001',
        purchasePrice: 1,
        salePrice: 2,
      ),
    );
    expect(first.businessBarcodePayload?['barcode_type'], 'internal');
    expect(first.productPayload['master_product_id'], isNull);

    await expectLater(
      creationService.createManualLocalProduct(
        const CreateManualLocalProductInput(
          businessId: 'business-a',
          name: 'Otro arroz A',
          barcode: 'ARROZ-001',
          purchasePrice: 1,
          salePrice: 2,
        ),
      ),
      throwsA(anything),
    );

    final otherBusiness = await creationService.createManualLocalProduct(
      const CreateManualLocalProductInput(
        businessId: 'business-b',
        name: 'Arroz B',
        barcode: 'ARROZ-001',
        purchasePrice: 1,
        salePrice: 2,
      ),
    );
    expect(otherBusiness.productId, isNot(first.productId));

    await database.customStatement(
      '''
      insert into local_product_barcodes (
        id, scope, master_product_id, barcode, barcode_normalized,
        barcode_type, is_primary, status
      ) values (?, 'global', ?, ?, ?, 'ean13', 1, 'active')
      ''',
      ['global-1', 'master-global', '7701111111111', '7701111111111'],
    );
    await expectLater(
      database.customStatement(
        '''
        insert into local_product_barcodes (
          id, scope, master_product_id, barcode, barcode_normalized,
          barcode_type, is_primary, status
        ) values (?, 'global', ?, ?, ?, 'ean13', 1, 'active')
        ''',
        ['global-2', 'master-global', '7702222222222', '7702222222222'],
      ),
      throwsA(anything),
    );
  });

  test('business lookup excludes inactive and deleted Products', () async {
    final created = await creationService.createManualLocalProduct(
      const CreateManualLocalProductInput(
        businessId: 'business-a',
        name: 'Producto inactivo',
        barcode: 'INTERNAL-9',
        purchasePrice: 1,
        salePrice: 2,
      ),
    );

    expect(
      (await catalogDao.lookupByBarcode(
        businessId: 'business-a',
        barcode: 'INTERNAL-9',
      ))
          .matchType,
      'business',
    );

    await (database.update(database.products)
          ..where((row) => row.id.equals(created.productId)))
        .write(const ProductsCompanion(status: Value('inactive')));
    expect(
      (await catalogDao.lookupByBarcode(
        businessId: 'business-a',
        barcode: 'INTERNAL-9',
      ))
          .found,
      isFalse,
    );

    await (database.update(database.products)
          ..where((row) => row.id.equals(created.productId)))
        .write(
      ProductsCompanion(
        status: const Value('active'),
        deletedAt: Value(DateTime.utc(2026, 8, 25)),
      ),
    );
    expect(
      (await catalogDao.lookupByBarcode(
        businessId: 'business-a',
        barcode: 'INTERNAL-9',
      ))
          .found,
      isFalse,
    );
  });
}

Future<void> _insertBusiness(AppDatabase database, String id) {
  return database.into(database.businesses).insert(
        BusinessesCompanion.insert(id: id, name: 'Business $id'),
      );
}
