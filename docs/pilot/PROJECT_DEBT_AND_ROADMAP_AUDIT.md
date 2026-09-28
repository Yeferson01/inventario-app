# Cronos POS — deuda técnica y ruta al primer piloto

Auditoría read-only del 28-09-2026. Este documento es una fotografía del commit indicado, no una garantía sobre datos Hosted o dispositivos que no se pudieron consultar en esta sesión. Las rutas son relativas a la raíz del repositorio. No se modificó código ni datos durante la auditoría.

## Executive Summary

La base funcional del piloto existe: POS, compras, caja, inventario por sucursal, onboarding, sincronización productiva y tres vistas de reportes. Existe una APK universal release firmada para distribución manual. **Aún no debe declararse aceptado el primer piloto**: faltan una aceptación manual reproducible del APK, una prueba de entrada offline en el dispositivo que mostró un blocker, cierre de fallos de la suite Flutter, paridad de migraciones Hosted verificable y un procedimiento de backup/recuperación ensayado. La estimación de avance hacia *piloto aceptado* es **~80 %**, juicio cualitativo basado en capacidades presentes frente a cinco gates pendientes; no es cobertura de tests ni porcentaje de roadmap formal.

Registro: **1 P0, 4 P1, 7 P2, 5 P3 y 2 P4**. Hay **5 gates de piloto** (un incidente funcional y cuatro verificaciones/operaciones pendientes). P0 no afirma que el código de readiness sea incorrecto: el incidente offline observado aún necesita causalidad en un dispositivo con datos reales.

## Verified Baseline

- Rama `feature/foundation-core`; HEAD `4be7697dde48486e0375756d09331cdb67f0b7b6` (`chore: bump pilot build to 1.0.0+2`). Entre los commits recientes: orden del Dashboard `4c079e4`, identidad `e23fc24`, UX `7ba23d0`, sync-status de caja `b088543`, cash flow `fb8c287`. La referencia local `origin/feature/foundation-core` está 39 commits detrás y 0 delante; **no se hizo fetch**, por lo que no informa del servidor actual.
- Ningún archivo tracked modificado al inicio. Untracked históricos en `inventario-Backend/tools/catalog_import/reports/`, `tmp/` y `inventario-Frontend/releases/`; no se tocaron. `git diff --check` inicial: PASS. El único cambio de esta tarea es este informe.
- `inventario-Frontend/pubspec.yaml`: `1.0.0+2`, Dart `>=3.3.0 <4.0.0`. Drift resuelto `2.33.0`, Riverpod `3.3.1`, GoRouter `17.3.0` en lockfile. Código: 310 archivos Dart bajo `lib/`, 125 archivos de test Flutter; backend: 142 migraciones y 38 archivos de tests SQL (conteo de archivos, no de assertions).
- Drift `AppDatabase.schemaVersion == 17` (`lib/core/database/app_database.dart:1270`). `beforeOpen` activa `pragma foreign_keys = on` (`:2025`). `onCreate` crea tablas e índices; `onUpgrade` contiene rutas aditivas por versión 3–17 (`:1843–2023`). `app_database_migration_test.dart` cubre 8→17, 9→17, 10→17, 12→17 y 16→17 y pasó en esta sesión.
- APK `inventario-Frontend/releases/Cronos-POS-Pilot-1.0.0-build2.apk`: 70.876.613 bytes; SHA-256 `BF42C2BD8BFA3DED74FFE4F7A874A4C4DC55C98CC5556BD4CC25706D263076F8`. La verificación técnica previa de P2.8 lo identificó como release universal, `com.cronosmanagement.app`, `1.0.0+2`, firmado con certificado no-debug; esta sesión confirmó archivo/hash/configuración, **no instaló ni volvió a verificar el certificado del APK**. `android/key.properties` existe, está ignorado; el `storeFile` configurado existe fuera del repositorio. No se leyó ni imprimió secreto.
- `config/prod.json` existe y está tracked con claves de configuración públicas/anon (`APP_NAME`, `ENVIRONMENT`, `API_URL`, `SUPABASE_URL`, `AUTH_REDIRECT_URL`, `SUPABASE_ANON_KEY`); no se imprimieron valores. `AndroidManifest.xml` principal declara INTERNET, nombre `Cronos POS`, callback `cronosmanagement://auth-callback`, y deshabilita el handler deep-link integrado para dejar `app_links/supabase_flutter` como dueño. `app_router.dart:44,68–94,164–168` registra/bloquea rutas debug solo en `kDebugMode`.
- El estado Hosted *actual* no quedó verificado: `pnpm dlx supabase migration list --linked` se interrumpió al fallar la descarga npm (`ECONNRESET`); no se mostró ni utilizó ninguna credencial y no hubo writes. Las migraciones locales finales revisadas incluyen S1/S1A/C4A1, evento temporal de pago y cash-flow RPC (`20260927131000`). Que un smoke anterior haya validado Hosted no sustituye la comparación linked de hoy.
- `docs/ROADMAP.md`, `CURRENT_STATE.md`, `ARCHITECTURE.md`, `DECISIONS.md` y `TESTING.md` conservan una fotografía anterior (p. ej. schema 8, sync programado solo de catálogo y 36 tests) y **no describen el HEAD**; se usan solo como historia, no como prueba de implementación actual.

### Validación ejecutada y clasificación

| Comando / alcance | Resultado | Clasificación |
|---|---|---|
| `flutter analyze --no-pub` | 28 diagnósticos: 1 error, 27 infos, 0 warnings; error en `purchase_product_dependency_test.dart:508` por fake que no implementa `inspectPermissionRetry` / `finalizePermissionRetry` | Fallo de test/fake; impide análisis limpio del proyecto |
| `flutter test --no-pub` focal de `local_cash_movements_test.dart` y `report_snapshot_local_dao_test.dart` | 23 PASS / 3 FAIL: schema 14 esperado vs 17, fixture 13→14 construido desde schema actual que intenta añadir `sale_id` otra vez, schema 13 esperado vs 17 | Fixtures/assertions desactualizados; el fallo no demuestra que una migración real falle |
| `flutter test --no-pub test/features/sync/purchase_product_dependency_test.dart` | No compila por los dos métodos faltantes en fake | Fallo de test; producción no evaluada por este comando |
| `flutter test --no-pub` de `app_database_migration_test.dart`, `offline_operational_readiness_service_test.dart`, `productive_scheduled_sync_service_test.dart` y `cash_flow_report_service_test.dart` | 25 PASS / 2 FAIL; solo OR-01 y OR-08 fallan | El fixture de readiness omite `cash_pos/cash_movements`, ahora requerido por `CashPosSnapshotApplier.datasets`; 6/6 migraciones, 10/10 scheduled y 5/5 cash-flow service pasaron |
| Búsqueda de `skip:` / `@Skip` en tests | Ningún test skipped explícito hallado; `.skip(1000)` es paginación de datos | No demuestra ausencia de flakiness; suite global no ejecutada |
| `git diff --check` | PASS inicial | Repetir al cerrar informe |

