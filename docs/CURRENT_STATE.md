# Estado actual de CronosManagement

Fotografía factual del repositorio `inventario-app` en el baseline indicado. No
es un roadmap ni una propuesta de arquitectura. Los dos documentos de
recuperación añadidos al working tree no forman parte del commit fotografiado.

## Identidad del baseline

- Proyecto: CronosManagement / `inventario-app`.
- Rama: `feature/foundation-core`.
- Commit: `8d1b8f4876b8934e54dc15e86fa5411158758bd3`.
- Fecha del commit: `2026-07-10T14:18:36-05:00`.
- Asunto del commit: `Agregar cambios anteriores offline-first para estar al día`.
- Frontend principal: `inventario-Frontend`, aplicación Flutter/Dart.
- Backend principal: `inventario-Backend`, proyecto Supabase/PostgreSQL definido
  principalmente por migraciones SQL; también contiene utilidades Node.js para
  conexión y pruebas manuales.

El hash, la fecha y la rama se obtuvieron directamente de Git. El stash de
rescate no se aplicó ni se usó como fuente para esta fotografía.

## Stack comprobado

`inventario-Frontend/pubspec.yaml` declara una aplicación `1.0.0+1`, con SDK
Dart `>=3.3.0 <4.0.0`, y las siguientes dependencias principales:

- Flutter;
- `flutter_riverpod ^3.3.1` para estado;
- `go_router ^17.3.0` para navegación;
- `drift ^2.20.1`, `drift_dev ^2.20.1`, `path_provider` y `path` para la base
  SQLite local y su generación;
- `supabase_flutter ^2.6.0` y `dio ^5.5.0` para backend/red;
- `uuid`, `connectivity_plus`, `shared_preferences`, `logger`, `intl`,
  `freezed` y `json_serializable` como soporte.

La raíz de `lib/` está dividida efectivamente en `app/`, `core/`, `features/` y
`shared/`. `main.dart` inicializa Supabase, envuelve la aplicación en
`ProviderScope` y usa `MaterialApp.router` con `AppRouter` en el flujo normal.

En backend, `supabase/config.toml` configura el desarrollo local de Supabase y
declara PostgreSQL major version 17 para ese entorno. `package.json` contiene
`@supabase/supabase-js ^2.106.2` y `uuid ^14.0.0`; su script `test` no ejecuta una
suite automatizada.

## Drift actual

La fuente autoritativa inspeccionada fue
`inventario-Frontend/lib/core/database/app_database.dart`.

- `schemaVersion` actual: **8**.
- Tablas de negocio y operación: `businesses`, `profiles`, `categories`,
  `customers`, `products`, `sales`, `sale_items`, `sale_payments`, `purchases`,
  `purchase_items`, `cash_registers` y `cash_sessions`.
- Contexto y permisos locales: `branches`, `roles`, `permissions`,
  `role_permissions` y `business_members`.
- Catálogo offline: `local_master_products_catalog`, `local_product_barcodes`,
  `local_catalog_sync_state` y `local_catalog_contribution_queue`.
- Outbox/sync local: `local_sync_batches` y `local_sync_mutations`.
- Inventario local: `local_inventory_movements` y
  `local_product_stock_balances`.

`app_database.g.dart` es código generado por Drift. La auditoría histórica que
registró `schemaVersion 1` no describe este baseline.

La tabla `products` todavía contiene `stock_quantity` y `minimum_stock`. El DAO
de saldos expone el primero con el alias explícito `legacy_stock_quantity`,
mientras obtiene `quantity_on_hand`, `quantity_reserved` y
`quantity_available` desde `local_product_stock_balances`. El test de base de
datos también comprueba que insertar una venta no modifique el stock legacy del
producto.

## Features Flutter presentes

La existencia de una carpeta se distingue aquí de una funcionalidad final:

