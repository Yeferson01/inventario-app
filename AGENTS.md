# Contrato operativo para agentes

Este archivo aplica a todo el repositorio `inventario-app`. Su propósito es
preservar las decisiones ya tomadas y mantener el trabajo de los agentes dentro
del roadmap oficial de CronosManagement.

## Gobierno del proyecto

- ChatGPT, en el chat principal, define la arquitectura, el roadmap y las
  decisiones técnicas relevantes.
- Codex ejecuta inspecciones, cambios acotados, comandos, pruebas y revisión de
  diffs dentro del alcance recibido.
- Codex no introduce decisiones arquitectónicas importantes sin una instrucción
  explícita del chat principal.
- Ante una ambigüedad arquitectónica, Codex se detiene y la reporta; no elige una
  dirección por cuenta propia.
- Trabajar normalmente uno o dos pasos por vez y mantener cada cambio limitado
  al objetivo indicado.
- No saltarse fases ni subfases del roadmap.
- Antes de modificar archivos, inspeccionar el estado real del código, las
  pruebas y la configuración relacionados con la tarea. Los documentos
  históricos no sustituyen esta inspección.

## Git y disciplina del working tree

- Rama de trabajo actual: `feature/foundation-core`.
- Baseline de recuperación:
  `8d1b8f4876b8934e54dc15e86fa5411158758bd3`.
- Comenzar desde un working tree limpio. Si `git status` muestra cambios no
  esperados o fuera del alcance, detenerse y reportarlos antes de editar.
- Nunca ejecutar comandos destructivos de Git sin autorización explícita. Esto
  incluye, entre otros, `reset`, `restore`, `checkout`, `clean` y operaciones que
  apliquen o eliminen stashes.
- Mostrar `git status` antes y después de cada tarea.
- Revisar el diff completo del alcance antes de considerar terminada una tarea.
- No crear archivos temporales o de respaldo como `.bak`, `.back`, `.tmp` o
  equivalentes.
- No incluir accidentalmente archivos temporales, respaldos ni diagnósticos en
  commits.
- Las migraciones SQL bajo Supabase pueden requerir atención especial por las
  reglas y excepciones de `.gitignore`. No modificar esas reglas sin
  autorización explícita.
- No hacer commit ni push salvo que la tarea lo solicite expresamente.

## Flutter y estructura vigente

- El frontend usa Flutter con Drift/SQLite, Riverpod, GoRouter y Supabase
  Flutter.
- La estructura principal de `lib/` está organizada en `app/`, `core/`,
  `features/` y `shared/`; conservar esta organización.
- La frontera de capas para la UI final es:
  `UI/presentation → servicios/providers de application → DAOs/datasources`.
- La UI final no implementa lógica de negocio ni accede directamente a DAOs,
  salvo que exista un patrón ya establecido y expresamente autorizado para ese
  caso.
- Los DAOs y datasources pertenecen a la capa de datos. La capa de presentación
  los consume a través de los servicios/providers de application, siguiendo el
  contrato ya establecido por POS y Caja.
- No editar `app_database.g.dart` manualmente.
- Ejecutar la generación de Drift solamente cuando corresponda a una
  modificación autorizada del esquema.
- No sustituir DAOs, servicios u outboxes existentes por una arquitectura nueva
  sin instrucción explícita.
- Las pantallas y servicios E2E son laboratorio/debug, no UI final ni modelo de
  producto terminado.

## Reglas offline-first

- Toda operación compatible con el modelo actual escribe primero en local.
- La UI se actualiza desde el estado local.
- La sincronización con Supabase ocurre después de la escritura local.
- Los IDs de entidades nuevas se generan localmente.
- Mantener idempotencia mediante batches, mutations e idempotency keys.
- No consultar Supabase por cada escaneo de producto.
- Consultar primero el catálogo local; la ausencia local conduce al flujo
  previsto de creación/sincronización, no a una consulta remota por escaneo.
- No implementar hard delete para entidades de negocio sin una decisión
  explícita.
- Mantener separadas las responsabilidades del estado local, el outbox y el
  servidor.

## Inventario

- `products.stock_quantity` no es la fuente de verdad del saldo operativo y no
  debe recuperar ese rol por accidente.
- Los saldos operativos locales se basan en
  `local_product_stock_balances`, por producto y sucursal.
- Los movimientos y la trazabilidad local se basan en
  `local_inventory_movements`.
- Los campos de configuración de `products`, como `minimum_stock`, pueden seguir
  utilizándose para su finalidad correspondiente; no deben confundirse con el
  saldo operativo.
- Las compras aumentan inventario y las ventas lo disminuyen mediante los flujos
  existentes de movimientos y saldos.
- No crear un segundo sistema paralelo de inventario.

## Sincronización

Existen flujos separados y deben conservarse sus nombres y responsabilidades:

- catálogo: `CatalogSyncUploadService` y el pull de
  `CatalogSyncService`;
- POS: `PosSyncUploadService`;
- compras: `PurchasesSyncUploadService`;
- caja: `CashSyncUploadService` y `CashCloseSyncTriggerService`;
- inventario: `InventorySyncUploadService`;
- sincronización programada: `ScheduledSyncService`;
- coordinación general: `AppSyncCoordinatorService`;
- contexto operacional: `OperationalContextPullService`;
- outbox común: `LocalSyncOutboxService`.

Reutilizar los batches, mutations, estados, conteos de reintento e idempotency
keys existentes. No reemplazar estos mecanismos de idempotencia o reintento por
otros nuevos sin una decisión arquitectónica explícita.

## Validación y reporte

- Codex puede intentar ejecutar las pruebas relevantes, pero un fallo del
  entorno no autoriza por sí solo un cambio de código.
- Clasificar los resultados de validación como uno de estos casos: fallo real de
  código, fallo de test, fallo de tooling/entorno o prueba que no pudo
  ejecutarse.
- No afirmar que una tarea está validada cuando las pruebas relevantes no se
  ejecutaron o no pudieron completarse.
- Reportar los comandos ejecutados, su resultado y cualquier incertidumbre sin
  corregirla mediante supuestos.