## Roadmap Status

| Fase | Estado a HEAD | Evidencia / límite |
|---|---|---|
| P2.0 Pilot audit | COMPLETE WITH DEBT | Roadmap histórico existe, pero desactualizado; este informe recompone el baseline. |
| P2.1 Release / operational gate | COMPLETE WITH DEBT | APK, firma release, paquete e identidad presentes; falta aceptación manual y diagnóstico offline. |
| P2.2 Financial integrity | COMPLETE WITH DEBT | Snapshots de costo en POS/sync y RPC de margen; costos históricos rellenados requieren advertencia de calidad. |
| P2.3 Sync contract + recovery UX | COMPLETE WITH DEBT | `ProductiveManualSyncService` recorre catálogo→caja→POS→compras→inventario, hasta 8 pasadas acotadas; scheduled y cash-close lo integran. Incidente offline pendiente. |
| P2.4 Registration & onboarding | COMPLETE WITH DEBT | Registro, invitaciones, aceptación, creación self-service, selector y bootstrap presentes. Falta aceptación real multinegocio en release. |
| P2.5 Movements & history | COMPLETE WITH DEBT | Historial hidratado y ajustes/transferencias presentes; no equivale a contabilidad completa ni a void/refund productivo. |
| P2.5X Operational pilot gaps | COMPLETE WITH DEBT | Cash movements offline, S1/S1A, cash-flow snapshot y cierre de caja tienen contratos/tests; faltan prueba real y UX compra→salida. |
| P2.6 Reports | PARTIAL | Ventas, margen y cash flow implementados; inventario, compras y export no tienen implementación productiva comparable. |
| P2.7 UX productization | COMPLETE WITH DEBT | Orden del Dashboard, marca, icono/splash y varios mensajes productivos; tablets y accesibilidad requieren smoke. |
| P2.8 Delivery acceptance / release | PARTIAL | APK técnica construida; instalación/reinstalación/upgrade manual y procedimiento de distribución pendientes. |
| P2.9 First real pilot | NOT STARTED | No hay evidencia de operación diaria controlada bajo checklist de este informe. |

## Debt Register

Severidad: **P0** = pérdida/corrupción/seguridad o bloqueo operativo plausible y observado; **P1** = importante antes del piloto; **P2** = conveniente durante piloto; **P3** = post-piloto; **P4** = expansión futura. “Pilot blocker” marca un gate que debe cerrarse con evidencia; no siempre indica código defectuoso. Los paths son *probables* para un futuro fix, no autorización de cambio.

