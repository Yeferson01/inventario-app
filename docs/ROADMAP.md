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
| UI final de inventario | ⏳ | La ruta actual sigue siendo temporal y la pantalla operativa 6.21 no existe. |

## ORG-1 — Onboarding privado de plataforma

- ✅ **ORG-1B — Invitación y aceptación atómica.** La autoridad durable,
  provisioning canónico y primary Branch viven en backend.
- ✅ **ORG-1C — Auth productivo y UX de invitaciones privadas.** El router usa
  sesión Supabase, no existe signup público, el resolver combina contextos e
  invitaciones y la aceptación vuelve a discovery/runtime/bootstrap.
- ⏳ **ORG-1D — Inicialización del catálogo.** Continúa separado de
  `operationalReady`; no forma parte de ORG-1C.

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

## Fase 6.21 — Inventario operativo

**Estado general:** ⏳ pendiente. No fue implementado en el baseline.

**Objetivo:** tener una pantalla real de inventario.

La infraestructura de balances, movements, compras, ventas y backend ya existe,
pero no equivale a la UI final del módulo. La ruta recuperada para esta fase es:

- ⏳ **6.21.1 — Listado de productos con stock.**
- ⏳ **6.21.2 — Buscar por nombre/código.**
- ⏳ **6.21.3 — Ver stock por sucursal.**
- ⏳ **6.21.4 — Ver costo promedio.**
- ⏳ **6.21.5 — Ver stock mínimo.**
- ⏳ **6.21.6 — Ver productos agotados.**
- ⏳ **6.21.7 — Ver productos con bajo stock.**
- ⏳ **6.21.8 — Acceso a movimientos del producto.**

### 6.21.1 — Listado de productos con stock

**Estado:** ⏳ pendiente de inspección, diseño e implementación.

**Fuente operativa:**

- `local_product_stock_balances` para el saldo operativo local por sucursal.

**Trazabilidad:**

- `local_inventory_movements` para el ledger y la trazabilidad local.

**Fuente prohibida como saldo:** `products.stock_quantity` no puede usarse como
saldo operativo. `products.minimum_stock` puede aportar configuración de umbral,
no disponibilidad.

Antes de diseñar o implementar, inspeccionar:

- `ProductStockBalanceLocalDao`;
- `InventoryMovementLocalDao`;
- providers existentes;
- contexto operacional vigente;
- patrones de pantalla y routing ya existentes.

Esta subfase no define todavía SQL, servicios nuevos ni una UI concreta.

## Fase 6.22 — Movimientos de inventario

**Estado general:** ⏳ pendiente.

**Objetivo:** trazabilidad clara.

- ⏳ **6.22.1 — Pantalla de movimientos.**
- ⏳ **6.22.2 — Entradas por compra.**
- ⏳ **6.22.3 — Salidas por venta.**
- ⏳ **6.22.4 — Ajustes manuales autorizados.**
- ⏳ **6.22.5 — Filtros por producto, fecha y tipo.**
- ⏳ **6.22.6 — Detalle del origen: venta, compra, ajuste.**

## Fase 6.23 — Flujo por roles

**Estado general:** ⏳ pendiente.

**Objetivo:** que cada usuario vea y use lo que corresponde.

- ⏳ **6.23.1 — Detectar rol local actual.**
- ⏳ **6.23.2 — Admin/owner: dashboard libre, caja solo para vender.**
- ⏳ **6.23.3 — Cajero: obligado a abrir caja para operar POS.**
- ⏳ **6.23.4 — Bodega: inventario/compras sin caja.**
- ⏳ **6.23.5 — Técnico: sync/configuración/diagnóstico.**
- ⏳ **6.23.6 — Ocultar o bloquear módulos según permisos.**

## Fase 6.24 — Sync programado automático

**Estado general:** ⏳ pendiente.

**Objetivo:** automatizar sincronización según reglas del negocio.

