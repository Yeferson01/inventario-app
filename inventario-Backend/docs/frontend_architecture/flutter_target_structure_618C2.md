# Fase 6.18C.2 — Estructura objetivo Flutter adaptada a la base existente

## 1. Objetivo

Definir la estructura objetivo del frontend Flutter sin recrear el proyecto desde cero.

La base actual ya incluye:

- `app/router`
- `app/theme`
- `core/database`
- `features/auth`
- `features/customers`
- `features/inventory`
- `features/sales`
- Drift
- GoRouter
- Riverpod
- Supabase Flutter

Por eso, la estrategia es adaptar y extender, no reemplazar.

---

## 2. Principios de arquitectura

La app debe seguir estos principios:

1. Offline-first real.
2. SQLite/Drift como fuente local inmediata.
3. Supabase como servidor de sincronización.
4. No consultar Supabase por cada escaneo.
5. No bloquear venta por falta de internet.
6. Separar datos locales, sincronización y UI.
7. Mantener el código existente mientras se migra gradualmente.
8. Usar Riverpod para providers globales.
9. Usar GoRouter como navegación principal.
10. Usar UUID generado localmente para entidades nuevas.

---

## 3. Estructura objetivo

```txt
lib/
  app/
    router/
    theme/

  core/
    config/
    constants/
    database/
      app_database.dart
      app_database.g.dart
      tables/
      converters/
      migrations/
    device/
    errors/
    logging/
    network/
    providers/
    supabase/
    sync/
    utils/

  features/
    auth/
    customers/
    inventory/
    sales/

    catalog/
      data/
        datasources/
        models/
        repositories/
      domain/
        entities/
        repositories/
      application/
      presentation/
        pages/
        widgets/

    pos/
      data/
        datasources/
        models/
        repositories/
      domain/
        entities/
        repositories/
      application/
      presentation/
        pages/
        widgets/

    sync/
      data/
        datasources/
        models/
        repositories/
      domain/
        entities/
        repositories/
      application/
      presentation/
        pages/
        widgets/

    settings/
      data/
        datasources/
        models/
        repositories/
      domain/
        entities/
        repositories/
      application/
      presentation/
        pages/
        widgets/

  shared/
    widgets/
    extensions/
    formatters/
4. Qué se conserva

Se conserva la base actual:

main.dart
app/router/app_router.dart
app/router/routes_constants.dart
app/theme/*
core/database/app_database.dart
DAOs existentes en features
GoRouter
Drift
Riverpod
Supabase Flutter

No se debe borrar ni mover código existente en esta fase
5. Qué se agregará después
5.1 Core config

Contendrá lectura de variables de entorno:

APP_NAME
SUPABASE_URL
SUPABASE_ANON_KEY
ENVIRONMENT
API_URL si se conserva para servicios auxiliares
5.2 Core supabase

Contendrá:

cliente Supabase
inicialización
helpers de sesión
llamadas RPC comunes
5.3 Core providers

Contendrá providers globales:

databaseProvider
supabaseClientProvider
currentSessionProvider
currentBusinessProvider
currentBranchProvider
currentAppDeviceProvider
5.4 Core device

Contendrá:

installation id local
registro de app_device
datos del dispositivo
app version / platform
5.5 Core sync

Contendrá:

SyncEngine
UploadSyncService
PullSyncService
CatalogSyncService
ConflictSyncService
SyncScheduler
5.6 Core network

Contendrá:

estado online/offline
verificación de conectividad
retry policies
5.7 Core utils

Contendrá:

normalizeBarcode
UUID helpers
date helpers
json helpers
6. Módulo catalog

Responsable de:

tablas locales de catálogo maestro
product_barcodes locales
lookup local por barcode
pull_product_catalog_delta
cola de contribuciones
submit_product_catalog_contribution
caché lazy de imágenes livianas

Regla principal:

La app no debe llamar Supabase por cada escaneo.

7. Módulo POS

Responsable de:

venta local offline
items de venta
pagos
generación local de IDs
estado pendiente de sync
subida en lote con process_sync_batch modo apply_pos
aplicación posterior de inventario con apply_pos_batch_inventory_movements
8. Módulo Sync

Responsable de UI/admin de sync:

ver estado de sincronización
errores
conflictos
último pull
último upload
dispositivo actual
cola pendiente

La lógica pesada vive en core/sync.

9. Módulo Settings

Responsable de:

negocio actual
sucursal actual
caja actual
dispositivo actual
usuario actual
preferencias offline
10. Relación con Drift actual

Actualmente existe un archivo central:

core/database/app_database.dart

Por ahora se mantiene como punto central.

En fases siguientes se agregarán tablas nuevas dentro del mismo archivo o mediante parts organizados, según convenga.

Tablas nuevas requeridas a futuro:

local_app_devices
local_sync_batches
local_sync_mutations
local_sync_conflicts
local_sync_cursors
local_catalog_sync_state
local_master_products_catalog
local_product_barcodes
local_catalog_contribution_queue
local_cash_registers
local_cash_sessions
local_sale_payments
11. Relación con Supabase actual

main.dart ya importa supabase_flutter, pero todavía debe inicializar Supabase formalmente.

En una fase siguiente se agregará:

await Supabase.initialize(
  url: AppConfig.supabaseUrl,
  anonKey: AppConfig.supabaseAnonKey,
);

También se agregará ProviderScope.

12. Orden de implementación recomendado
6.18C.2 — estructura objetivo.
6.18C.3 — configuración e inicialización Supabase/Riverpod.
6.18C.4 — helpers base: config, logger, UUID, barcode.
6.18C.5 — ampliar Drift con tablas de catálogo local.
6.18C.6 — DAO/repositorio de catálogo local.
6.18C.7 — pull_product_catalog_delta desde Flutter.
6.18C.8 — búsqueda local por barcode.
6.18C.9 — contribuciones offline.
6.18C.10 — sync engine inicial.
13. Reglas de no ruptura

Durante la adaptación:

No borrar DAOs existentes.
No eliminar rutas temporales todavía.
No reemplazar AppRouter sin necesidad.
No cambiar theme system.
No borrar app_database.g.dart manualmente.
No editar archivos generados a mano.
Ejecutar build_runner solo cuando se modifiquen tablas Drift.
Hacer cambios pequeños y validados.
14. Estado de esta fase

Esta fase solo crea:

carpetas objetivo
documento de arquitectura

No modifica lógica de ejecución.