| ID | Área | Deuda | Evidencia | Sev. | Pilot blocker | Riesgo | Dependencias | Solución propuesta | Archivos probables | Tests necesarios | Momento recomendado |
|---|---|---|---|---|---|---|---|---|---|---|---|
| D01 | Recovery/offline | Moto mostró blocker sin Wi-Fi antes del Dashboard; falta diagnóstico de estado real | Incidente comunicado; gate en `business_context_required_gate.dart:553–604`; `offline_operational_readiness_service.dart:83–206` distingue auth/runtime/checkpoints/issues/caja | P0 | Sí | Tienda sin entrada offline pese a datos válidos, o bypass inseguro si se relaja a ciegas | D04 | Capturar resultado tipado y checkpoints/issue del dispositivo; reproducir con fixture; corregir solo si se prueba falso positivo | `business_context_required_gate.dart`, `offline_operational_readiness_service.dart`, tests focales | Estado completo permite Dashboard; incompleto/revoked bloquea; caja cerrada válida permite Dashboard | Antes del primer piloto |
| D02 | Release acceptance | APK no aceptada aún en flujo manual completo | Artefacto firmado existe; no hubo instalación ni prueba física de build 2 en esta sesión | P1 | Sí | Distribuir un APK que no complete login, auth, Caja, POS, Inventario, Compras o Sync | D01, D03, D05 | Ejecutar matriz manual en dispositivo limpio designado; conservar evidencia y hash; no operar cuentas reales antes de PASS | Checklist de este informe; quizá tests de UI si surge defecto | Instalación, identidad, auth, bootstrap, operación y segundo arranque | Antes del primer piloto |
| D03 | Operación/backup | No hay runbook de backup+restore probado para datos piloto | Backup pre-ORG histórico en contexto; `docs/TESTING.md` no es runbook de restauración piloto | P1 | Sí | Pérdida de datos o recuperación improvisada; reset local/Hosted no es rollback | D05 | Confirmar plan Hosted/retención; export cifrado fuera del repo, hash, restauración en entorno aislado, custodia; plan para Drift con pendientes | Runbook operativo futuro, herramientas existentes de dump/restore; no código obligatorio | Restore de ensayo y comparación de conteos/hashes, nunca sobre Hosted piloto | Antes del primer piloto |
| D04 | Calidad | Suite/analyze no verdes por fixtures schema 13/14 y fake de compras; OR-01/08 fixture omite cash movements | Resultados focales anteriores; `local_cash_movements_test.dart:70,88`, `report_snapshot_local_dao_test.dart:21`, `purchase_product_dependency_test.dart:508`, `offline_operational_readiness_service_test.dart:177–187` | P1 | Sí | Regresiones reales quedan ocultas y no existe release gate automatizado confiable | Ninguna | Actualizar fixtures históricos genuinos y fake, no producción; correr analyzer y suite completa, clasificar cualquier fallo restante | Esos 4 tests; fixture de migración | v13/14/16→17, OR-01/08, compra retry, suite global | Antes de aceptación final |
| D05 | Backend/release | Paridad exacta de migraciones Hosted vs HEAD no comprobada hoy | 142 migraciones locales; consulta linked bloqueada por npm `ECONNRESET` | P1 | Sí | APK llama RPC/columnas aún no desplegados en un entorno concreto | Acceso read-only seguro | Reintentar `migration list --linked` con CLI ya instalada/caché o panel; cotejar últimas versiones y contratos sin writes | Ninguno | Consulta de versión y smoke read-only por RPC; pgTAP local cuando haya cambios | Antes de aceptación final |
| D06 | Compras/caja UX | Compra no ofrece atajo directo “Registrar salida de efectivo” | `purchase_entry_screen.dart:775–854` solo guarda compra/stock; `CashMovementDialog` se abre desde `cash_dashboard_screen.dart:306,680–683`; categoría `supplier_purchase` existe | P2 | No | Operador olvida salida o asocia manualmente mal; no afecta inventario | D02 | Acción posterior y opcional tras compra que navegue a Caja/dialog con categoría y referencia prellenadas, usando `CashMovementService`; no crear `purchase_payments` | purchase screen/application, cash dialog/provider | Compra no genera cash automáticamente; salida idempotente/autorizada; offline/outbox | Durante piloto tras estabilizar base |
| D07 | Rentabilidad | Snapshots históricos no nulos pueden ser costo de backfill, no costo capturado en venta | `20260616194609_pos_sale_items_snapshots_totals.sql:67–95` usa `products.purchase_price`; RPC P2.6B1 trata no-null como conocido | P2 | No, con política | Margen histórico puede parecer exacto sin serlo | D05 | Delimitar fecha/cohorte confiable con evidencia de Hosted; etiquetar históricos como aproximados o restringir período; jamás recalcular desde costo actual | RPC/report UI solo si se decide cambiar política | Cohortes pre/post, NULL, permisos `sales.view_costs`, etiqueta visible | Durante piloto antes de decisiones financieras |
| D08 | Tablets/accesibilidad | Adaptación no aceptada en pantallas de 7–10″, landscape y texto grande | POS usa umbral ancho 900 (`pos_sale_screen.dart:991`), Dashboard grid adaptable (`main_dashboard_screen.dart:1150`); no prueba física completa | P2 | No para piloto de teléfono; sí si tablet es dispositivo inicial | Overflow/taps pequeños/teclado obstruye cobrar | D02 | Smoke en tamaño objetivo y escala texto 1.3/1.5; corregir únicamente findings reproducidos | Screens Dashboard/POS/Caja/Inventario/Compras | Widget goldens/overflow a 360/600/900dp y landscape | Durante piloto antes de añadir tablets |
| D09 | Onboarding multinegocio | Falta prueba real de aceptación de invitación B mientras se opera A en release | `business_context_required_gate.dart:160–201` llama stabilization con business/branch aceptados; entry conserva selección profile-scoped y exige selector si hay múltiples | P2 | No en tienda de un negocio | Usuario cree estar en B pero continúa en A, o cambio inesperado | D02 | Smoke A→invitar B→aceptar→seleccionar B→reiniciar/offline; cotejar scope de caja/stock, sin forzar auto-switch por inferencia | Gate/stabilization/selection tests si se observa fallo | Contextos A/B, revocación, logout/login, restart | Durante piloto multinegocio |
| D10 | Observabilidad | No hay runbook de señales y respuesta de primer nivel | `activity_logs`, `sync_logs`, outbox/issue/status existen; `AppLogger` y mensajes UI, pero no proceso de revisión operativa demostrado | P2 | No si acompañamiento manual diario | Errores/pendientes pasan inadvertidos | D03 | Definir revisión diaria de pending/partial, issues, cierre de caja, storage/db, sin tokens; códigos y umbrales de escalado | Procedimiento y quizá export de diagnóstico no sensible | Simular pending, partial y error; verificar captura redactada | Durante piloto |
| D11 | Catálogo | Calidad, procedencia y licencia de imágenes/datos requieren gobernanza continua | Tooling conserva `image_source_key`/`image_license` (`tools/catalog_import/README.md:230`); datasets/reports históricos untracked; importador y master catalog existen | P2 | No para surtido curado del piloto | Código erróneo, identidad duplicada o uso no autorizado de assets | D03 | Curar solo surtido piloto, trazabilidad fuente/licencia, auditoría de códigos y proceso de corrección reversible; no importar datasets masivos durante operación | Tooling/catalog UI/registro de curation | Barcode único, producto provisional, imagen 404, rollback de lote | Durante piloto |
| D12 | Retry/estado parcial | Cobertura de recuperación de partial/blocked tras operación real necesita matriz operacional | Outbox tiene dependencias y ocho pasadas acotadas; D01 muestra estado real bloqueado; no se ejecutó matriz de desconexión/reintento actual | P2 | No tras D01/D02 si aceptación controlada pasa | Pendientes antiguos o duplicados por acciones manuales indebidas | D04 | Probar corte de red entre local/remote ACK y cierre, reintento sin duplicación, opción de soporte sin borrar datos | tests de sync/recovery por dominio | Invariantes de IDs, outbox, balances, cash en retry | Durante piloto controlado |
| D13 | Reportes | Inventario, Compras y Export productivos faltan | `features/reports` solo implementa sales/profitability/cash_flow; permissions `reports.inventory`/`reports.export` existen | P3 | No | Operación usa vistas y export manual supervisado | Pilot data estable | Diseñar RPC agregado por branch/período, cache profile-scoped, capability, UI y tests por reporte | `features/reports`, migraciones futuras | Scope, total, NULL, offline cache, revocation, export | Post-piloto |
| D14 | Ventas | Void/refund/reversal de venta completada no es flujo productivo | Backend tiene columnas `voided_*` y permissions `sales.void`/`sales.refund`; búsqueda en `features/sales` muestra POS/repair de venta no materializada, no UI de devolución | P3 | No con procedimiento manual administrativo para excepciones | Correcciones comerciales no automáticas | Política financiera/stock | Definir contrato contable y ledger inverso antes de UI | POS/backend futuro | Doble void, refund parcial, efectivo/stock | Post-piloto |
| D15 | Administración | Lifecycle de members/roles/devices/subscriptions incompleto | UI administración lista sucursales e invitaciones; `administration_home_screen.dart:19–70`; roles delegables limitados | P3 | No en piloto de una tienda | Gestión manual de revocaciones/cambio de dispositivo | Seguridad/política de identidad | Definir ORG-3 y UI autorizada para revocar/cambiar/retirar, sin borrar devices de pruebas manualmente | administración y RPCs futuros | Cross-tenant, revocación, role custom | Post-piloto |
| D16 | Documentación | Docs de arquitectura/roadmap/testing contradicen HEAD | `ARCHITECTURE.md` y `TESTING.md` dicen schema 8/36 tests; HEAD schema 17/125 tests | P3 | No con este informe vigente | Agentes futuros actúan sobre un baseline falso | D04 | Actualizar docs después de consolidar pilot gate; conservar decisiones históricas con fecha | `docs/*` | Revisión contra código y tests | Post-aceptación |
| D17 | Dependencias | 27 infos/deprecations y contrato Flutter/Gradle requieren mantenimiento | Analyzer; `pubspec.yaml` constraints; Gradle placeholder TODO de applicationId ya resuelto en valor | P3 | No | Upgrade futuro más costoso | Piloto estable | Actualizar en rama separada con matriz de migración, no junto con aceptación | pubspec/Android/UI | Full analyze, tests, build | Post-piloto |
| D18 | Finanzas | `purchase_payments`, deuda a proveedor y contabilidad de doble entrada deliberadamente diferidos | Modelo `CashMovementCategoryMetadata` documenta que `supplier_purchase` clasifica efectivo y **no** es pago de compra; C4C1 pospuesto | P4 | No | No se puede calcular CxP ni pagos parciales | Decisión de producto/contabilidad | Diseñar ledger financiero y migración cuando haya necesidad real | Backend/Drift/reportes futuros | Accounting invariants y migration | Versión completa |
| D19 | Distribución/analytics | Play Store, telemetry avanzada, pipeline multi-entorno | Piloto es APK manual con Hosted actual; sin publicación store | P4 | No | Escalabilidad de distribución y diagnóstico | Piloto | Diseñar firma/canales/versioning/privacidad después de medir uso | Android/CI/ops | Upgrade in-place y rollout | Expansión |

