# Arquitectura vigente de CronosManagement

## Alcance

Este documento describe la arquitectura comprobable del baseline actual. No es
una propuesta de arquitectura futura. Los contratos históricos se usan para
entender decisiones existentes, pero las afirmaciones sobre implementación se
contrastan con el código y con [CURRENT_STATE.md](CURRENT_STATE.md).

## Visión general

La cadena principal es:

```text
Presentation / UI
  → servicios y providers de Application
  → DAOs, repositorios y datasources de Data
  → Drift / estado local
  → outbox y uploaders de sync
  → Supabase / Postgres
```

Es una cadena conceptual, no una única llamada lineal común a todos los
dominios. Las escrituras operacionales se resuelven primero en Drift. El outbox
también se persiste en Drift y los uploaders por dominio lo envían después a sus
datasources remotos. Los pulls de catálogo, contexto operacional o saldos tienen
datasources propios y aplican sus resultados al estado local.

La frontera arquitectónica vigente es:

```text
UI / presentation → application → data
```

La UI final no debe implementar lógica de negocio ni acceder directamente a
DAOs/datasources, salvo un patrón ya establecido y expresamente autorizado para
el caso. Los DAOs pertenecen a Data.

## Frontend

El código principal bajo `inventario-Frontend/lib/` está organizado así:

- `app/`: composición de la aplicación, router y tema;
- `core/`: configuración e infraestructura transversal, incluida la base Drift,
  red, Supabase, logging, errores, utilidades y piezas comunes de sync;
- `features/`: capacidades agrupadas por dominio, con las capas que cada feature
  implementa actualmente;
- `shared/`: modelos, widgets, providers, formatos, extensiones y otros elementos
  reutilizables que no pertenecen a un único dominio.

No todas las features contienen las mismas subcapas ni tienen el mismo grado de
finalización. La estructura del directorio no sustituye la inspección de sus
archivos y consumidores.

## Capas

### Presentation

Contiene screens, widgets y providers de presentación. Recoge intención del
usuario, presenta estado y delega casos de uso a Application. No es la capa para
implementar reglas de negocio ni persistencia.

### Application

Contiene servicios, casos de uso, coordinación y providers que componen
dependencias. Aquí viven, entre otros, los servicios de venta y compra local,
sesiones de caja, contexto, outbox, uploaders y coordinación programada.

### Data

Contiene DAOs, datasources locales/remotos, repositorios y modelos de
persistencia o transporte. Encapsula el acceso a Drift y a los RPCs/tablas
remotas usados por Application.

### Base de datos local

La persistencia local usa Drift sobre SQLite. `AppDatabase` tiene actualmente
`schemaVersion = 8` y registra estas familias de tablas:

- negocio: `businesses`, `profiles`, `branches`, `business_members`, `roles`,
  `permissions` y `role_permissions`;
- operación comercial: `categories`, `customers`, `products`, `sales`,
  `sale_items`, `sale_payments`, `purchases`, `purchase_items`,
  `cash_registers` y `cash_sessions`;
- catálogo local: `local_master_products_catalog`, `local_product_barcodes`,
  `local_catalog_sync_state` y `local_catalog_contribution_queue`;
- outbox: `local_sync_batches` y `local_sync_mutations`;
- inventario: `local_inventory_movements` y
  `local_product_stock_balances`.

`app_database.g.dart` es código generado y no se edita manualmente. La generación
de Drift corresponde únicamente cuando hay una modificación autorizada del
esquema.

## Offline-first

El flujo lógico de una operación compatible con el baseline es:

```text
acción del usuario
  → validación y transacción local
  → estado operacional local y preparación del outbox
  → UI actualizada desde local
  → upload posterior del dominio
  → aplicación remota y reconciliación/pull cuando corresponde
```

La escritura local y la creación del batch no siempre ocurren dentro del mismo
método ni en el mismo instante. Por ejemplo, ventas y compras se crean mediante
servicios locales y luego sus servicios de outbox buscan operaciones pendientes
para encolarlas. Por eso el diagrama expresa responsabilidades y orden de
autoridad, no una implementación idéntica para todos los dominios.

Las entidades se identifican localmente. La reejecución remota conserva IDs,
secuencias e idempotency keys para evitar aplicar dos veces el mismo efecto.

## Contexto operacional

El contexto seleccionado combina `business`, `branch`, `profile` y los datos de
la instalación/dispositivo. Ese contexto delimita consultas, permisos, caja,
inventario y payloads de sincronización.