| Feature | Evidencia en el baseline | Clasificación factual |
| --- | --- | --- |
| `auth` | DAOs locales de negocio y perfil | Infraestructura de datos |
| `cash` | Servicio/DAO local de sesiones, outbox, dashboard y widgets | Flujo operacional local con UI |
| `catalog` | lookup local por barcode, pull delta, repositorio y datasource remoto; no hay pantalla final propia | Infraestructura operacional offline-first |
| `customers` | DAO local | Infraestructura de datos |
| `dashboard` | dashboard principal y módulos de navegación | UI operacional; algunos módulos siguen pendientes |
| `debug` | ping y login Supabase | Laboratorio/debug |
| `inventory` | saldos, movimientos, pull, stock inicial, creación de producto, compras y reparación de sync | Infraestructura operacional más UI de Compras; no es la UI final de Inventario 6.21 |
| `pos` | carpeta sin archivos funcionales | Scaffold vacío |
| `sales` | venta local POS, impacto de inventario, outbox y pantalla POS | Flujo operacional local con UI |
| `settings` | estructura con `.gitkeep`, sin implementación funcional | Scaffold vacío |
| `sync` | outbox, uploads por dominio, runtime/contexto, scheduler, gates y pantallas E2E | Infraestructura; las pantallas E2E son laboratorio/debug |

Aunque existe una ruta llamada `inventory`, actualmente construye
`TemporaryInventarioView`. En el dashboard, Inventario y Movimientos muestran
mensajes de próxima implementación. Esto impide considerar que la carpeta
`inventory` sea por sí sola el módulo operativo final.

## Estado del inventario

- `ProductStockBalanceLocalDao` mantiene y consulta saldos por `business_id`,
  `branch_id` y `product_id`. Ofrece lectura individual, listado por sucursal y
  streams para UI.
- `InventoryMovementLocalDao` inserta movimientos locales con tipo, cambio de
  cantidad, origen, referencia e idempotency key, y permite marcarlos como
  sincronizados.
- `ProductStockBalancePullService` obtiene los saldos remotos de una sucursal y
  hace upsert en `local_product_stock_balances`.
- `InventoryInitialStockService` crea un movimiento inicial local y lo encola en
  el dominio de inventario.
- `InventoryProductCreationService` crea IDs localmente y soporta tanto producto
  local derivado del catálogo maestro como producto manual. Genera las
  mutaciones de catálogo y sus idempotency keys.
- `InventoryProductFromMasterSyncService` conecta esa creación con el outbox de
  catálogo. También puede reconstruir/encolar mutaciones de productos manuales
  usados por compras aún no sincronizadas.
- `PurchaseEntryScreen` permite buscar productos locales, crear un “producto
  rápido” manual, agregarlo al carrito y registrar la compra.
- `PurchaseLocalService` y `PurchaseLocalDao` crean compra, ítems y movimientos
  en una transacción local. Cada movimiento de compra usa cantidad positiva y
  actualiza `quantity_on_hand` y `quantity_available` del saldo local.
- El flujo POS bajo `features/sales` crea movimientos de venta con
  `quantity_change` negativo y aplica el cambio a los mismos saldos locales.
- `PurchaseSyncOutboxService` encola compras e ítems. Los movimientos locales de
  compra sirven al ledger/UI offline; el backend aplica el inventario remoto a
  partir de `purchase_items`.
- `PurchaseSyncRepairService` reemplaza batches de compras parciales o fallidos,
  restablece compra, ítems y movimientos para un reintento limpio, y el DAO
  también reconcilia compras cuyo outbox ya quedó completado.

Por tanto, el stock operativo local se apoya en
`local_product_stock_balances` y su trazabilidad en
`local_inventory_movements`; `products.stock_quantity` no es su fuente de
verdad. La UI final del módulo **6.21 — Inventario operativo** todavía no está
implementada en este baseline.

## Estado de sincronización

En `inventario-Frontend/lib/features/sync/application/` existen estos flujos y
componentes con nombres comprobados:

- `LocalSyncOutboxService`: batches y mutations locales compartidos por dominio;
- `CatalogSyncUploadService`: subida del dominio catálogo;
- `PosSyncUploadService`: subida de ventas/POS;
- `PurchasesSyncUploadService`: subida y reconciliación de compras;
- `CashSyncUploadService`: subida de caja;
- `InventorySyncUploadService`: subida de movimientos del dominio inventario;
- `ScheduledSyncService`: evalúa la política/estado de las ventanas y, cuando
  corresponde ejecutar, sube batches pendientes de catálogo, hace pull delta de
  catálogo, marca el slot como completado y guarda el resultado;