## P0/P1/P2 Priority Debt

La P0 D01 exige *diagnóstico antes de fix*. P1 D02–D05 son gates verificables. P2 D06–D12 se pueden ordenar durante el piloto sin bloquear una tienda/dispositivo bajo acompañamiento, salvo que su escenario sea parte explícita de la aceptación (p. ej. tablet o multinegocio).

### Mini-planes ejecutables

1. **D01 — Offline gate.** (1) Sin writes, capturar outcome/reason y scope del dispositivo, authorizationValidatedAt, runtime IDs, checkpoints y blockers redactados. (2) Comparar con `OfflineOperationalReadinessService.evaluate` y gate de UI; distinguir falta real de dataset de caché stale. (3) Reproducir estado exacto en test con `NativeDatabase.memory`. (4) Solo si hay falso positivo, fijar condición mínima sin relajar revoked/scope/issue. (5) Aceptar online→offline→restart con caja cerrada y operación local pendiente.
2. **D02 — APK acceptance.** (1) Registrar hash/certificado/versionCode del archivo entregado. (2) Instalar manualmente en dispositivo limpio o compatible y autenticar. (3) Recorrer bootstrap, Dashboard, Caja, POS, Inventario, Compras, Reportes, Sync; reiniciar y cortar red controladamente. (4) Tomar resultados PASS/WARN/FAIL sin crear ventas/cash ficticios fuera del plan. (5) Autorizar distribución solo tras PASS.
3. **D03 — Backup/restore.** (1) Identificar plan/retención Hosted real y custodios. (2) Backup schema+data fuera del repo y cifrado; guardar hash. (3) Ensayar restore en entorno aislado, verificar conteos/funciones/migraciones y destruir solo ese entorno con autorización separada. (4) Definir qué hacer con Drift/outbox aún no sincronizado. (5) Programar frecuencia y responsables.
4. **D04 — Test gate.** (1) Actualizar fake de `purchase_product_dependency_test.dart` con métodos nuevos que fallen cerrados/retornen contrato real. (2) Sustituir expectativas 13/14 por 17 donde se testea creación actual; para migraciones usar fixtures realmente históricos, no sqlite_master contemporáneo renombrado. (3) Añadir `cash_movements` al fixture OR-01/08, manteniendo caso sin sesión abierta. (4) Ejecutar tests focales, `flutter analyze`, suite completa; clasificar regresiones restantes. (5) No modificar producción para “pasar” fixtures viejos.
5. **D05 — Paridad Hosted.** (1) Resolver tooling npm/CLI sin revelar credenciales. (2) Listar history linked read-only y comparar versiones SHA/nombres con 142 archivos locales; no `db push`. (3) Verificar presencia de S1/S1A, cash flow, reportes, costo y auth usados por APK. (4) Hacer consultas/RPCs read-only autorizadas y registrar fecha/ambiente. (5) Ante desfase, planificar despliegue como fase separada con backup.
6. **D06 — Compra/salida.** (1) Acordar que compra ≠ pago y la salida es explícita. (2) Mostrar atajo tras guardar compra para abrir `CashMovementDialog` con `supplier_purchase`, amount y referencia, sin registrar salida automáticamente. (3) Usar `CashMovementService` existente y su outbox. (4) Probar cancelación del diálogo, doble tap, compra pendiente, cash scope y no doble salida.
7. **D07 — Margen histórico.** (1) Medir cohorte de sale_items pre/post migración en Hosted read-only; no inferir procedencia por costo actual. (2) Definir cutoff o etiqueta “histórico aproximado”. (3) Si se decide, adaptar presentación/capability/cache sin alterar costo numérico por sustitución. (4) Probar períodos mixtos y `unknown_cost_item_count`.
8. **D08 — Tablet.** (1) Elegir modelo/resoluciones del piloto. (2) Ejecutar widget tests anchos 360/600/900dp, landscape y text scale; revisar overflow. (3) Smoke físico solo con autorización de usuario. (4) Corregir pantallas focales preservando flujo, no rediseño global.
9. **D09 — Invitación multinegocio.** (1) Test de A activo + invitación B. (2) Aceptar B; comprobar selección explícita B y resultado del stabilization service. (3) Reiniciar online/offline y verificar scope profile/business/branch/device. (4) Si falla, corregir gate/selection, nunca usar primer negocio arbitrario.
10. **D10 — Observabilidad.** (1) Definir vista/checklist de `pending/partial/error`, issues blocking, device, caja y backup. (2) Redactar guía de captura sin JWT/PII y umbrales de soporte. (3) Ensayar un pending y un rechazo. (4) Evitar telemetry nueva hasta justificarla.
11. **D11 — Catálogo.** (1) Congelar surtido piloto y registrar provenance/license. (2) Verificar unicidad/barcodes con tooling existente. (3) Curar provisionales y 404 sin writes masivos. (4) Ensayar corrección/idempotencia en local antes de lote Hosted autorizado.
12. **D12 — Partial/retry.** (1) Seleccionar casos de cada uploader, especialmente purchase-after-product y caja/venta. (2) Interrumpir entre commit remoto y ACK local en test; verificar IDs/keys. (3) Reabrir contexto y sincronizar: ningún doble movimiento, ningún loop infinito. (4) Documentar salida de soporte si permanece blocker.

## Safe-to-Defer Debt

- D06–D12 pueden permanecer durante un piloto **de una tienda y un dispositivo supervisado**, con excepciones: no introducir tablet/multinegocio antes de D08/D09; no presentar margen histórico como exactitud financiera antes de D07.
- D13 reportes avanzados, D14 devoluciones/void, D15 lifecycle administrativo, D16 docs históricas, D17 upgrades, D18 contabilidad completa y D19 Store/analytics no bloquean ventas/caja/stock básicos. Una devolución real, un empleado revocado o una pérdida de device durante piloto requiere procedimiento administrativo y puede activar STOP PILOT para ese caso, no un workaround con edición manual.
- La ausencia de sesión de caja abierta es estado comercial válido para entrar al Dashboard; POS exige apertura en su guard propio. `offline_operational_readiness_service.dart` exige caja canónica activa, **no** sesión abierta. Los fallos OR-01/08 de hoy provienen del fixture sin el dataset `cash_movements`, no prueban violación de esta regla.

## Pilot Blockers — MUST FIX BEFORE FIRST REAL PILOT

| Gate | Por qué bloquea | Reproducción / evidencia | Cierre y validación |
|---|---|---|---|
| D01 | Un operador podría no entrar sin Wi-Fi | Reabrir el dispositivo afectado offline con autorización/checkpoints ya completos; capturar reason tipado | Diagnóstico causal; si local completo, Dashboard abre; si faltante legítimo, mensaje específico y recuperación online segura |
| D02 | APK construida ≠ APK operativamente aceptada | Instalación manual build 2 y checklist de primer uso | Checklist completo PASS en dispositivo piloto; firma/hash/versionCode anotados |
| D03 | Sin retorno probado ante pérdida/datos corruptos | Ensayo de export/restore aislado | Backup privado con hash + restore ensayado + responsable y frecuencia |
| D04 | Analyze y suite actual fallan por tests obsoletos | Comandos de Verified Baseline | Analyzer sin errors/warnings nuevos y suite relevante completa, sin “fix” de producción innecesario |
| D05 | No se demostró que Hosted tenga todas las RPCs locales | `migration list --linked` no terminó por `ECONNRESET` | History linked + contratos read-only cotejados y registrados |