- `AuthorizedOperationalContextService` consume
  `list_authorized_operational_contexts()` y es la autoridad online para las
  opciones explícitas `profile + business + branch`.
- `OperationalBootstrapEntryService` valida la selección profile-scoped y
  coordina registro del device, resolución de runtime y bootstrap antes de
  permitir la navegación productiva.
- `AppContextService` lee la proyección local efectiva por
  `profile + business + branch`; sus permisos efectivos, no un rol activo,
  gobiernan el gating de UX.
- `AppBusinessSelectionService` y `OperationalContextPullService` permanecen
  como infraestructura legacy para consumidores delimitados de sync/E2E, pero
  ya no calculan las opciones del selector productivo.

La ausencia o selección incorrecta de contexto no es un detalle visual: cambia
el tenant, la sucursal y las autorizaciones de una operación.

## Arquitectura de sincronización

### Outbox común

`local_sync_batches` agrupa intentos por negocio, dominio y dirección, y conserva
estado, conteo de reintentos, errores y client batch ID.
`local_sync_mutations` mantiene las operaciones ordenadas del batch, con client
mutation ID, client sequence, entidad, operación, payload, idempotency key,
estado, error y retry count.

`LocalSyncOutboxService` valida y administra ese outbox común. Ofrece colas
pendientes y transiciones de estado para los dominios `catalog`, `pos`,
`purchases`, `cash` e `inventory`.

### Uploaders por dominio

El outbox no implica un uploader monolítico. La subida está separada en:

- `CatalogSyncUploadService`;
- `PosSyncUploadService`;
- `PurchasesSyncUploadService`;
- `CashSyncUploadService`;
- `InventorySyncUploadService`.

Cada servicio toma batches de su dominio, usa su datasource remoto y actualiza
el estado local según el resultado. Comparte el mecanismo de batches/mutations,
pero conserva reglas y reconciliación propias.

### Pulls y conflictos

El baseline implementa pulls específicos, entre ellos el delta del catálogo, el
snapshot de contexto operacional y la actualización de saldos de stock. No debe
inferirse de esto un pull único y automático para todos los dominios.

El backend contiene `sync_batches`, `sync_mutations`, `sync_cursors` y
`sync_conflicts`, además de RPCs de procesamiento y resolución. Los conflictos
son infraestructura remota comprobada; la base Drift de schema 8 no contiene
una tabla local `sync_conflicts` equivalente.

## Scheduled sync

`AppSyncLifecycleGate` intenta el flujo programado al iniciar y reanudar la
aplicación, con control de intervalo. La política vigente define ventanas en las
horas locales 11 y 23 y permite triggers forzados manual y de cierre de caja.

Hay que distinguir el servicio scheduled aislado de la ejecución completa por
el coordinador:

- `ScheduledSyncService` evalúa la política y el estado de slots. Cuando ejecuta,
  llama únicamente al upload pendiente de **catálogo**, realiza después el pull
  delta de **catálogo**, marca el slot y guarda el resultado.
- `AppSyncCoordinatorService` hace un preflight de esa decisión, omite la cadena
  si no corresponde o si el dispositivo está offline y, cuando continúa,
  prepara el runtime remoto, intenta el pull de contexto operacional si dispone
  de `profileId` y finalmente delega en `ScheduledSyncService`.
- `PosSyncUploadService`, `PurchasesSyncUploadService`,
  `CashSyncUploadService` e `InventorySyncUploadService` no son dependencias de
  esta cadena. POS, compras, caja e inventario no forman parte del scheduled
  actual.

Este es el alcance implementado hoy; no afirma que catálogo deba ser el alcance
definitivo del producto.

## Caja y POS

### Caja

`CashSessionLocalService` obtiene o crea una caja local, abre una sesión local y
valida que no exista otra sesión abierta para la misma caja. La preparación del
outbox y `CashSyncUploadService` permiten registrar remotamente caja/sesión antes
de que el uploader POS exija su disponibilidad remota.

La habilitación operacional de POS se basa en el contexto y en una sesión de
caja abierta. El uploader POS comprueba además la preparación remota de caja.

### POS

El POS operacional vive en `features/sales`, no en `features/pos`. Su flujo
actual es:

```text
producto y saldo local
  → venta local
  → ítems y pagos locales
  → movimiento negativo y actualización del saldo local
  → batch/mutations POS
  → PosSyncUploadService
  → aplicación remota de venta e inventario
```