- `AppSyncCoordinatorService`: hace el preflight de la decisión, omite la
  ejecución si no corresponde o si el dispositivo está offline y, cuando puede
  continuar, prepara runtime, intenta el pull del contexto operacional y delega
  la ejecución de catálogo a `ScheduledSyncService`;
- `OperationalContextPullService`: descarga y aplica el snapshot operacional;
- `AppRuntimeSetupService`, `AppContextService` y
  `AppBusinessSelectionService`: preparación y selección del contexto operativo;
- `CashCloseSyncTriggerService`: wrapper que delega
  `runAfterCashClose` en `AppSyncCoordinatorService.runSyncForCashClose`; existe
  un provider, pero no se encontró un consumidor de este servicio en `lib/`;
- `AppE2ELocalFlowService` y `AppE2EProductFromCatalogFlowService`: flujos de
  laboratorio E2E, no UI final.

Además existen stores, políticas, providers y modelos para installation ID,
contexto runtime/seleccionado y estado del scheduled sync. Los dominios
`catalog`, `pos`, `purchases`, `cash` e `inventory` tienen servicios de subida y
datasources remotos separados.

### Alcance real de scheduled sync y cierre de caja

El flujo programado conectado a la UI parte de `AppSyncLifecycleGate`: al inicio
o al reanudar la aplicación construye el input y llama
`AppSyncCoordinatorService.runScheduledSyncIfDue`. La política actual contempla
ventanas durante las horas locales 11 y 23, además de triggers forzados para
ejecución manual y cierre de caja.

Hay una diferencia explícita entre el servicio scheduled aislado y la ejecución
completa a través del coordinador:

- `ScheduledSyncService` directamente solo ejecuta el dominio **catálogo**:
  upload pendiente seguido de pull delta. Sus métodos manual y de cierre de caja
  fuerzan la decisión, pero no añaden otros dominios.
- Una ejecución programada mediante `AppSyncCoordinatorService` puede hacer,
  antes de ese catálogo, el setup remoto del runtime/dispositivo y el pull del
  contexto operacional cuando hay `profileId`. Después llama al mismo
  `ScheduledSyncService`.
- `PosSyncUploadService`, `PurchasesSyncUploadService`,
  `CashSyncUploadService` e `InventorySyncUploadService` no son dependencias del
  coordinator/scheduled ni se invocan desde esa cadena. Por tanto POS, compras,
  caja e inventario no forman parte del flujo programado actual.

El cierre de caja operacional visible sigue otro camino. En
`CashDashboardScreen`, la acción de cierre prepara y sube caja, prepara y sube
POS, cierra la sesión local y vuelve a preparar/subir caja para enviar el cierre.
Esa pantalla no llama `CashCloseSyncTriggerService` ni
`AppSyncCoordinatorService`. En consecuencia, el cierre real de esa UI incluye
los dominios **cash** y **POS**, pero no compras ni inventario, y no ejecuta
catálogo/contexto operacional mediante el coordinator como efecto de ese
cierre. Si se invocara `CashCloseSyncTriggerService`, el trigger forzado
recorrería la cadena del coordinator descrita arriba —runtime, contexto
operacional y catálogo—, no los uploads de cash o POS. El wrapper describe una
ruta disponible en infraestructura, no una integración consumida por la UI
actual.

La idempotencia no es una intención futura: `local_sync_batches` y
`local_sync_mutations` registran client IDs, secuencia, idempotency key, estado,
errores y retry count. Los uploaders reutilizan esos datos y tratan conflictos
duplicados según cada dominio. En compras existe de forma explícita el cierre
local `completed_remote_already_exists` cuando todas las entidades ya existen en
remoto.

## Estado funcional conocido del roadmap

- **6.20 — producto rápido desde Compras: implementada.** La pantalla permite
  crear el producto manual local, incorporarlo al carrito y encolar primero sus
  mutaciones de catálogo. El historial de Git contiene el commit
  `6f031c7 feat: support quick product creation from purchases with catalog sync repair`,
  incluido en el baseline.
- Catálogo local/outbox e idempotencia: implementados en código mediante catálogo
  local, batches, mutations e idempotency keys.
- Reparación y reconciliación de compras: implementadas mediante
  `PurchaseSyncRepairService`, `reconcileCompletedPurchasesFromOutbox` y el flujo
  de subida de compras.
