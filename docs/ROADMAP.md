# Roadmap oficial de continuidad

Este documento registra qué está consolidado, qué es parcial y cuál es el
siguiente paso. La fotografía detallada del baseline sigue en
[CURRENT_STATE.md](CURRENT_STATE.md). No se considera completa una UI solo
porque exista infraestructura backend, una carpeta o un laboratorio E2E.

## Leyenda

- ✅ **Completado:** funcionalidad o infraestructura implementada en su alcance.
- 🟡 **Parcial / infraestructura disponible:** existe una base utilizable, pero
  falta integración o UI final.
- ⏳ **Pendiente:** no implementado en el baseline.
- 🧪 **Validación/laboratorio:** evidencia controlada que no constituye UI final
  ni una suite integral por sí sola.

## Baseline

- ✅ Baseline funcional recuperado:
  `8d1b8f4876b8934e54dc15e86fa5411158758bd3` (`8d1b8f4`).
- ✅ Contrato operativo y fotografía del estado:
  `1797804 docs: establish project agent rules and baseline state`.
- ✅ Contexto y arquitectura vigentes:
  `5b15be0 docs: document project context and current architecture`.

Los commits documentales describen y gobiernan el baseline; no añaden por sí
mismos funcionalidad de producto.

## Backend consolidado

Las migraciones presentes permiten clasificar como infraestructura backend
consolidada:

- ✅ foundations, esquema inicial y metadatos operacionales/versionados;
- ✅ multitenancy por negocio/sucursal, membresías, roles y permisos;
- ✅ helpers, índices, policies y RLS para aislamiento y seguridad;
- ✅ POS y caja: registros, sesiones, pagos, secuencias y totales;
- ✅ inventario remoto: `inventory_movements`,
  `product_stock_balances`, aplicación de movimientos, conteos y transferencias;
- ✅ sync: batches, mutations, cursors, conflicts, procesamiento, resolución,
  observabilidad e idempotencia;
- ✅ catálogo offline/master, barcodes, contribuciones, lookup y pull delta;
- ✅ compras y aplicación idempotente de su efecto en inventario;
- ✅ pull paginado y mecanismos de reconciliación remotos.

Esta consolidación no marca como completadas las pantallas Flutter de
inventario, transferencias, conteos o conflictos.

## Frontend offline-first

| Área | Estado | Evidencia actual |
| --- | --- | --- |
| Runtime y contexto operacional | ✅ | Registro de instalación/dispositivo, setup remoto, selección business/branch/profile, permisos y pull de snapshot. |
| Catálogo local/master | ✅ | Tablas Drift, pull delta, barcode lookup local y contribuciones/outbox. |
| Creación de producto | ✅ | Creación local desde master y creación manual con IDs y mutaciones de catálogo. |
| POS local | ✅ | Venta, ítems, pagos e impacto local de inventario en `features/sales`. |
| Caja | ✅ | Apertura/cierre local, dashboard, outbox y upload de caja. |
| Compras | ✅ | Compra e ítems locales, pantalla de entrada e impacto positivo en inventario. |
| Outbox común | ✅ | `local_sync_batches`, `local_sync_mutations`, estados, retries e idempotency keys. |
| Uploads por dominio | ✅ | Servicios separados para catalog, POS, purchases, cash e inventory. Esto no significa que todos estén en scheduled sync. |
| Saldos locales de producto | ✅ | `local_product_stock_balances`, lecturas por sucursal, streams y pull remoto. |
| Movimientos locales de inventario | ✅ | `local_inventory_movements` con origen, referencia, idempotencia y estado de sync. |
| Reparación/idempotencia de compras | ✅ | Reparación de batches, reconciliación y manejo `completed_remote_already_exists`. |
| UI final de inventario | ⏳ | La ruta actual sigue siendo temporal y el dashboard operativo 6.21 no existe. |

## 6.20 — Producto rápido desde Compras

**Estado general:** ✅ completado funcionalmente.