`PosLocalSaleService` genera los IDs y payloads y
`PosLocalSaleDao.insertSaleWithLocalInventoryImpact` ejecuta la persistencia
transaccional de venta, ítems, pagos, movimientos y saldos. El outbox POS encola
después la venta pendiente con sus entidades relacionadas.

### Cierre actual

La acción de cierre visible en `CashDashboardScreen` sigue esta secuencia:

```text
preparar/subir cash
  → preparar/subir POS
  → cerrar la sesión local
  → preparar/subir cash con el cierre
```

Esta pantalla no consume `CashCloseSyncTriggerService` ni el coordinador
programado. Por tanto, ese cierre real no añade catálogo, contexto, compras o
inventory upload por medio del coordinator.

## Compras

`PurchaseLocalService` crea localmente la compra y sus ítems. La operación
transaccional de `PurchaseLocalDao` también crea movimientos positivos y
actualiza los saldos locales por sucursal.

El flujo de sincronización vigente es:

```text
purchase + purchase_items + impacto local de inventario
  → PurchaseSyncOutboxService
  → completar/subir catálogo primero cuando un producto lo requiere
  → PurchasesSyncUploadService
  → backend aplica compra e inventario remoto
  → reconciliación local
```

Los IDs e idempotency keys se conservan al reintentar. La reparación de compras
atiende estados parciales/fallidos y el uploader reconoce explícitamente
`completed_remote_already_exists` cuando las entidades ya existen en remoto.

## Catálogo

La resolución de código de barras es local-first:

```text
código normalizado
  → producto del negocio en local
  → catálogo maestro en local
  → creación desde master o creación manual si no hay coincidencia
```

`CatalogBarcodeLookupService` delega la búsqueda a la persistencia local. No
consulta Supabase por cada escaneo. La red interviene después mediante upload de
mutaciones/contribuciones y pull delta del catálogo.

El pull del catálogo maestro usa una ventana delimitada y tokens firmados. El
cursor temporal comprometido solo avanza al completar la unión de productos
maestros y códigos globales/empresariales; una pausa por presupuesto conserva
un checkpoint reanudable. La aplicación de cada página y ese checkpoint es
atómica en Drift, incluye tombstones y rechaza versiones remotas más antiguas.

## Inventario

El modelo separa datos comerciales, saldo y ledger:

- `products` contiene identidad y datos comerciales/configurables del producto;
- `local_product_stock_balances` es la fuente local del saldo operativo por
  producto y sucursal;
- `local_inventory_movements` conserva el ledger y la trazabilidad local;
- en backend, `product_stock_balances` e `inventory_movements` cumplen las
  responsabilidades remotas equivalentes.

`products.stock_quantity` permanece como campo legacy y no es source of truth
del saldo operativo. `products.minimum_stock` es configuración de umbral y no
debe confundirse con una cantidad disponible.

Ventas y compras ya generan movimientos y modifican saldos locales mediante sus
flujos existentes. Esto no equivale a que la UI final de inventario 6.21 esté
implementada.

## Backend

El backend vigente se construye con Postgres/Supabase y migraciones versionadas.
Incluye:

- aislamiento multi-tenant por negocio/sucursal, helpers, índices y políticas
  RLS;
- roles, permisos y membresías;
- metadatos de versión y soft delete donde aplica el contrato;
- registro de dispositivos y preparación del runtime;
- batches, mutations, cursores, conflictos, procesamiento, resolución y
  observabilidad de sync;
- catálogo maestro, barcodes, contribuciones, lookup y pull delta;
- POS/caja, pagos, sesiones, secuencias y totales;
- compras y aplicación idempotente de su efecto en inventario;
- ledger y saldos de inventario por sucursal, conteos, transferencias y RPCs de
  aplicación/finalización.

Estas capacidades remotas no garantizan consumidores ni pantallas Flutter para
cada una de ellas.

## E2E y debug

Las pantallas y servicios E2E/debug ejercitan setup, contexto, catálogo,
outbox, uploads y otros flujos controlados. Son un laboratorio para validar
infraestructura y contratos; no definen la UI final ni prueban que una feature
de producto esté terminada.

## Deudas y zonas no consolidadas confirmadas

- El scheduled sync todavía no integra POS, compras, caja ni inventario.
- `CashCloseSyncTriggerService` tiene provider, pero no es consumido por la UI
  actual.
- `features/pos` es un scaffold sin implementación operacional relevante,
  mientras el POS real del baseline vive en `features/sales`.
- La UI final de inventario correspondiente a 6.21 está pendiente.

Esta sección registra el estado actual y no propone soluciones.
