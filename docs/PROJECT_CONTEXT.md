# Contexto del proyecto CronosManagement

## Qué es CronosManagement

CronosManagement es un sistema de gestión comercial, inventario, punto de venta
(POS) y caja. El frontend se desarrolla en Flutter y el backend se apoya en
Supabase/Postgres.

El producto está concebido como **offline-first** y **multi-negocio / por
sucursal**: la operación diaria parte del estado local del dispositivo, mientras
que el backend consolida información, aplica seguridad multi-tenant y permite la
sincronización entre instalaciones.

## Objetivos funcionales principales

El sistema reúne estos ámbitos funcionales:

- POS para registrar ventas, sus ítems y sus medios de pago sin depender de una
  conexión permanente;
- caja para abrir y cerrar sesiones, asociar ventas y mantener la secuencia
  operacional de cada sucursal;
- compras con detalle de productos, referencias de proveedor e impacto en
  inventario;
- inventario por producto y sucursal, con saldo operativo y trazabilidad de sus
  movimientos;
- catálogo propio del negocio y catálogo maestro local para búsqueda por código
  de barras, sugerencias y creación de productos;
- clientes y, donde corresponde, proveedores: el baseline local incluye
  clientes; compras conserva datos/referencias de proveedor y el backend dispone
  de soporte remoto para proveedores, sin que eso implique una feature Flutter
  final dedicada;
- membresías, roles y permisos dentro de cada negocio;
- sincronización offline/online con operaciones idempotentes, reintentos y
  reconciliación;
- trazabilidad de las operaciones comerciales y del inventario;
- contexto operacional explícito de negocio, sucursal, perfil y dispositivo.

## Principios de producto

- **Offline-first real.** Las operaciones compatibles con el modelo actual se
  escriben primero en local y la UI se alimenta del estado local.
- **Operación inmediata.** Una pérdida temporal de conectividad no debe impedir
  vender ni registrar el trabajo que el dispositivo puede resolver localmente.
- **Identidad local.** Las entidades nuevas usan IDs generados en el cliente; no
  esperan una identidad asignada por el servidor.
- **Sincronización posterior.** La subida remota ocurre después de la escritura
  local y conserva separadas la operación local, el outbox y la aplicación en
  servidor.
- **Idempotencia.** Batches, mutations, client IDs, secuencias e idempotency keys
  permiten reintentar sin duplicar el efecto de negocio.
- **Borrado lógico.** Las entidades de negocio no deben depender de hard delete;
  el contrato usa soft delete/tombstones donde corresponde.
- **Trazabilidad.** Las ventas, compras, sesiones de caja y variaciones de
  inventario deben conservar el origen y la secuencia necesarios para auditar su
  efecto.
- **Catálogo local primero.** Un escaneo consulta el producto local y luego el
  catálogo maestro local; no realiza una consulta a Supabase por cada código de
  barras.
- **Inventario por sucursal.** Un mismo producto puede tener saldos distintos en
  cada branch.
- **Saldo operativo separado del producto.** `products.stock_quantity` es un
  campo legacy y no es la fuente de verdad. El saldo local operativo está en
  `local_product_stock_balances` y la trazabilidad local en
  `local_inventory_movements`. Campos de configuración como
  `products.minimum_stock` conservan su finalidad y no representan el saldo.

## Contexto técnico

El frontend usa Flutter/Dart, Riverpod para composición y estado, GoRouter para
navegación, Drift/SQLite para persistencia local y Supabase Flutter para acceso
remoto.

El backend es Postgres administrado mediante Supabase. Su evolución está
versionada en migraciones e incluye políticas RLS, RPCs, procesamiento de sync,
catálogo, POS/caja, compras e inventario. La presencia de infraestructura remota
no demuestra por sí sola que exista una pantalla Flutter final que la consuma.

La descripción detallada de capas y flujos vigentes está en
[ARCHITECTURE.md](ARCHITECTURE.md).

## Conceptos de dominio relevantes

| Concepto | Significado en el baseline |
| --- | --- |
| `business` | Tenant o negocio propietario de la información operacional. |
| `branch` | Sucursal dentro de un negocio; delimita operaciones como caja e inventario. |
| `profile` / `membership` / `role` | El perfil identifica al usuario en la aplicación; la membresía lo vincula con un negocio y su contexto; el rol aporta permisos dentro de ese ámbito. |
| `app device` / `installation` | La instalación mantiene una identidad estable en el cliente y se registra/actualiza como dispositivo de aplicación en remoto para el runtime y la sincronización. |
| `cash register` | Caja perteneciente a un negocio y una sucursal. |
| `cash session` | Apertura operacional de una caja, con responsable, montos y estado hasta su cierre o cancelación. |
| `product` | Producto comercial propio del negocio, con precios y datos de configuración. |
| `master product` / catálogo maestro | Referencia global descargada al dispositivo para resolver códigos de barras y sugerir datos sin consultar remoto en cada escaneo. |
| `purchase` | Compra local/remota con ítems, proveedor cuando aplica e incremento de inventario. |
| `sale` | Venta con ítems y pagos, vinculada a sucursal y, para el flujo POS, a su contexto de caja. |
| `inventory movement` | Evento del ledger que explica una entrada, salida o ajuste de existencias. |
| `product stock balance` | Saldo operativo agregado de un producto en una sucursal. |
| `sync batch` | Agrupación ordenada de mutations de un dominio para una subida y su seguimiento. |
| `sync mutation` | Operación individual, identificada e idempotente, sobre una entidad sincronizable. |
| `sync conflict` | Divergencia detectada durante sync y registrada en el backend con datos y estado de resolución; el esquema Drift actual no define una tabla local equivalente. |

## Estado actual resumido

[CURRENT_STATE.md](CURRENT_STATE.md) es la fuente autoritativa para la fotografía
del baseline recuperado. En resumen:

- la fase **6.20**, producto rápido desde Compras, está implementada
  funcionalmente;
- **6.21**, inventario operativo, es la siguiente fase;
- la UI final de inventario correspondiente a 6.21 aún está pendiente y no debe
  inferirse a partir de infraestructura, laboratorios ni código posterior ajeno
  al baseline.

## Qué no debe inferir un agente

- Que una tabla, política, RPC o migración del backend implica una UI final en
  Flutter.
- Que la existencia de una carpeta de feature demuestra que esa feature está
  terminada.
- Que un documento histórico representa el estado actual sin contrastarlo con
  el código del baseline.
- Que una pantalla o servicio E2E/debug define la UI final o el modelo de
  producto terminado.
- Que `features/pos` contiene el POS operacional actual: esa carpeta es un
  scaffold sin implementación operacional relevante; el flujo POS real de este
  baseline vive en `features/sales`.

Las reglas operativas para agentes, el alcance permitido y la disciplina de Git
pertenecen a [AGENTS.md](../AGENTS.md), no a este documento de contexto.
