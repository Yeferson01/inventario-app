# Laboratorio E2E — Caja, POS, compras e inventario

Este documento describe los botones actuales del laboratorio E2E y el flujo correcto para pruebas controladas.

## Estado

La pantalla E2E no es UI final de usuario. Es un laboratorio interno para validar:

- contexto negocio/sucursal
- catálogo offline-first
- inventario local/remoto
- ventas POS offline-first
- compras offline-first
- cash_registers / cash_sessions
- sync outbox
- idempotencia
- reconciliación de stock

## Botones actuales

| Botón | Uso |
|---|---|
| 1–6 | Legacy/debug antiguo. No usar salvo diagnóstico puntual. |
| 7 | Pull stock: trae saldos remotos a local. |
| 8 | Preview stock: muestra productos + stock local. |
| 9 | Crear venta offline: crea venta local y descuenta stock local. |
| 10 | Encolar POS: prepara ventas para sync. |
| 11 | Upload POS: sube ventas/items/pagos y backend descuenta inventario. |
| 12 | Crear compra offline: crea compra local y suma stock local. |
| 13 | Encolar compras: prepara compras para sync. |
| 14 | Upload compras: sube compras/items y backend suma inventario. |
| 15 | Abrir caja local: crea/reutiliza sesión de caja abierta. |
| 16 | Verificar POS/caja: valida si POS puede subirse. |
| 17 | Encolar cash: prepara apertura/cierre de caja para sync. |
| 18 | Upload cash: sube caja/sesión/cierre a Supabase. |
| 19 | Cerrar caja local: cierra sesión y calcula esperado/diferencia. |
| 20 | Resumen cierre caja: muestra reporte local de sesión. |

## Flujo correcto POS con caja

1. Abrir caja local.
2. Encolar cash.
3. Upload cash.
4. Verificar POS/caja.
5. Crear venta offline.
6. Encolar POS.
7. Upload POS.
8. Pull stock.
9. Preview stock.
10. Cerrar caja local.
11. Encolar cash.
12. Upload cash.
13. Resumen cierre caja.

## Reglas importantes

- No subir POS si cash no está sincronizado.
- No vender sin caja abierta.
- No vender con caja cerrada.
- No usar `products.stock_quantity` como fuente de verdad.
- El stock real viene de `inventory_movements` y `product_stock_balances`.
- Las ventas legacy pueden tener `cash_session_id = null`.
- Las ventas nuevas deben tener `cash_session_id` remoto válido.

## Próximo destino

La pantalla E2E debe quedar como laboratorio interno.

La UI real debe usar servicios de aplicación existentes, no llamar directamente a botones debug.