## Sync & Offline Audit

- Escritura operacional local→Drift, outbox `local_sync_batches`/`local_sync_mutations`, dependencias `local_sync_batch_dependencies`, upload por catálogo/caja/POS/compras/inventario, luego pulls/reconciliación. `productive_manual_sync_service.dart:282–326` limita iteraciones a ocho y reevalúa dependencias; `productive_scheduled_sync_service.dart` prueba slot aislado por profile/business/branch y evita loop de slot. `CashCloseSyncTriggerService` mantiene cierre como trigger diferenciado. No se encontró un segundo outbox.
- `local_sync_outbox_dao.dart` contiene índices/selección y guardas de dependencias; el resumen de estado es derivado de consultas, no simple contador incremental. Hay pruebas focales para scheduled (10 PASS), pero no se ejecutó la suite global de idempotencia este día. No declarar ausencia de starvation en un dispositivo sin D12.
- Recovery usa bootstrap core→products→balances→cash, checkpoints por scope `profile/business/branch/device`, y issues blocking por scope. La autorización local se deriva de proyección efectiva, no de nombre de role. `OfflineOperationalReadinessService` exige usuario/profile coherente, autorización activa, runtime de instalación, checkpoints completos/convergidos, ausencia de issues blocking y caja canónica si capability cash. Pending mutations legítimas no son condición de bloqueo. Revoked no se abre con snapshot cacheado.
- El gate online puede devolver `bootstrapRecoveryBlocked`; ante fallo transitorio evalúa readiness cacheada. Si ésta no está completa, muestra “Conéctate a Internet y reintenta”. **No se conoce** la razón precisa del blocker observado en Moto: pudo ser un checkpoint de cash movements ausente, issue real, runtime/caja o auth; no se debe reducir la condición sin evidencia. Historial de caja y stale sale tiene flujos focales de reparación, pero su operación multi-device requiere D12.

## Cash / Sales / Purchase Audit

- Caja local incluye registers/sessions/movements, una sesión abierta por register (`app_database.dart:1546`), ledger append-only para cash movements (`:1276–1318`), salida bloqueada si expected cash quedaría negativa (`cash_movement_service.dart:108`), categorías que distinguen inventario, gasto, owner y otros (`cash_movement_models.dart`). Cierre contempla pagos cash, movimientos y guard de pendientes; no confundir saldo físico con beneficio.
- POS en `features/sales` (no scaffold `features/pos`) crea sale/items/payments y movement negativo en una ruta local; `PosLocalSaleService` valida cash session. Backend de sale sync y stale reconciliation rechaza sesión cerrada y conserva reparación auditada de venta no materializada. La app tiene pagos múltiples/cash; no se verificó en esta sesión cada método de pago en Hosted. `voided_at`/`void_reason` y permisos existen en SQL, pero no hay UX de devolución ordinaria en el POS productivo.
- Compras escriben items, movement positivo y balance local; dependencia catálogo→compra y retry autoritativo existen. Guard C4A1 conserva centavos exactos. El formulario de compra **no** pregunta si se pagó con Caja ni crea automáticamente un outflow; la categoría `supplier_purchase` existe en Caja. Esto es deliberadamente distinto de cuentas por pagar. Hasta D06: registrar la compra y, si se pagó efectivamente en efectivo, registrar salida separada desde Caja con referencia; no registrar dos veces.
- `purchase_payments`, saldos de proveedor y pagos parciales se pospusieron: aceptable para piloto operacional, insuficiente para contabilidad real/CxP. No inferir deuda pagada ni cash outflow desde el total de la compra. La salida `supplier_purchase` afecta efectivo, no COGS otra vez.

## Inventory Audit

- Saldo operativo es `local_product_stock_balances` por business+branch+product, no `products.stock_quantity`; ledger `local_inventory_movements`. Hay índices únicos de scope y de movimientos/historial (`app_database.dart:1618–1641,1707–1722`). Ajustes manuales y pérdidas validan stock insuficiente (`inventory_adjustment_service.dart:101`); transferencia también expone insuficiencia. Compras suman, ventas restan; balances se reconcilian como base remota + movimientos locales no ACK.
- Minimum stock es configuración global del producto; agotados/bajo stock son proyecciones por saldo branch. Historial paginado (`inventory_history_local_dao.dart:193,232`) normaliza orden temporal de ISO/epoch. No se ejecutó reconciliación multi-device real en esta sesión. D12 cubre ACK ambiguo y balance remoto ausente con movimiento local legítimo; no borrar ledger ni forzar stock a cero.
- Falta P2.6C reporte agregado de inventario; la lista operacional de stock no lo sustituye. Inventario y compras para piloto tienen capacidad principal, pero requieren smoke D02.

## Reporting Audit

| Vista | Estado actual | Autoridad/cache/permiso | Pendiente |
|---|---|---|---|
| Sales Summary | Implementada | RPC `get_branch_sales_report_summary`, branch/período; snapshot local profile-scoped; `reports.sales` | Aceptación con datos piloto |
| Profitability | Implementada con advertencia histórica | RPC `get_branch_profitability_report_summary`; `reports.sales` + `sales.view_costs`; COGS de `unit_cost_snapshot`; NULL segregados | D07: procedencia de no-NULL antiguos; no prometer exactitud histórica |
| Cash Flow & Expenses | Implementada | RPC `get_branch_cash_flow_report_summary`, venta cash completada + cash movements ordinarios; cache offline y warning local de pendientes; `reports.cash` | Aceptación manual; no confundir opening/closing con flujo |
| P2.6C Inventory Report | No implementada como reporte productivo | Propuesta: balances/movements server-authoritative por branch, `reports.inventory`, snapshot offline invalidado por auth | RPC agregado de stock/valoración/alertas, UI, tests scope/convergencia |
| P2.6D Purchases Report | No implementada | Propuesta: purchases/items finalizados por branch/período, capability `reports.inventory` o nueva decisión; cache separada | Definir total exacto, devoluciones futuras, RPC/UI/tests |
| P2.6F Exports | No implementada | `reports.export` existe como permiso; debe heredar la ACL de cada reporte además de export | Formato/redacción/límites, export de snapshot con provenance y tests |

P2.6E “Cash” corresponde en la práctica a cash-flow ya implementado; cualquier reporte de conciliación de caja más profundo es otra decisión. Para C/D/F no crear consulta cliente ad hoc de tablas protegidas ni sumar local sobre un total Hosted autoritativo; definir RPC+capability+cache+revocation coherentes con A/B/Cash.

