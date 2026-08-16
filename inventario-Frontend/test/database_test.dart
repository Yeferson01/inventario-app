import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/native.dart'; // Importante para usar NativeDatabase.memory()
import 'package:inventario_frontend/core/database/app_database.dart';

void main() {
  // Nota: Eliminamos WidgetsFlutterBinding.ensureInitialized() ya que no tocaremos canales nativos de disco.

  group('Pruebas de Persistencia Local Offline-First', () {
    late AppDatabase db;
    late ProductDao productDao;
    late SaleDao saleDao;

    final String businessId = const Uuid().v4();
    final String productId = const Uuid().v4();
    final String saleId = const Uuid().v4();

    setUp(() {
      // 1. Inicializamos Drift directamente en memoria RAM usando el constructor con executor
      db = AppDatabase.executor(NativeDatabase.memory());

      // 2. Como los DAOs son partes del archivo central, los instanciamos pasándoles la base de datos en memoria
      productDao = ProductDao(db);
      saleDao = SaleDao(db);
    });

    tearDown(() async {
      // Cerramos la base de datos limpia al finalizar para no dejar residuos en la memoria virtual
      await db.close();
    });

    test('Debería insertar una venta sin modificar stock legacy del producto',
        () async {
      await db.into(db.businesses).insert(
            BusinessesCompanion.insert(
              id: businessId,
              name: 'Negocio de Prueba Offline',
            ),
          );

      // 1. Crear e insertar un producto inicial con 50 unidades en stock
      final productoInicial = Product(
        id: productId,
        businessId: businessId,
        name: 'Producto de Prueba Offline',
        salePrice: 1500.0,
        purchasePrice: 1000.0,
        stockQuantity: 50, // Stock inicial
        minimumStock: 5, // Proporcionamos el valor requerido por la tabla
        unit: 'unidad',
        status: 'active',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        syncStatus: SyncStatus
            .pendingInsert, // Pasamos el índice entero (.index) si la base de datos espera un int
      );

      await productDao.saveProductLocal(productoInicial);
      print('✅ Producto insertado con éxito localmente.');

      // 2. Crear una venta de 5 unidades de ese producto
      final now = DateTime.now();

      final ventaCabecera = Sale(
  	id: saleId,
  	businessId: businessId,
  	customerId: null,
  	branchId: null,
  	cashRegisterId: null,
  	cashSessionId: null,
  	subtotal: 7500.0,
  	discountTotal: 0,
  	taxTotal: 0,
  	total: 7500.0,
  	paymentMethod: 'efectivo',
  	paymentStatus: 'paid',
  	idempotencyKey: null,
  	localStatus: 'synced',
  	metadataJson: null,
  	status: 'completed',
  	createdAt: now,
  	updatedAt: now,
  	deletedAt: null,
  	syncStatus: SyncStatus.pendingInsert,
      );

      final detalleItem = SaleItem(
  	id: const Uuid().v4(),
  	saleId: saleId,
  	productId: productId,
  	productNameSnapshot: null,
  	barcodeSnapshot: null,
  	quantity: 5,
  	unitPrice: 1500.0,
  	discountTotal: 0,
  	taxTotal: 0,
  	subtotal: 7500.0,
  	lineTotal: 7500.0,
  	metadataJson: null,
  	createdAt: now,
  	updatedAt: now,
  	syncStatus: SyncStatus.pendingInsert,
      );

      // 3. Ejecutar la venta usando la transacción atómica del DAO
      print(
          '🚀 Ejecutando transacción de venta legacy sin impacto directo a stock...');
      await saleDao.insertCompleteSale(
        saleRecord: ventaCabecera,
        itemsList: [detalleItem],
      );

      // 4. Verificar que el stock se haya reducido automáticamente (50 - 5 = 45)
      final productosActivos =
          await productDao.searchProducts(businessId, 'Prueba');
      final productoActualizado = productosActivos.first;

      print('📊 Stock Inicial: 50 | Cantidad Vendida: 5');
      print(
          '📊 Stock legacy actual en DB Local: ${productoActualizado.stockQuantity}');

      expect(productoActualizado.stockQuantity, 50);

      // Comparamos contra el índice numérico del enum (o contra el enum entero según corresponda)
      expect(productoActualizado.syncStatus, SyncStatus.pendingInsert);

      print(
          '🎉 ¡Prueba superada con éxito! La persistencia local y la lógica de stock funcionan perfectamente.');
    });
  });
}