La continuidad oficial identifica estas subfases:

- ✅ **6.20.1 — Botón Crear producto rápido.** La acción está disponible en la
  pantalla de Compras.
- ✅ **6.20.2 — Formulario mínimo.** La UI recoge los datos necesarios para el
  alta rápida.
- ✅ **6.20.3 — Crear producto local.** El producto recibe ID local y se persiste
  antes de depender del servidor.
- ✅ **6.20.4 — Agregar al carrito.** El producto creado puede entrar en la
  compra en curso.
- ✅ **6.20.5 — Catálogo/master sync, reparación e idempotencia.** El flujo
  prepara catálogo antes de compras cuando hace falta y dispone de reparación y
  reconciliación.
- ✅ **Fixes hasta 6.20.5O.** La continuidad oficial agrupa bajo este límite los
  fixes de idempotencia y reconciliación. El repositorio no conserva una lista
  documental individual de cada sufijo 6.20.5A–6.20.5O; no se reconstruyen
  nombres intermedios por intuición.
- 🧪 **6.20.6 — Validación integral.** La funcionalidad fue validada de forma
  distribuida observando productos remotos, `purchase_items`, el resumen y
  `inventory_movements`. No se encontró una prueba automatizada única ni un acta
  formal que represente por sí sola toda esta subfase.

El commit funcional representativo es
`6f031c7 feat: support quick product creation from purchases with catalog sync repair`,
incluido en el baseline recuperado.

## 6.21 — Inventario operativo

**Estado general:** ⏳ pendiente. No fue implementado en el baseline.

La infraestructura de balances, movements, compras, ventas y backend ya existe,
pero no equivale a la UI final del módulo.

### 6.21.1 — Dashboard de inventario

**Estado:** ⏳ pendiente de diseño e implementación.

**Fuentes obligatorias del estado:**

- `local_product_stock_balances` para el saldo operativo local por sucursal;
- `local_inventory_movements` para ledger y trazabilidad.

**Fuente prohibida como saldo:** `products.stock_quantity` no puede usarse como
saldo operativo. `products.minimum_stock` puede aportar configuración de umbral,
no disponibilidad.

**Objetivos iniciales conocidos, todavía no implementados:**

- KPIs de inventario;
- productos con poco stock;
- movimientos recientes;
- valor de inventario usando saldo y costo operativo cuando corresponda.

Esta definición no fija todavía SQL, archivos ni una solución de UI.

## Posterior a 6.21

La numeración exacta de estas fases no está confirmada. Se mantienen como
capacidades posteriores descriptivas, sin asignarles números:

- ⏳ listado operativo de inventario;
- ⏳ detalle de producto y kardex;
- ⏳ ajustes de inventario;
- ⏳ alertas y operación de poco stock;
- ⏳ valor de inventario;
- 🟡 transferencias: backend disponible, UI pendiente;
- 🟡 conteos y operación avanzada: infraestructura backend disponible, UI/flujo
  final pendiente cuando corresponda.

## Deudas técnicas e integraciones pendientes

- 🟡 Scheduled sync solo cubre catálogo; no integra POS, purchases, cash ni
  inventory.
- 🟡 `CashCloseSyncTriggerService` existe y tiene provider, pero no está
  consumido por la UI actual.
- 🟡 El POS operacional vive en `features/sales`; `features/pos` sigue como
  scaffold. No hay una decisión confirmada de reorganización.
- 🟡 El backend tiene `sync_conflicts`, pero schema Drift 8 no tiene tabla local
  equivalente ni una solución local decidida.
- ⏳ La UI final de inventario 6.21 está pendiente.

## Próximo paso exacto

**6.21.1 — Dashboard de inventario**

Antes de implementarlo, inspeccionar la API real de
`ProductStockBalanceLocalDao`, `InventoryMovementLocalDao`, sus providers y el
contexto operacional vigente. No implementar el dashboard desde este documento.