## Security Audit

- Backend incorpora RLS/migrations para memberships/branch, RPCs `security definer` con chequeos internos y grants focales. Ejemplos concretos: `get_branch_profitability_report_summary` requiere `reports.sales` y `sales.view_costs` (`20260924120000...:58–59`); cash-flow exige `reports.cash` (`20260927131000...:56`) y revoca/granta EXECUTE explícito (`:137–140`). No se ejecutó auditoría exhaustiva de las 142 migraciones ni pgTAP hoy; no se afirma ausencia total de bypass.
- Flutter limita rutas debug con `kDebugMode`; `main.dart` imprime excepción/stack solo en debug y muestra error sanitizado en release. Ambos callbacks dev/prod permanecen en Manifest, lo cual es intencional y no da por sí mismo acceso. La app no debe mostrar tokens ni SQL al operador.
- `config/prod.json` contiene anon/publishable key (pública por diseño), no `service_role`/password entre sus claves. Signing properties y keystore son locales ignorados; el keystore configurado está fuera del repo. Se inspeccionaron claves/nombres/rutas, no contenidos secretos. No se realizó scanner de secretos sobre toda la historia Git: eso sería una auditoría distinta.
- Seguridad del piloto depende de revisión de permisos efectivos de Owner/Cashier/Warehouse, revocación y cross-branch durante D02/D09. No delegar role custom por nombre. Si aparece acceso cruzado, **STOP PILOT**.

## Local DB / Drift Audit

- Schema 17 registra negocio/autorización, POS, compras, caja, catálogo maestro/barcodes, outbox+dependencias, movements/balances, checkpoints/seen/issues, history hydration y report snapshots (`app_database.dart:1–1269`). `products.stock_quantity` y algunos campos heredados permanecen por compatibilidad; son **legacy no autoritativos**, no una segunda fuente de saldo. No se identificó obligación segura de eliminarlos antes de piloto.
- Versiones 13/14 añaden report snapshots/cash movements, 15 compra exacta, 16 scope de issues, 17 dependencias de batches. `beforeOpen` reinstala índices idempotentes y FK; tests genuinos de upgrade 8/9/10/12/16→17 pasaron. Un test que clona schema actual y cambia `user_version` a 13 **no representa** un archivo SQLite histórico y falla con columna duplicada: D04.
- SQLite privado del dispositivo no se leyó; no se infiere salud del Drift instalado. Para upgrade debug→release con distinta firma no existe instalación in-place: desinstalar perdería SQLite, prefs, sesión e IDs. Se requiere instalación piloto limpia en dispositivo designado o un plan explícito de preservación de pendientes, nunca `pm clear` por conveniencia.

## Backend / Supabase Audit

- 142 migraciones locales, con cierres recientes de sync registration/idempotencia, monetaria de compras, pago con event time y cash-flow. Tests pgTAP específicos existen para caja, ventas, compras, inventario, auth y reportes. No se ejecutó reset/pgTAP/lint en esta auditoría porque sería costoso y no necesario para leer el estado; no se infiere que todos pasen hoy.
- Hosted había sido ejercitado en fases anteriores según contexto de proyecto, pero la lista *actual* de migraciones no se pudo consultar por fallo de tooling (`ECONNRESET` al descargar CLI). Tratar D05 como **UNKNOWN hasta verificación**. No hacer deploy para “probar” paridad.
- SQL inicial amplio (`GRANT ALL` en schema original) fue endurecido por migraciones posteriores; evaluar ACL efectiva requiere estado final, no leer grants iniciales aislados. El stack local PostgreSQL 17.6 tenía incidente documentado de SIGSEGV al invocar función sin EXECUTE: no relajar ACL por limitación local (`docs/TESTING.md`).

## UX / Tablet Readiness

- P2.7A limpió muchas pantallas; el Dashboard usa grid adaptable y el POS dos layouts según ancho. Hay `Wrap`/constraints en Caja/Inventario. Esto es evidencia de intención responsive, **no** aceptación en tablet/landscape. Pantallas densas (POS, edición de cantidad, cash movement, reportes) merecen smoke con teclado y fuente grande (D08).
- Buscar “TODO” sin distinguir palabras da falsos positivos por “Todo al día”; búsqueda precisa case-sensitive en `lib`/migrations no encontró marcadores `TODO/FIXME/HACK/UnimplementedError`. Existe un comentario plantilla `TODO: Specify your own unique Application ID` en Gradle, pero el valor real ya es `com.cronosmanagement.app`; es deuda cosmética, no bloqueo.
- La UI de recovery usa textos productivos y retry; cualquier UUID/error crudo en un caso real debe capturarse y corregirse focalmente, no se halló exposición concreta de secretos en startup. Mantener asistencia humana para casos financieros/caja no resolubles.

## Release / Distribution

- Build universal manual `1.0.0+2`, package `com.cronosmanagement.app`, app label `Cronos POS`, INTERNET en main, signing release sin fallback debug (`android/app/build.gradle.kts:45–83`), prod config explícita, icono/splash integrados según commit P2.7B y smoke visual previo comunicado. Sin prueba de instalación física de esta APK en esta auditoría.
- Requisito de actualización in-place: **mismo applicationId + mismo certificado signing + versionCode ascendente**. El Moto G13 con APK debug firmada distinto **no puede actualizarse encima con release**. Si conserva operaciones no sincronizadas, no desinstalar ni limpiar. Para primer piloto, preferir instalación limpia en dispositivo nuevo o uno cuyo estado ya fue evacuado/verificado, y usar desde entonces siempre la misma firma release custodiada. Export/import Drift no es requisito si se empieza limpio; sí sería proyecto separado si se exige migrar datos debug.
- Para compartir: distribuir solo APK cuyo hash coincida, por canal privado, con instrucciones de instalación/versión; conservar certificado/keystore fuera de Git con respaldo privado. Play Store, AAB y rollout público son posteriores. No actualizar `versionCode` solo por copiar un APK existente.

## Catalog Debt

- Existe maestro/barcodes, importer chunked/idempotente y origen de imágenes. `tools/catalog_import/README.md` pide licencia cuando hay `image_source_key`; los reports y snapshot de tooling untracked no se incorporan por accidente al APK ni a Git. Esta auditoría **no revalidó** 1.149 filas ni ejecutó import/dataset pesado.
- Para piloto, catálogo puede ser un surtido curado con barcodes verificados y fallback provisional OFF; no confundir un dato externo con identidad comercial aprobada. Calidad y derechos de imagen son D11. Un 404 de imagen puede usar placeholder, no debe afectar venta. No ejecutar cargas masivas en día de apertura.

## Test / Analyze Debt