- ⏳ **6.24.1 — Sync automático 11:00.**
- ⏳ **6.24.2 — Sync automático 23:00.**
- ⏳ **6.24.3 — Sync al cerrar caja.**
- ⏳ **6.24.4 — Incluir POS, cash, compras, catálogo e inventario.**
- ⏳ **6.24.5 — Evitar reintentos duplicados.**
- ⏳ **6.24.6 — Logs claros de sync.**

El scheduled actual solo sincroniza catálogo. El coordinator añade la
preparación de runtime y el pull de contexto operacional, pero POS, purchases,
cash e inventory todavía no forman parte de esa cadena. La fase 6.24 representa
la evolución pendiente hacia el comportamiento completo; no está implementada.

## Fase 6.25 — Monitor de sincronización

**Estado general:** ⏳ pendiente.

**Objetivo:** que el usuario vea qué está pendiente o fallando.

- ⏳ **6.25.1 — Pantalla Sync.**
- ⏳ **6.25.2 — Pendientes por dominio: POS, cash, compras, inventario,
  catálogo.**
- ⏳ **6.25.3 — Última sincronización.**
- ⏳ **6.25.4 — Errores y parciales.**
- ⏳ **6.25.5 — Botón de reintento controlado.**
- ⏳ **6.25.6 — Vista técnica para admin/técnico.**

## Fase 6.26 — Reportes básicos

**Estado general:** ⏳ pendiente.

**Objetivo:** empezar operación real con información útil.

- ⏳ **6.26.1 — Reporte de caja diaria.**
- ⏳ **6.26.2 — Ventas del día.**
- ⏳ **6.26.3 — Ventas por método de pago.**
- ⏳ **6.26.4 — Compras del día.**
- ⏳ **6.26.5 — Margen estimado.**
- ⏳ **6.26.6 — Productos más vendidos.**
- ⏳ **6.26.7 — Bajo stock.**

## Fase 6.27 — Recibos y comprobantes

**Estado general:** ⏳ pendiente.

**Objetivo:** operación comercial más completa.

- ⏳ **6.27.1 — Recibo de venta.**
- ⏳ **6.27.2 — Compartir recibo.**
- ⏳ **6.27.3 — Imprimir recibo si hay impresora Bluetooth.**
- ⏳ **6.27.4 — Comprobante de compra.**
- ⏳ **6.27.5 — Consecutivo o número de recibo.**

## Fase 6.28 — Anulaciones, devoluciones y correcciones

**Estado general:** ⏳ pendiente.

**Objetivo:** manejar errores reales de operación.

- ⏳ **6.28.1 — Anular venta.**
- ⏳ **6.28.2 — Devolver producto.**
- ⏳ **6.28.3 — Reintegrar stock.**
- ⏳ **6.28.4 — Registrar motivo.**
- ⏳ **6.28.5 — Permisos por rol.**
- ⏳ **6.28.6 — Sync de anulaciones/devoluciones.**

## Fase 6.29 — Hardening final offline-first

**Estado general:** ⏳ pendiente.

**Objetivo:** dejar la app más resistente.

- ⏳ **6.29.1 — Revisión de idempotencia.**
- ⏳ **6.29.2 — Revisión de outbox local.**
- ⏳ **6.29.3 — Limpieza de batches antiguos.**
- ⏳ **6.29.4 — Manejo de errores de red.**
- ⏳ **6.29.5 — Tests E2E principales.**
- ⏳ **6.29.6 — Validación de datos locales vs remotos.**

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

**6.21.1 — Listado de productos con stock**

**Estado:** ⏳ pendiente de inspección, diseño e implementación.

Antes de implementarlo, inspeccionar la API real de
`ProductStockBalanceLocalDao`, `InventoryMovementLocalDao`, sus providers, el
contexto operacional vigente y los patrones de pantalla/routing ya existentes.
No implementar la subfase desde este documento.
