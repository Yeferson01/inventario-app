# Contrato UI real — Caja y POS

Este documento define cómo deben comportarse las pantallas reales de caja y POS.

## Pantallas objetivo

### Caja

Pantallas previstas:

- Estado de caja
- Abrir caja
- Cerrar caja
- Resumen de caja
- Historial de sesiones

### POS

Pantallas previstas:

- Venta POS
- Búsqueda de producto
- Carrito
- Pagos
- Confirmación de venta
- Estado de sincronización

## Flujo de apertura

La pantalla de caja debe:

1. Resolver negocio/sucursal actual.
2. Consultar si ya existe una caja abierta.
3. Si no existe, pedir monto de apertura.
4. Crear cash_session local.
5. Encolar cash.
6. Subir cash.
7. Permitir POS solo cuando cash esté sincronizado.

## Flujo de venta

La pantalla POS debe:

1. Verificar caja abierta.
2. Verificar que la caja esté sincronizada.
3. Buscar producto local.
4. Verificar stock local disponible.
5. Crear venta local.
6. Crear sale_items.
7. Crear sale_payments.
8. Crear inventory movement local negativo.
9. Actualizar stock local.
10. Encolar POS.
11. Subir POS cuando haya conexión.
12. Pull stock para reconciliar.

## Flujo de cierre

La pantalla de cierre debe:

1. Calcular efectivo esperado.
2. Mostrar ventas de la sesión.
3. Mostrar pagos por método.
4. Pedir monto contado.
5. Calcular diferencia.
6. Cerrar cash_session local.
7. Encolar cash.
8. Subir cash.
9. Bloquear nuevas ventas hasta abrir nueva caja.

## Reglas de bloqueo

La UI debe bloquear ventas si:

- No hay caja abierta.
- La caja abierta no está sincronizada.
- La sesión está cerrada.
- No hay stock suficiente.
- No hay contexto negocio/sucursal.
- El producto no existe localmente.

## Servicios existentes a reutilizar

- `CashSessionLocalService`
- `CashSyncOutboxService`
- `CashSyncUploadService`
- `PosLocalSaleService`
- `PosSyncOutboxService`
- `PosSyncUploadService`
- `ProductStockBalanceLocalService`
- `CatalogLocalRepository`
- `AppE2ELocalFlowService` solo para laboratorio/debug, no para UI final.

## Principio

La UI final no debe implementar lógica de negocio directamente. Debe llamar servicios de aplicación.