- D04 es la deuda inmediata. El error de fake es de compilación del test, no prueba de error en `PurchasesSyncUploadService`. Los asserts 13/14 son expectativas viejas. OR-01/OR-08 son fixtures incompletos tras `cash_pos/cash_movements`; los otros seis casos OR pasaron. Los seis tests de migración actual y diez de sync programado pasaron.
- `flutter analyze --no-pub`: 0 warnings, 27 infos (deprecaciones/estilo), 1 error del fake. No “arreglar” 27 infos dentro de la aceptación del piloto. Suite global no ejecutada porque ya hay test que no compila; no dar cifra global de PASS. No se detectaron tests `skip` explícitos; test flakiness requiere repetición/CI, no inferencia por grep.
- Test de release físico, upgrade real y restore siguen manuales/no ejecutados. Registrar ambiente, comandos, PASS/FAIL y evidencia en el gate correspondiente.

## Operational / Backup Debt

- Antes del piloto: confirmar plan real de Supabase, disponibilidad de backup/retención y privacidad de datos; no asumir PITR ni acceso a backups por el solo hecho de usar Hosted. Según [documentación oficial de backups](https://supabase.com/docs/guides/platform/backups), los mecanismos y acceso dependen del plan; la [pausa por inactividad en plan Free](https://supabase.com/docs/guides/platform/free-project-pausing) es un riesgo a revisar si ese es el plan efectivo. **No se verificó el plan de este proyecto hoy**.
- Procedimiento mínimo: export de schema+data aprobado a ubicación privada externa, cifrado/ACL, hash, copia separada, restore de ensayo en entorno aislado, y bitácora diaria de sync pendientes/issues/cierre. SQLite del dispositivo puede contener operaciones todavía no Hosted; antes de reemplazar un equipo debe verificarse outbox, nunca asumir que backup Hosted lo incluye. No escribir dumps en repo ni logs compartidos.
- Observabilidad mínima: una revisión al abrir/cerrar de estado `pending/partial/error`, issues blocking scoped, caja abierta/cerrada, último sync, dispositivos y uso/capacidad de Hosted; capturar código/ID de correlación no secreto y hora, nunca JWT/contraseña. `activity_logs`/`sync_logs` y reconciliación son evidencia potencial, no sustituto de runbook.

## Remaining Roadmap

| Fase propuesta | Objetivo / scope y dependencia | Tests / aceptación | No hacer |
|---|---|---|---|
| P2.8B Release acceptance gate | Cerrar D01–D05, empezando por diagnóstico offline y test health; comparar Hosted y preparar backup antes del smoke APK | Analyzer/suite verdes, paridad, restore ensayado, checklist release PASS | No deploy o wipe implícito; no ventas de prueba no autorizadas |
| P2.9 Primer piloto real | Una tienda/dispositivo, surtido validado, operación diaria asistida | Checklist inferior: transacciones locales/remotas, caja conciliada, outbox e issues sin bloqueo | No multi-device/tablet sin aceptar escenarios específicos |
| P3.0 Stabilization | D06–D12 según incidentes y valor observado | Tests focales + smoke por deuda + métricas de operación | No ampliar finanzas antes de estabilizar |
| P3.1 Reporting/administration | D13–D17 con RPCs, cache y ACL coherentes | pgTAP, Flutter tests, datasets de prueba, actualización segura | No exportar datos sensibles sin autorización |
| P4 Product expansion | D18–D19, contabilidad/proveedores/Store | Decisiones de producto, migración y certificación propias | No mezclar con piloto |

## Implementation Plan

Los 12 mini-planes P0/P1/P2 anteriores son el backlog ejecutable. Cada tarea nueva debe empezar con `git status`, contrastar tests/código del HEAD de ese momento, limitarse a uno o dos pasos, y terminar con diff y validación proporcional. No juntar D01 con refactor de sync, ni D04 con schema nuevo, ni D06 con CxP formal. Para P3: diseñar cada reporte como contrato servidor + test RLS + cache revocable + UI; para P4: pedir decisión arquitectónica antes de iniciar.

## Dependency Order

```text
D04 test health ──┐
                  ├── D01 offline diagnosis/fix ──┐
D05 Hosted parity ├─────────────────────────────────┼── D02 release acceptance ── P2.9 pilot
D03 backup/restore ──────────────────────────────────┘

P2.9 pilot ──> D10 observability + D12 retry matrix
           ├─> D06 purchase cash UX, D07 margin provenance
           └─> D08 tablet / D09 multi-business / D11 catalog (before enabling each scope)

P2.9 evidence ──> D13–D17 post-pilot ──> D18–D19 expansion
```

D03 y D05 pueden avanzar en paralelo read-only; D04 puede avanzar sin Hosted; D02 espera los cuatro. Ninguna dependencia autoriza cambios remotos por sí sola.

## First Pilot Checklist

**Estados:** PASS = evidencia y resultado esperado; WARN = desviación documentada sin riesgo de dinero/stock/auth y con operador supervisado; FAIL = criterio no cumplido, no ampliar uso; STOP PILOT = riesgo de pérdida, doble cobro/stock, acceso cruzado, caja inconciliable o corrupt Drift. Cada ítem registra fecha, operador, device, build/hash, business/branch y resultado sin credenciales.

### Antes

1. Backup Hosted privado + hash + restore de ensayo PASS; plan/retención confirmado. Nunca incluir `data.sql` en Git.
2. APK build 2/hash/certificado y keystore respaldado; paquete `com.cronosmanagement.app`, versionCode 2. Device piloto limpio o release-compatible; pendientes de instalación debug anterior resueltos sin wipe improvisado.
3. Usuario Auth y permissions efectivas correctas; negocio y sucursal explícitos; app_device único por instalación; caja canónica/runtime, receipt sequence y productos/barcodes del surtido definidos.
4. Stock inicial físico y saldo por branch registrado; caja inicial/efectivo contado; internet y plan de corte; outbox/issues iniciales conocidos; autorización de qué transacciones reales se harán.

### Durante

1. Login/restart online; selector/contexto; Dashboard. Entrada offline tras bootstrap completo y caja cerrada legítima. Si offline no entra por D01: FAIL/STOP según necesidad operacional.
2. Abrir Caja; venta cash real controlada: comprobante, pago, descuento de stock local exactamente una vez; sync y comparación Hosted. Si otro pago es parte del piloto, verificar ese método sin inventar cash.
3. Compra real controlada: aumento local/Hosted y costo; si se pagó cash, salida de Caja separada con categoría proveedor y referencia. Ajuste/inventario solo con motivo autorizado.
4. Corte de red controlado: operación local, UI visible y pending; reconectar, “Sincronizar ahora”, idempotencia y conteos finales. No forzar sync si aparece issue no entendido.
5. Reports: ventas, margen con advertencia histórica, cash flow; cache offline conserva snapshot y advierte pendientes. Cambiar sucursal solo si está incluido en alcance del piloto y verificar no mezclar scope.

### Cierre diario

1. Confirmar outbox sin pendientes inesperados o registrar cada excepción. Cerrar Caja mediante UI, comparar expected/actual/difference; no manipular cash session Hosted manualmente.
2. Revisar issues blocking, stock de artículos de muestra y RPC/read-only, reportes y logs; backup programado y hash; firma del operador/resultado PASS/WARN/FAIL. No dejar blocker abierto sin owner y siguiente acción.

### STOP PILOT inmediato

Stock local/Hosted diverge sin explicación de movimiento pendiente; venta/pago doble; Caja cerrada con dinero no conciliado; datos de otro business/branch; auth revocada que aún opera; Drift ilegible; pérdida de dispositivo con outbox no respaldado; sync que reintenta mutación terminal sin control. Preservar datos/evidencia y no limpiar almacenamiento.

## Rollback Plan

| Incidente | Acción inicial segura | Prohibido / escalado |
|---|---|---|
| Sync atascado/partial | Dejar de generar operaciones nuevas si compromete stock/caja; capturar batch/mutation/issue IDs, status, timestamps y scopes; consultar estado Hosted read-only; reintentar solo por flujo idempotente confirmado | No borrar outbox ni “recrear” venta/movement; si ACK ambiguo, escalar a reconciliación focal |
| Cash close bloqueado | Mantener sesión/efectivo intactos; revisar pendientes de POS/cash y razón tipada; seguir ruta productiva de repair si está soportada | No forzar status closed en SQL/Drift ni abrir caja alternativa |
| Drift corrupto/inaccesible | Detener uso del dispositivo; preservar archivo/copia forense con autorización y resguardar app storage; comparar última convergencia Hosted | No uninstall, `pm clear`, reset ni restore sobre el único origen de movimientos pendientes |
| Hosted indisponible | Operar offline solo si readiness válida y política lo permite; registrar transacciones/efectivo; limitar volumen y reconciliar al volver | No asumir que caché equivale a autorización online nueva; si bootstrap incompleto, detener operación |
| Release mala | Retirar distribución; conservar APK/hash anterior y signing key. Para volver a versión anterior, Android suele exigir versionCode creciente: preparar build corregida y probar actualización conservando datos | No distribuir APK debug ni cambiar package/firma; no hacer downgrade destructivo |
| Catálogo erróneo | Pausar uso del SKU, documentar barcode/ID/ventas; curar con flujo canónico y soft delete donde proceda | No borrar master/producto con movimientos ni cargar lote masivo correctivo |
| Permisos rotos/tenant cruzado | STOP PILOT, revocar acceso por ruta administrativa autorizada, preservar logs y limitar dispositivos | No conceder grants amplios ni editar RLS apresuradamente en Hosted |

## Avoid Before Pilot

No construir contabilidad general, `purchase_payments` complejos/CxP, devolución parcial avanzada, tienda de apps, analytics/telemetry nueva, rediseño global, migración masiva de catálogo o reemplazo del outbox/Drift. Tampoco usar `products.stock_quantity` como saldo ni convertir cada escaneo en RPC. El primer objetivo es demostrar operación segura y recuperable con una tienda y un dispositivo.

## Recommended Next 10 Tasks

1. **Task:** D04 cerrar fixtures/fake de suite. **Why now:** sin analyzer/tests verdes no hay gate confiable. **Scope:** cuatro tests, sin producción. **Expected files:** `local_cash_movements_test.dart`, `report_snapshot_local_dao_test.dart`, `purchase_product_dependency_test.dart`, `offline_operational_readiness_service_test.dart`. **Validation:** tests focales, `flutter analyze`, suite completa. **Done when:** 0 errores/warnings nuevos y OR-01/08 pasan con dataset real.
2. **Task:** D01 diagnóstico read-only de blocker offline Moto. **Why now:** posible bloqueo operativo P0. **Scope:** reason/checkpoint/issue/runtime scoped, sin limpiar datos. **Expected files:** inicialmente ninguno; test/fix focal solo tras causa demostrada. **Validation:** reproducción equivalente y contraste con readiness. **Done when:** causa precisa y regla segura documentadas.
3. **Task:** D01 fix focal si el diagnóstico confirma falso positivo. **Why now:** entrada offline es contrato de piloto. **Scope:** gate/readiness mínimos, sin relajar auth/blocks; si no hay bug, cerrar con explicación del estado incompleto. **Expected files:** servicio/gate y tests focales solo si procede. **Validation:** offline completo entra; incompleto/revoked no entra. **Done when:** dispositivo y test demuestran regla.
4. **Task:** D05 paridad Hosted read-only. **Why now:** APK requiere RPCs actuales. **Scope:** migration history/ACL/RPC presence, sin writes. **Expected files:** ninguno, acta privada no sensible. **Validation:** lista linked y smoke read-only. **Done when:** versión Hosted cotejada exactamente o desfase escalado como deployment separado.
5. **Task:** D03 backup/restore piloto. **Why now:** no operar con datos reales sin retorno ensayado. **Scope:** dump privado fuera del repo, hash, restauración aislada con autorización específica. **Expected files:** runbook operativo futuro, no migraciones. **Validation:** conteos, migraciones y hashes/restauración en entorno aislado. **Done when:** responsable puede ejecutar recuperación documentada.
6. **Task:** D02 inspección técnica final del APK distribuible. **Why now:** fijar identidad de lo que se va a instalar. **Scope:** hash, signature, package, version, config pública y cadena de custodia. **Expected files:** ninguno. **Validation:** `apksigner`/`aapt` y SHA-256. **Done when:** artefacto exacto aprobado, sin secreto en Git.
7. **Task:** D02 aceptación Android manual inicial. **Why now:** build no equivale a operación. **Scope:** usuario instala en dispositivo piloto limpio/release-compatible y recorre checklist Antes+Durante. **Expected files:** acta de prueba; código solo si bug focal. **Validation:** resultados PASS/FAIL y comparación de scopes/stock/caja. **Done when:** ningún blocker y primer día simulado completo.
8. **Task:** P2.9 primer día real controlado. **Why now:** medir operación/latencia/errores reales con bajo riesgo. **Scope:** una tienda/dispositivo, surtido acotado, transacciones autorizadas. **Expected files:** bitácora privada, quizá documentación. **Validation:** checklist diario + cierre de Caja + outbox/issues + backup. **Done when:** balances/efectivo/reportes concuerdan y no hay STOP.
9. **Task:** D10+D12 observabilidad y matriz de retry basada en incidentes. **Why now:** estabilizar antes de ampliar usuarios. **Scope:** runbook y tests focales de interrupción/idempotencia, sin segundo outbox. **Expected files:** sync/recovery tests, procedimiento. **Validation:** pending/partial/ACK ambiguo detectados y reintento sin doble efecto. **Done when:** operador sabe cuándo reintentar/escalar.
10. **Task:** D06/D07 priorización post-primer día. **Why now:** atajo de gasto proveedor y calidad de margen deben responder a uso real, no a especulación. **Scope:** decisión de UX cash y cutoff de costo histórico read-only; prompts focales separados. **Expected files:** purchase/cash UI tests; reporte/UI solo si política aprobada. **Validation:** sin cash duplicado y margen etiquetado honestamente. **Done when:** decisiones y alcance de siguientes dos tareas están cerrados.