- Manejo `completed_remote_already_exists`: presente en
  `PurchasesSyncUploadService`.
- **6.21 — Inventario operativo: pendiente de implementación como UI final en el
  baseline.** No se atribuye al baseline ningún archivo posterior guardado en el
  stash de rescate.

## Backend comprobado por migraciones

Las migraciones presentes muestran, sin necesidad de reconstruir aquí todo su
SQL:

- esquema remoto inicial y metadatos de catálogo/operación;
- multitenancy con negocios, miembros, sucursales, roles, permisos, helpers,
  índices y políticas RLS por entidades;
- POS/caja con cajas, sesiones, pagos, secuencias y totales;
- inventario por sucursal con ledger de `inventory_movements`,
  `product_stock_balances`, aplicación de movimientos, stock counts y RPCs;
- batches, mutations, conflicts, cursors, procesamiento, resolución,
  observabilidad y mantenimiento de sync;
- aplicación de mutaciones de catálogo y product barcodes;
- aplicación de POS y compras, incluyendo aplicación idempotente de inventario;
- pull de cambios con cursores y page tokens;
- catálogo offline/master, lookup por barcode, pull delta y contribuciones;
- registro de dispositivos y onboarding/runtime del negocio;
- transferencias de inventario y RPC de finalización.

Entre los nombres representativos están
`multitenancy_core_policies`, `sync_batches`, `sync_mutations`,
`sync_conflicts`, `sync_apply_catalog_mutations`, `sync_apply_pos_patch`,
`sync_apply_purchases`, `sync_pull_changes_v2_page_tokens`,
`inventory_product_stock_balances`, `inventory_transfers` y
`inventory_complete_transfer_rpc`.

La infraestructura backend para transferencias no implica que exista una UI
Flutter de transferencias. No se encontró esa UI en las features del baseline.

## Tests presentes

Hay 36 archivos Dart bajo `inventario-Frontend/test/`. Las áreas visibles en la
suite son:

- persistencia Drift/SQLite y la regla de no mutar el stock legacy al insertar
  una venta;
- guard de `customStatement` contra parámetros raw inseguros;
- normalización de parámetros SQLite;
- UUID y normalización de barcodes;
- modelos, lookup local, pull y respuestas de catálogo;
- modelos de creación de producto de inventario y mapeo al outbox;
- modelos, stores, providers, selección de negocio, permisos y contexto de sync;
- políticas/modelos de scheduled sync;
- widgets y gates del shell/contexto, además de pantallas E2E como verificación
  de existencia/construcción;
- smoke test de `MyApp`.

Esta lista describe los tests que existen, no afirma cobertura integral ni que
la suite haya sido ejecutada durante esta recuperación documental.

## Documentación histórica

Ya existen documentos bajo `inventario-Backend/docs/`, incluidos contratos de
catálogo/sync y auditorías de frontend, y documentos de UI operacional bajo
`inventario-Frontend/docs/frontend/`.

En particular, `database-baseline.md`,
`flutter_current_structure_audit.md` y
`flutter_local_db_sync_audit_618C95.md` son fotografías históricas. No son una
descripción autoritativa del estado actual sin contrastarlas con el código. Por
ejemplo, la auditoría 618C95 registra `schemaVersion 1`, mientras el baseline
actual declara `schemaVersion 8`.

## Próximo punto

El próximo punto del roadmap es:

**6.21 — Inventario operativo**

La ruta oficial de continuidad, documentada en [ROADMAP.md](ROADMAP.md), fija
como siguiente punto **6.21.1 — Listado de productos con stock**. Esta UI final
continúa pendiente. El listado deberá partir de
`local_product_stock_balances`; `local_inventory_movements` conserva los
movimientos y la trazabilidad, y `products.stock_quantity` no es el saldo
operativo. Este documento no diseña ni implementa esa fase.

## Límites de esta fotografía

- Se inspeccionaron el código, los tests, la configuración, el historial Git y
  los nombres/contenido representativo de migraciones del commit baseline.
- No se ejecutó la aplicación, la suite Flutter ni las migraciones contra una
  instancia Supabase; por ello no se afirma validación runtime.
- No se inspeccionó ni aplicó el contenido del stash de rescate.
