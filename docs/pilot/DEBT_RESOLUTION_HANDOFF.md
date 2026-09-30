# Cronos POS — handoff ejecutable de deuda y piloto

Fecha: 2026-09-28. Raíz del repositorio: `C:/Users/Cronos/Developer/personal/inventario-app`. Los paths de código siguientes son relativos a esa raíz. Este documento contrasta íntegramente `docs/pilot/PROJECT_DEBT_AND_ROADMAP_AUDIT.md` con el HEAD indicado abajo; **no** certifica el estado Hosted ni el del Moto. Etiquetas: **VERIFIED** = comprobado en código/archivo/comando local; **INFERRED** = diseño o causa plausible que exige prueba; **UNKNOWN** = falta acceso/evidencia. No usar una inferencia como autorización de escritura.

## 0. Baseline y gates

- **VERIFIED** rama `feature/foundation-core`; HEAD `3e9072be7b90ae4ad84f5828f5ce326c2d201da5` (`test: update pilot fixtures for current contracts`). Recientes: `7711605` audit, `4be7697` APK build 2, `4c079e4` Dashboard, `e23fc24` identidad, `b088543` sync status caja, `fb8c287` cash flow, `efe1714` dependencias de batches, `17c944a` sync/moneda compra. En esta tarea `git status --short` no mostró cambios tracked antes de crear este documento. Untracked históricos: `inventario-Backend/tools/catalog_import/reports/{category_mapping,master_seed,open_food_facts,open_prices,promotion_readiness,resolution}/`, ocho CSV `rejected_*`, `tools/catalog_import/tmp/` y `inventario-Frontend/releases/`. No tocarlos.
- **VERIFIED** Flutter 3.44.1 stable / Dart 3.12.1; `inventario-Frontend/pubspec.yaml` versión `1.0.0+2`; `AppDatabase.schemaVersion == 17` en `inventario-Frontend/lib/core/database/app_database.dart`. APK `inventario-Frontend/releases/Cronos-POS-Pilot-1.0.0-build2.apk`: 70.876.613 bytes, SHA-256 `BF42C2BD8BFA3DED74FFE4F7A874A4C4DC55C98CC5556BD4CC25706D263076F8`. Archivo presente; firma/metadata no fueron reverificados aquí. Paquete esperado por Gradle: `com.cronosmanagement.app`.
- **VERIFIED** D04 focal está en HEAD. Resultado de la ejecución precedente documentada por la tarea: cuatro archivos focales 40/40 PASS, migraciones 7/7 PASS, analyzer 0 errores/0 warnings/27 infos, suite completa 978 PASS/3 FAIL. Esos números son evidencia de esa corrida, no una reejecución en este handoff. **UNKNOWN** estado de pruebas tras futuros cambios. D01 (offline Moto), D05 (Hosted parity), D03 (restore) y D02 (aceptación APK) siguen sin cerrar. El informe original fue escrito en `4be7697`; sus resultados de tests/analyze anteriores a D04 ya no son el baseline actual.

## 1. D04 — tres tests restantes y cambios que no deben revertirse

| Test | Aserción vieja → valor productivo | Cambio mínimo posterior / PASS |
|---|---|---|
| **RG-01**, `inventario-Frontend/test/features/auth/productive_auth_routing_test.dart:71,88` | Espera `Crea tu acceso a CronosManagement. Los negocios y permisos se asignan después.`; `inventario-Frontend/lib/features/auth/presentation/screens/productive_registration_screen.dart:107` muestra `Crea tu acceso a Cronos POS. Podrás crear un negocio o aceptar una invitación.` | Sustituir solo el literal esperado; conservar tap/routing. `cd inventario-Frontend && flutter test --no-pub test/features/auth/productive_auth_routing_test.dart`. |
| **RG-04**, `inventario-Frontend/test/features/auth/productive_registration_test.dart:80,96` | Espera `... vuelve a CronosManagement para iniciar sesión.`; pantalla `:214` dice `... vuelve a Cronos POS para iniciar sesión.` | Actualizar solo el literal, conservar semántica signup sin Session. `flutter test --no-pub test/features/auth/productive_registration_test.dart`. |
| `switching invalidates only context-dependent shell state`, `inventario-Frontend/test/features/sync/operational_branch_switching_test.dart:214,231` | Lee el *source* de `main_dashboard_screen.dart` y exige `title: 'Recuperación requerida'`; ese literal ya no está allí. La recuperación bloqueada se aloja en `business_context_required_gate.dart` (`bootstrapRecoveryBlocked`, `:496`). | Eliminar/reemplazar **solo** la aserción literal obsoleta por verificación del gate/productive error actual; conservar assertions de invalidación, ausencia de RPC/delete y prueba conductual de branch switch. `flutter test --no-pub test/features/sync/operational_branch_switching_test.dart`. |

**VERIFIED** el commit `3e9072b` cambió cinco tests, ningún archivo productivo: `test/features/sync/purchase_product_dependency_test.dart` agregó al fake `inspectPermissionRetry`/`finalizePermissionRetry` con firmas actuales y `UnsupportedError` si se invocan fuera de alcance; `test/core/database/local_cash_movements_test.dart` espera schema 17 y retiró una falsa migración v13 hecha copiando `sqlite_master` actual; `test/features/reports/report_snapshot_local_dao_test.dart` espera schema 17; `test/features/sync/offline_operational_readiness_service_test.dart` agregó checkpoint `cash_pos/cash_movements` en fixture OR-01/OR-08; `test/core/database/app_database_migration_test.dart` agregó fixture mínimo genuino v13→17 preservando report snapshot. No revertir: hacerlo resucita fallos de compilación, versiones falsas o falsa exigencia de sesión abierta. Para cerrar D04: corregir únicamente los tres asserts, ejecutar tres focales, `flutter analyze --no-pub --no-fatal-infos`, `flutter test --no-pub`, `git diff --check`; PASS global sin cambiar producción. Si surge otro fallo, clasificar antes de editar.

## 2. D01 — mapa exacto del bloqueo offline P0

### 2.1 Flujo y punto decisorio

**VERIFIED** `inventario-Frontend/lib/main.dart` inicializa Supabase; `lib/app/router/app_router.dart` aplica auth/rutas y construye `BusinessContextRequiredGate` (`lib/features/sync/presentation/widgets/business_context_required_gate.dart`). El gate observa `productiveOperationalEntryProvider` (`lib/features/sync/application/operational_bootstrap_entry_providers.dart:198`) y acceso autenticado. `OperationalBootstrapEntryService.run` (`.../operational_bootstrap_entry_service.dart:72`) hace profile Auth → `AuthorizedOperationalContextService.listAuthorizedContexts`/RPC `list_authorized_operational_contexts` → selección explícita o único contexto → `AppInstallationIdStore` → `register_or_update_app_device` → `RuntimeResolutionService.resolve`/`resolve_business_runtime` → guarda `AppRuntimeContextStore` en SharedPreferences → `OperationalBootstrapService.run`. Éste hace `core/context` → proyección efectiva → product categories/products/barcodes → balance → cash_pos → issues/checkpoints finales. La entrada `runtimeReadyAndBootstrapCompleted && offlineReady` entrega `widget.child` (Dashboard) en gate `:469`. No es prueba de que ese recorrido completó en el Moto.

**VERIFIED** cuando Entry devuelve `transientFailure`, gate `:547` consulta `productiveCachedOperationalReadinessProvider(widget.profileId)` → `OfflineOperationalReadinessService.evaluate`. Si `offlineReady`, Dashboard; si `authorizationRevoked`, mensaje de autorización; si `recoveryRequired`, “Conéctate a Internet y reintenta”; otros errores muestran estado offline/contexto. Si Entry devuelve `bootstrapRecoveryBlocked`, `:496` muestra overlay de reparación/reintento, **no** consulta cache para bypass.

### 2.2 Estados reales

| Capa | Outcome / reason | Significado/acción |
|---|---|---|
| Entry (`operational_bootstrap_entry_models.dart`) | `noAuthorizedContexts`, `selectionRequired`, `deviceBlocked`, `runtimeReadyAndBootstrapCompleted`, `runtimeSetupRequired`, `authorizationRevoked`, `transientFailure`, `bootstrapRecoveryBlocked`, `failed` | Selector/no membresía, dispositivo bloqueado, ready, setup administrativo, revocación, red/retry, reconciliación, fallo genérico. Ver switch del gate `:414–640`. |
| Bootstrap (`operational_bootstrap_orchestration_models.dart`) | `ready`, `authorizationRevoked`, `runtimeSetupRequired`, `recoveryBlocked`, `networkUnavailableWithCachedContext`, `transientFailure`, `failed` | `ready` solo tras bundles/checkpoints/issues; network cached **no** decide TTL. Entry mapea ambos transitorios a `transientFailure`. |
| Cached readiness (`offline_operational_readiness_service.dart`) | `ready/offline_ready`; `invalidContext/authenticated_scope_mismatch`; `recoveryRequired/authorization_projection_missing`, `runtime_missing_or_out_of_scope`, `cash_runtime_missing`, `required_datasets_incomplete`, `blocking_reconciliation_issues`, `canonical_cash_register_not_ready`; `authorizationRevoked/authorization_revoked` | `missingDatasets`, `blockingIssueCount`, `appDeviceId`, `authorizationValidatedAt` están en el resultado tipado. Priorizar reason y scope, no texto genérico de UI. |

### 2.3 Invariante offline exacto

**VERIFIED**, traducción de `OfflineOperationalReadinessService.evaluate` (`:83–206`):

```text
profile/business/branch/installation no vacíos
AND authenticatedProfileId == request.profileId
AND local_authorized_operational_contexts(profile,business,branch) existe y status=active
AND AppRuntimeContextStore.getContext(business,branch,installation) existe
AND runtime.profile/business/branch/installation coinciden y appDeviceId no vacío
AND (no cash capability OR runtime.cashRegisterId no vacío)
AND para cada dataset requerido: checkpoint(scope profile,business,branch,appDevice,
    bundle,dataset) existe, isComplete y convergenceStatus='complete'
AND no local_reconciliation_issues con ese profile/business/branch,
    severity='blocking', status='open'
AND (no cash capability OR cash_registers[id=runtime.cashRegisterId,
    business,branch].status='active')
→ ready
```

`OperationalBootstrapService.productPermissions` = `sales.create`, `inventory.read`, `inventory.purchase`. `cashPermissions` = `cash.read`, `cash.open`, `cash.close`, `cash.receive`, `cash.disburse`, `sales.create`. Se usa *effectivePermissions*, nunca role name. Pending outbox **no** bloquea por sí mismo. Una sesión de caja `open` **no** es requisito del Dashboard; sí puede serlo para POS/apertura/cierre. No relajar scope, auth revoked, checkpoint o blocker para “hacer pasar” el Moto.

### 2.4 Checkpoints requeridos

Todos usan tabla `local_operational_bootstrap_checkpoints`, clave lógica `(profile_id,business_id,branch_id,app_device_id,bundle,dataset)`, `status='complete'` (véase `OperationalBootstrapCheckpointRecord.isComplete`) y `convergence_status='complete'`; la instalación se valida por runtime, no es columna del checkpoint.

| Condición | bundle | dataset(s) exactos |
|---|---|---|
| Siempre | `core` | `context` |
| Alguna product permission | `product_operational` | `categories`, `products`, `product_barcodes`, `product_stock_balances` |
| Alguna cash permission | `cash_pos` | `cash_registers`, `open_cash_sessions`, `cash_movements`, `session_sales`, `session_sale_items`, `session_sale_payments` |

Fuente: `operational_bootstrap_service.dart:98–119`, `cash_pos_snapshot_applier.dart:31–38`, `offline_operational_readiness_service.dart:_requiredDatasets`. Un dataset de cero filas sigue necesitando checkpoint completo.

### 2.5 Consultas SQLite **sobre una copia**, nunca sobre DB original

Primero `PRAGMA query_only=ON;` y `PRAGMA table_info(...)` si el archivo instalado pudiera tener otra versión. Sustituir los UUID entre comillas; no imprimir `effective_permissions` ni `metadata_json` en un informe público si contienen datos sensibles. Archivo fuente privado: `app_local_database.sqlite` bajo `getApplicationDocumentsDirectory()` (`app_database.dart:2043–2044`). Runtime y selección **no están en SQLite**: `AppRuntimeContextStore` y `AppSelectedSyncContextStore` usan SharedPreferences; no inferirlos de los checkpoints. Auth Session tampoco se prueba desde SQLite.

```sql
PRAGMA query_only=ON;
PRAGMA user_version;
SELECT id,name,status,deleted_at FROM businesses WHERE id='<BUSINESS>';
SELECT id,business_id,name,status,deleted_at FROM branches WHERE id='<BRANCH>';
SELECT id,business_id,status FROM profiles WHERE id='<PROFILE>';
SELECT profile_id,business_id,branch_id,status,authorization_validated_at,
       effective_permissions FROM local_authorized_operational_contexts
 WHERE profile_id='<PROFILE>' AND business_id='<BUSINESS>' AND branch_id='<BRANCH>';
SELECT app_device_id,bundle,dataset,status,convergence_status,
       rows_received,pages_applied,retry_count,last_error,completed_at
  FROM local_operational_bootstrap_checkpoints
 WHERE profile_id='<PROFILE>' AND business_id='<BUSINESS>' AND branch_id='<BRANCH>'
 ORDER BY app_device_id,bundle,dataset;
SELECT id,domain,issue_type,entity_type,entity_id,severity,status,message,
       cash_register_id,cash_session_id,sale_id
  FROM local_reconciliation_issues
 WHERE profile_id='<PROFILE>' AND business_id='<BUSINESS>' AND branch_id='<BRANCH>'
   AND status='open' ORDER BY severity,created_at;
SELECT id,client_batch_id,domain,status,app_device_id,profile_id,
       mutation_count,applied_count,skipped_count,conflict_count,error_count,last_error
  FROM local_sync_batches
 WHERE business_id='<BUSINESS>' AND branch_id='<BRANCH>'
 ORDER BY created_at DESC LIMIT 50;
SELECT id,local_sync_batch_id,entity_table,entity_id,status,retry_count,error_code
  FROM local_sync_mutations
 WHERE business_id='<BUSINESS>' AND branch_id='<BRANCH>' AND status NOT IN ('applied','skipped')
 ORDER BY created_at DESC LIMIT 100;
SELECT id,business_id,branch_id,status,local_status,deleted_at FROM cash_registers
 WHERE business_id='<BUSINESS>' AND branch_id='<BRANCH>';
SELECT id,cash_register_id,business_id,branch_id,status,local_status,
       opened_at,closed_at,deleted_at FROM cash_sessions
 WHERE business_id='<BUSINESS>' AND branch_id='<BRANCH>' ORDER BY opened_at DESC;
```

**UNKNOWN** el nombre exacto del *device physical* instalado y si su release permite `run-as`; no ejecutar `pm clear`/uninstall. Si es build debuggable, comprobar `adb devices`, package con `adb shell pm list packages`, `adb shell run-as com.cronosmanagement.app pwd`; exportar copia fuera del repo usando mecanismo forense que incluya WAL/SHM o backup consistente y consultar **solo la copia**. `run-as` puede fallar en release: entonces no rootear; utilizar diagnóstico read-only existente de la app o pedir un build diagnóstico sin borrar datos. No copiar un solo `.sqlite` mientras hay WAL activo y asumir que está íntegro.

### 2.6 Procedimiento Moto y recetas condicionadas

1. Registrar build/hash, hora UTC, modo avión/conectividad, perfil (ID redactable), business/branch e instalación del dispositivo; no hacer sync/recovery manual aún.
2. Capturar outcome de Entry (`bootstrap_outcome`, `message`) y, si transitorio, `OfflineOperationalReadinessResult.outcome/reason/missingDatasets/blockingIssueCount/authorizationValidatedAt/appDeviceId` con logging seguro o infraestructura diagnóstica existente. Si no existe vía de lectura, **UNKNOWN**, no inventar causa.
3. Capturar autorización local, runtime SharedPreferences **solo IDs/scopes** (no tokens), selección profile-scoped, y comparar con current Auth user. Inspeccionar `cashRegisterId` canónico y appDevice del mismo contexto.
4. Consultar checkpoints y blockers con SQL anterior. Para cada faltante comparar `bundle/dataset/app_device_id`, `status`, `convergence_status`, no solo número de filas. `cash_pos/cash_movements` es sospechoso plausible por introducción reciente, **no diagnóstico demostrado**.
5. Consultar outbox y caja; comprobar si hay sesión cerrada legítima (permitida) o register canónico ausente/inactivo. No resolver issue ni borrar outbox.
6. Si hay acceso remoto autorizado read-only, comparar auth/runtime/snapshot/version, sin usar service_role ni ejecutar writes. Reproducir *exactamente* reason y filas en `test/features/sync/offline_operational_readiness_service_test.dart` y `business_context_required_gate_test.dart`.
7. Clasificar: checkpoint realmente faltante → recuperación online normal y confirmar que se complete; checkpoint completo pero no reconocido → revisar scope appDevice/branch o parser de `isComplete`; auth stale/revoked → revisar proyección y flujo de invalidación, no TTL inventado; caja canónica inconsistente → resolver por `CashPosRecoveryService`/guard scoped, no crear caja alternativa; issue real → servicio de reconciliación del dominio; falso positivo del gate → cambiar condición mínima **solo tras test**. Retestar online→offline→restart y sesión cerrada.

Tests actuales: `test/features/sync/offline_operational_readiness_service_test.dart` (OR-01…OR-08), `business_context_required_gate_test.dart`, `operational_bootstrap_service_test.dart`, `operational_bootstrap_entry_service_test.dart`, `cash_pos_operational_recovery_test.dart`, `test/features/sync/operational_branch_switching_test.dart`. Falta test con **estado exacto copiado/redactado del Moto** (mismo scope/checkpoints/runtime/issue) que demuestre outcome antes y después; no simular un caso distinto para afirmar cierre. Para una inspección estrictamente read-only de SharedPreferences, leer una copia cruda: `AppRuntimeContextStore.getContext` puede *migrar* una clave legacy a la nueva clave cuando coincide la branch.

## 3. D05 — paridad Hosted, solo lectura

**VERIFIED** CLI Supabase 2.118.0 disponible vía `npx --no-install supabase --version` desde `inventario-Backend`; `db dump --help` soporta `--linked`, `--local`, `--schema`, `--data-only`, `--file`. La auditoría previa sufrió `ECONNRESET` con `pnpm dlx`; no se intentó `migration list --linked` aquí. **UNKNOWN** historial Hosted de hoy. No ejecutar `db push`, `migration repair`, SQL de escritura ni RPC que muta.

En Git Bash:

```bash
cd /c/Users/Cronos/Developer/personal/inventario-app/inventario-Backend
npx --no-install supabase --version
npx --no-install supabase migration list --linked
# si falta binario cacheado: pnpm dlx supabase@2.118.0 migration list --linked
# si npm falla: usar Supabase Dashboard → Database → Migrations y SQL Editor read-only;
# no relinkear ni descargar binarios de fuentes no verificadas por conveniencia.
```

Comparar versiones/nombres con `ls supabase/migrations | tail -n 25`; no confiar en sólo el último número si hay gaps. En Dashboard SQL Editor, **SELECT exclusivamente** (puede requerir rol administrativo del panel):

```sql
SELECT version,name FROM supabase_migrations.schema_migrations
 ORDER BY version DESC LIMIT 25;
SELECT n.nspname AS schema,p.proname,pg_get_function_identity_arguments(p.oid) AS args,
       p.prosecdef AS security_definer,
       has_function_privilege('authenticated',p.oid,'EXECUTE') AS auth_execute,
       has_function_privilege('anon',p.oid,'EXECUTE') AS anon_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN
 ('process_sync_batch','register_pending_sync_batch','register_pending_sync_mutation',
  'register_pending_sync_mutations','get_branch_sales_report_summary',
  'get_branch_profitability_report_summary','get_branch_cash_flow_report_summary',
  'list_authorized_operational_contexts','resolve_business_runtime',
  'register_or_update_app_device') ORDER BY p.proname,args;
SELECT table_name,column_name,data_type FROM information_schema.columns
WHERE table_schema='public' AND (
 (table_name='cash_movements' AND column_name IN ('amount','occurred_at','cash_session_id','category')) OR
 (table_name='purchase_items' AND column_name IN ('unit_cost_cents','subtotal_cents','monetary_contract_version')) OR
 (table_name='purchases' AND column_name IN ('total_cents','financial_finalized_at','monetary_contract_version')) OR
 (table_name='sale_payments' AND column_name IN ('paid_at','created_at')) OR
 (table_name='sync_mutations' AND column_name IN ('idempotency_key','status','payload')))
ORDER BY table_name,column_name;
SELECT tgrelid::regclass::text AS table_name,tgname,tgenabled
FROM pg_trigger WHERE NOT tgisinternal AND tgname IN
 ('trg_sync_mutations_sale_payment_event_time','trg_sale_payments_immutable_paid_at');
```

| Contrato | Migración local de referencia | Esperado / comprobación |
|---|---|---|
| Registro sync idempotente S1A | `20260926141000_p2_5x_s1a_idempotent_sync_registration.sql` (+ S1 anterior) | `register_pending_sync_batch(jsonb)`, `register_pending_sync_mutation(jsonb)`, `register_pending_sync_mutations(jsonb)`; `authenticated` EXECUTE, `anon` no; `SyncRegistrationRemoteDataSource` los invoca. |
| Procesamiento | `20260831180000_intentional_stale_sale_reconciliation_v2.sql` y chain anterior | `process_sync_batch(uuid,text)` y base/wrapper de cash; revisar función efectiva, no solo el esqueleto `20260619163325`. |
| Caja ledger/pull | `20260925180000_p2_5x_c1_inactive_cash_movement_ledger.sql`, `20260926120000...productive_cash_movements.sql`, `20260926121000...cash_movement_bootstrap.sql` | `public.cash_movements`, columnas/scopes y snapshot cash_pos `cash_movements`. |
| Compra exacta | `20260926142000_p2_5x_c4a1_exact_purchase_money.sql` | `purchases.total_cents/financial_finalized_at/monetary_contract_version`, `purchase_items.unit_cost_cents/subtotal_cents`. |
| Pago evento | `20260927130000_p2_5x_c4d2_sale_payment_event_time.sql` | `sale_payments.paid_at` más dos triggers anteriores; `payment_event_time_contract=v1` requiere UTC. |
| Sales/margen/cash flow | `20260923120000_p2_6_a1_authoritative_sales_summary.sql`, `20260924120000_p2_6_b1_authoritative_profitability_summary.sql`, `20260927131000_p2_5x_c4d2_authoritative_cash_flow_report.sql` | Tres RPC `get_branch_*_report_summary(uuid,uuid,timestamptz,timestamptz)`; ACL y permisos internos diferentes: `reports.sales`, `reports.sales+sales.view_costs`, `reports.cash`. |
| Dependencia local de batches | Drift schema 17, commit `efe1714`; no equiparar a tabla Hosted sin evidencia | `local_sync_batch_dependencies` es local; backend verifica registro/aplicación S1/S1A. |

Si falta una versión o columna: **STOP aceptación**, plan de backup y deployment separado con autorización. No “probar” paridad invocando RPCs de registro/proceso, porque escriben.

## 4. D03 — backup/restore aislado, pendiente de ensayo

**VERIFIED** CLI 2.118.0 expone `supabase db dump --linked --schema ... --data-only --file`. **UNKNOWN** plan/retención Hosted, extensión/schemas necesarios para restaurar, credenciales de DB y éxito de restore. Los comandos siguientes son un **runbook propuesto**, no una ejecución validada; autorizaciones de backup y restore deben ser explícitas. Guardar fuera de Git, por ejemplo `C:/SecureBackups/CronosPOS/YYYY-MM-DD-pre-pilot` (`/c/SecureBackups/...` en Git Bash), con ACL privada. `public` contiene negocio; `auth`/`storage` contienen estado gestionado y requieren estrategia separada. Un dump `--schema public` **no** es backup completo del proyecto Supabase, Auth, objetos Storage, configuración ni secretos.

```bash
# Git Bash; ejecutar sólo con autorización de extracción Hosted.
cd /c/Users/Cronos/Developer/personal/inventario-app/inventario-Backend
mkdir -p /c/SecureBackups/CronosPOS/YYYY-MM-DD-pre-pilot
npx --no-install supabase db dump --linked --schema public \
  --file /c/SecureBackups/CronosPOS/YYYY-MM-DD-pre-pilot/schema-public.sql
npx --no-install supabase db dump --linked --schema public --data-only \
  --file /c/SecureBackups/CronosPOS/YYYY-MM-DD-pre-pilot/data-public.sql
sha256sum /c/SecureBackups/CronosPOS/YYYY-MM-DD-pre-pilot/*.sql
```

No usar `--dry-run`: puede imprimir cadena de conexión/credenciales efímeras. No imprimir contenido del dump ni passwords; comprobar exit code, archivo regular y tamaño >0. Antes de afirmar *backup completo*, definir export/custodia de Auth users, Storage objetos, roles/config y constatar plan Supabase real; **UNKNOWN** aún. Cifrado: si ya se dispone de 7-Zip confiable local, archivo `.7z` con AES-256 y contraseña introducida de forma interactiva, no pasada como argumento ni guardada en shell history; si no, usar almacenamiento privado cifrado del sistema con ACL/BitLocker verificado. Guardar hash del archivo cifrado y copia separada. No inventar PITR.

Restore de ensayo **LOCAL WRITE, no Hosted**: requiere autorización para crear/destruir entorno aislado. Iniciar stack local (`npx --no-install supabase start`), comprobar `docker ps` y versión PostgreSQL. No restaurar sobre la DB `postgres` del proyecto local existente ni ejecutar `db reset` para este ensayo sin autorización. Crear DB aislada *vacía* dentro del contenedor local: `docker exec supabase_db_inventario-Backend createdb -U postgres -T template1 pilot_restore_probe`; alimentar schema y luego data con `docker exec -i supabase_db_inventario-Backend psql -v ON_ERROR_STOP=1 -U postgres -d pilot_restore_probe < .../schema-public.sql` y después `.../data-public.sql`. **INFERRED/UNTESTED**: el dump puede requerir roles, extensions o esquemas gestionados no presentes en esa DB; si falla, conservar logs sanitizados, no corregir Hosted. Verificar `SELECT count(*)` de `businesses,branches,products,product_stock_balances,sales,sale_items,sale_payments,purchases,purchase_items,cash_registers,cash_sessions,cash_movements,sync_batches,sync_mutations`; `pg_proc` para RPCs anteriores; comparar conteos/hashes de inventario de tabla con origen read-only. Historial `supabase_migrations.schema_migrations` quizá no forma parte del dump `public`; cotejar aparte y **no** afirmar restaurado si no existe. Destruir `pilot_restore_probe` sólo con autorización específica y ruta/DB verificada. Una restauración de public no recupera Auth ni Storage: documentar ese límite explícitamente.

Hosted no cubre Drift privado: `local_sync_batches`, `local_sync_mutations`, dependencias, movimientos locales no ACK, balances operativos, issues/checkpoints, SharedPreferences de installation/runtime/selección y auth session del device. Antes de desinstalar/reemplazar, registrar pendientes + último ACK, copiar datos localmente con consentimiento y validar que Hosted contiene cada operación; nunca `pm clear` por conveniencia.

## 5. D02 — matriz manual de aceptación APK (usuario, no ejecutada aquí)

Registrar por fila: fecha, operador, device, Android version, SHA-256 APK, profile/business/branch, acción, evidencia redactada, PASS/WARN/FAIL. Usar negocio piloto autorizado, SKU real curado, dinero/stock reales sólo con permiso del dueño; **no** inventar ventas/clientes/movimientos para “pasar” la prueba.

| Acción | Esperado | Si falla / decisión |
|---|---|---|
| Verificar hash, package, firma, versionCode 2; instalar manualmente en equipo limpio o misma firma | Instalación preserva datos si upgrade compatible; label/icon Cronos POS | Firma/package incompatibles: **STOP**, no uninstall si hay outbox. |
| Login e invitación/selección | Auth correcto, business+branch explícitos, permisos efectivos | Tenant/branch equivocados o leakage: **STOP PILOT**. |
| Bootstrap online → Dashboard | Core/product/balance/cash requeridos completos, cero blockers, `offlineReady=true` | Reason tipado; FAIL, no retry a ciegas. |
| Caja | Canonical register, sesión abierta existente o apertura autorizada; efectivo inicial contado | Caja alternativa/duplicada o expected incoherente: STOP. |
| POS (solo venta real autorizada) | Sale/items/payments/movement local una vez, stock branch decrementa una vez; sync ACK | Doble cobro/stock: STOP. |
| Inventario | Stock y mínimo por branch, history y costo autorizado | Saldo de otro branch o negativo inexplicado: STOP. |
| Compras (solo compra real) | Purchase/items/movement +stock, exact cents y dependencia Product | Doble +stock o total distinto: STOP. Si pagada cash, registrar salida separada una vez. |
| Reportes ventas/margen/cash | Scope y período exactos; margen histórico no se presenta como certeza si D07 pendiente | Datos cruzados: STOP; falta cache: FAIL/WARN según uso. |
| “Sincronizar ahora” | Pending→ACK, status query-derived; cero blockers inesperados | Partial/ambiguous: detener nuevas operaciones afectadas, capturar IDs. |
| Reiniciar online y luego offline con bootstrap completo y caja legítimamente cerrada | Dashboard entra sin red; POS exige caja abierta; no red screen | D01: capturar `reason/missingDatasets/issues`, FAIL, no borrar app. |
| Reconectar | Reintento idempotente; stock/efectivo/IDs locales y Hosted convergen | Doble efecto o pérdida: STOP. |
| Cierre Caja por UI con efectivo físico | expected/actual/difference explícitos, close sync seguro y estado closed proyectado | Diferencia inexplicada o sesión stale: STOP, no SQL manual. |

## 6. D10 — observabilidad mínima y consultas read-only

**VERIFIED** `public.activity_logs` (`business_id,user_id,action,affected_table,record_id,created_at,metadata`), `public.sync_logs` (`business_id,device_id,sync_type,records_uploaded,records_downloaded,sync_status,error_message,created_at`) vienen de `20260613182343_initial_remote_schema.sql`; backend `sync_batches`, `sync_mutations`, `cash_sessions`, `cash_movements` y Drift outbox/issues existen. La ACL efectiva Hosted es **UNKNOWN**; ejecutar SQL sólo desde Dashboard con acceso autorizado o endpoint RLS propio. Nunca imprimir JWT, `metadata` completa, `payload`, claves ni mensajes sensibles.

```sql
-- Dashboard SQL Editor: sustituir UUIDs, SELECT solamente.
SELECT status,count(*) FROM public.sync_batches
 WHERE business_id='<BUSINESS>'::uuid AND branch_id='<BRANCH>'::uuid
   AND created_at >= now()-interval '2 days' GROUP BY status;
SELECT id,client_batch_id,status,mutation_count,applied_count,skipped_count,
       conflict_count,error_count,created_at
 FROM public.sync_batches WHERE business_id='<BUSINESS>'::uuid
   AND branch_id='<BRANCH>'::uuid ORDER BY created_at DESC LIMIT 20;
SELECT entity_table,status,count(*) FROM public.sync_mutations
 WHERE business_id='<BUSINESS>'::uuid AND branch_id='<BRANCH>'::uuid
   AND created_at >= now()-interval '2 days' GROUP BY entity_table,status;
SELECT id,cash_register_id,status,opened_at,closed_at FROM public.cash_sessions
 WHERE business_id='<BUSINESS>'::uuid AND branch_id='<BRANCH>'::uuid
 ORDER BY opened_at DESC LIMIT 10;
SELECT direction,category,count(*),sum(amount) FROM public.cash_movements
 WHERE business_id='<BUSINESS>'::uuid AND branch_id='<BRANCH>'::uuid
   AND occurred_at >= now()-interval '1 day' GROUP BY direction,category;
SELECT id,status,created_at FROM public.sales
 WHERE business_id='<BUSINESS>'::uuid AND branch_id='<BRANCH>'::uuid
 ORDER BY created_at DESC LIMIT 10;
SELECT product_id,quantity_on_hand FROM public.product_stock_balances
 WHERE business_id='<BUSINESS>'::uuid AND branch_id='<BRANCH>'::uuid
   AND product_id IN ('<SKU1>'::uuid,'<SKU2>'::uuid);
SELECT sync_status,count(*) FROM public.sync_logs
 WHERE business_id='<BUSINESS>'::uuid AND created_at >= now()-interval '1 day'
 GROUP BY sync_status;
SELECT action,affected_table,created_at FROM public.activity_logs
 WHERE business_id='<BUSINESS>'::uuid AND created_at >= now()-interval '1 day'
 ORDER BY created_at DESC LIMIT 20;
```

**VERIFIED** `public.product_stock_balances.quantity_on_hand` existe en la migration local `20260616201248_inventory_product_stock_balances.sql`; su presencia efectiva Hosted depende de D05. En dispositivo usar consultas D01 para outbox/issues, porque un batch aún no subido no figura Hosted. Cinco minutos: (1) confirmar business/branch/device + red; (2) ver `Pendientes` y batch `partial/failed`; (3) blockers scoped; (4) caja única/open o closed legítima y cash movements; (5) dos SKU, últimas ventas y backup del día. Escalar inmediatamente acceso cruzado, dinero/stock divergente sin pendiente explicativo, duplicados o Drift ilegible; no limpiar datos.

## 7. D12 — matriz de sync/partial/retry

**VERIFIED** `LocalSyncOutboxService`/`LocalSyncOutboxDao` conservan `client_batch_id`, `client_mutation_id`, `idempotency_key`, `retry_count`, estados y `local_sync_batch_dependencies`; `SyncRegistrationRemoteDataSource` registra por RPC S1A. `ProductiveManualSyncService.run` coordina catálogo→cash→POS→purchases→inventory hasta ocho pasadas, con dependencias; scheduled y cash-close tienen entrypoints separados. No sumar retry_count para inferir efecto remoto: comprobar ACK/evidencia.

| Dominio | Registros locales / uploader | Outbox/remote/ACK | Retry, blocker y prueba |
|---|---|---|---|
| Catálogo | `products/categories/local_product_barcodes`; `CatalogSyncUploadService.uploadPendingCatalogBatches` | `local_sync_*`; `CatalogSyncRemoteDataSource.uploadAndProcessCatalogBatch` → registro S1A + `process_sync_batch`; match por `idempotency_key`, duplicate catalog conflicts idempotentes sólo tras comprobación | Partial marca mutaciones según resultados; producto-before-purchase. `test/features/catalog/catalog_sync_reliability_test.dart`, `test/features/inventory/catalog_product_identity_local_test.dart`. |
| Caja | `cash_registers/cash_sessions/local_cash_movements`; `CashSyncUploadService.uploadPendingCashBatches` | `CashSyncRemoteDataSource` → registro S1A + `process_sync_batch`; recovery/cierre proyectan estado canónico | Sesión stale/close y cash movement pendiente pueden bloquear cierre; no crear register alternativo. `test/features/sync/cash_pos_operational_recovery_test.dart`, `test/features/cash/local_cash_movements_test.dart`, `test/features/sync/cash_close_sync_trigger_service_test.dart`. |
| POS | `sales/sale_items/sale_payments/local_inventory_movements`; `PosSyncUploadService.uploadPendingPosBatches` | `PosSyncRemoteDataSource` registra/procesa; primero revisa entidades remotas ya existentes e inventario; ACK por mutación/resultado, `PosLocalSaleDao.reconcileCompletedPosSalesFromOutbox` | Closed cash session produce blocker/reconciliación, no borrar sale dirty. `test/features/sync/stale_cash_session_sale_reconciliation_test.dart`, `test/features/sync/unmaterialized_local_sale_discard_test.dart`. |
| Compras | `purchases/purchase_items/local_inventory_movements`; `PurchasesSyncUploadService.uploadPendingPurchasesBatches` | `PurchasesSyncRemoteDataSource` registro/proceso y comprobación de entidades; ACK local tras evidencia | `PurchaseProductDependencyResolver.resolve` = waiting/blocked para producto no materializado; permission retry con `inspectPermissionRetry/finalizePermissionRetry`; `test/features/sync/purchase_product_dependency_test.dart`. |
| Inventario | `local_inventory_movements/local_product_stock_balances`; `InventorySyncUploadService.uploadPendingInventoryBatches` | `InventorySyncRemoteDataSource` registra/procesa; balance posterior = base remota + movimientos no ACK | ACK ambiguo/balance remoto ausente requiere `InventoryBalanceReconciliationService`, no +quantity dos veces. `test/features/sync/inventory_balance_reconciliation_test.dart` (confirmar path con `rg --files test`). |

Los nombres de algunos test de la tabla son rutas a confirmar (`rg --files inventario-Frontend/test | rg 'cash_pos|inventory_balance'`) antes de copy-paste. **No hacer manualmente**: borrar/editar batches, mutations, idempotency keys o sync_conflicts; reinsertar sale/purchase/movement; marcar `applied` sin evidencia; ejecutar `process_sync_batch` con payload improvisado; cerrar Caja en SQL. Ante `partial/error`: preservar ID/scope/error, consultar Hosted read-only, usar flujo productivo idempotente o reparación tipada; si ACK es ambiguo, escalar.

## 8. D06 y D07 — recetas sin implementación

### D06 compra → salida opcional

`inventario-Frontend/lib/features/inventory/presentation/screens/purchase_entry_screen.dart:_savePurchase` (`:775`) llama `purchaseLocalServiceProvider.createLocalPurchase` (`:803`) y crea compra/stock, **no** cash. `CashMovementDialog` (`lib/features/cash/presentation/widgets/cash_movement_dialog.dart:60`) hoy exige `profileId,businessId,branchId,cashRegisterId,cashSessionId,direction,loadExpectedCashCents,submit`; no acepta prefill de amount/category/source/nota. `_submit` construye `CashMovementRequest`, `CashMovementService.recordMovement` (`application/cash_movement_service.dart:55`) valida scope, sesión abierta, permiso `cash.disburse` para outflow y `expected - amount >= 0`, inserta ledger+outbox en transacción; mismo `idempotencyKey` y payload retorna `alreadyRecorded=true`. `cashMovementServiceProvider`/submit provider están en `cash_movement_provider.dart`.

**INFERRED diseño posterior**: tras resultado exitoso de compra mostrar botón **opcional** “Registrar salida de efectivo”; pulsarlo navega/abre el dialog existente sólo si `cash.disburse` y caja canónica/sesión abierta del mismo scope. Ampliar `CashMovementDialog` de forma focal con `initialCategory='supplier_purchase'`, `initialAmountCents` (derivado del total exacto de la compra, no monto pendiente de CxP), `initialSourceType='purchase'`, `initialSourceId=purchaseId`, `initialNote`; construir `CashMovementRequest` con esos datos. Confirmación humana obligatoria. Persistir/reutilizar una clave de intención estable por purchase+acción o bloquear segunda creación por `(business,source_type='purchase',source_id)` según decisión explícita; la idempotencia actual solo cubre **la misma** key, no dos taps con keys distintas. Cancelar dialog no altera compra ni Caja. Tests: compra sin salida, prefill correcto, permiso/session, cash insuficiente, doble tap/reentrada sin doble ledger, outbox una vez, sync idempotente. No crear `purchase_payments` ni asumir compra pagada por estar registrada.

### D07 costo histórico

**VERIFIED** `inventario-Backend/supabase/migrations/20260616194609_pos_sale_items_snapshots_totals.sql:67–95` rellenó `sale_items.unit_cost_snapshot = coalesce(si.unit_cost_snapshot, products.purchase_price)` en ese instante. Las filas no nulas preexistentes se preservaron; no hay flag de provenance en esa migration. POS actual captura en `inventario-Frontend/lib/features/sales/data/datasources/pos_local_sale_dao.dart:145` y lo sube por `pos_sync_outbox_service.dart:289`. `20260924120000_p2_6_b1_authoritative_profitability_summary.sql` considera **cualquier no-NULL** conocido, NULL desconocido; no separa backfill. **INFERRED** ventas anteriores a la implantación correcta de POS pueden tener costo aproximado; **UNKNOWN** cuáles fueron backfilled sin evidencia persistida adicional. `created_at` anterior al cutoff da cohorte de riesgo, no prueba individual. Nunca sustituir por average_cost/purchase_price actual.

Query Hosted read-only para principal (`business`/`branch` que defina operador), cutoff **parametrizado**: primero documentar hora real de aplicación Hosted de la migration; el timestamp del filename no es hora de ejecución Hosted.

```sql
WITH scoped AS (
 SELECT i.id,i.unit_cost_snapshot,i.quantity,
        i.subtotal-i.discount_amount AS net_item_sales,s.created_at
 FROM public.sales s JOIN public.sale_items i ON i.sale_id=s.id
 WHERE s.business_id='<BUSINESS>'::uuid AND s.branch_id='<BRANCH>'::uuid
   AND s.status='completed' AND s.deleted_at IS NULL AND s.voided_at IS NULL
   AND i.deleted_at IS NULL
)
SELECT created_at < '<HOSTED_CUTOFF_UTC>'::timestamp AS pre_cutoff,
 count(*) items,
 count(*) FILTER (WHERE unit_cost_snapshot IS NULL) null_cost,
 count(*) FILTER (WHERE unit_cost_snapshot=0) zero_cost,
 count(*) FILTER (WHERE unit_cost_snapshot>0) positive_cost,
 sum(net_item_sales) net_sales,
 sum(quantity*unit_cost_snapshot) FILTER (WHERE unit_cost_snapshot IS NOT NULL)
   AS stored_cogs_not_provenance_verified
FROM scoped GROUP BY 1 ORDER BY 1;
```

**INFERRED política**: para piloto, mostrar “margen de ventas históricas puede ser aproximado; costo no recuperable de forma confiable” y limitar decisiones financieras a cohorte posterior a captura POS comprobada. Si negocio exige exactitud, no presentar cohortes mixtas como autoritativas sin provenance confiable. Cambio posterior probable: badge/notice en UI de margen y/o rango confiable; no recalcular números con costos actuales. Test de período pre/post y permiso `sales.view_costs`.

## 9. D08 y D09 — activación de nuevos dispositivos/contextos

### D08 tablet

| Pantalla | Estrategia verificada | Riesgo / smoke posterior |
|---|---|---|
| Dashboard `main_dashboard_screen.dart:1150` | `LayoutBuilder`: 1 columna <580dp, 2 en [580,900), 3 ≥900; `GridView` no scroll propio | Cards muy altas/estrechas con textScale 1.5; probar 360/600/900dp, landscape y tap. |
| POS `pos_sale_screen.dart:991,1801` | Layout amplio ≥900; sub-layout “narrow” <380 | 900 justo y teclado/pago; probar 380/900/1200, landscape, texto 1.5, cobro sin overflow. |
| Compras `purchase_entry_screen.dart:936,1153` | Wide ≥900; lista acotada por 52 % de alto | Diálogo cantidad/costo con teclado, carrito y acción guardar; probar 360/900dp + landscape. |
| Caja `cash_dashboard_screen.dart:764` | `Wrap` en acciones | Diálogo de movimiento y cierre con teclado/textScale; probar 360/600/900dp. |
| Inventario `inventory_product_stock_list_screen.dart:504,1467` | `Wrap`, dialog maxWidth 420 | Filtros/cards y modal en pantalla baja; probar scroll/barcode/stock por branch. |
| Reportes `sales_report_screen.dart`, `cash_flow_report_screen.dart` | `ListView` y `Wrap` | Selector de rango, cifras largas/negativas; probar textScale 1.3/1.5 y landscape. |

**UNKNOWN** ancho mínimo *seguro*: no puede fijarse sin widget/physical smoke; 360dp es objetivo de prueba, no garantía. No ejecutar emulador ni habilitar tablet en piloto antes de PASS.

### D09 multinegocio

**VERIFIED** aceptación en `business_context_required_gate.dart:_acceptBusinessInvitation/_continueAfterInvitationAcceptance` usa `PostInvitationBootstrapStabilizationService.stabilize`; `OperationalBootstrapEntryService.run` valida selección con `_match(contexts,business,branch)` y, si hay >1 sin selección válida, `selectionRequired`. `AppSelectedSyncContextStore` es profile-scoped; `AppRuntimeContextStore` además business/branch/installation y verifica profile al evaluar readiness. No auto-switch seguro por “primer contexto”: eso rompería aislamiento A/B.

Prueba manual futura: A activo → invitación pendiente B en banner → aceptar → refresh server-authoritative A+B → selector/selección explícita de B → comprobar `profileId,businessId,branchId,appDeviceId,cashRegisterId` B y stock/caja B → restart online sigue B → offline usa solo checkpoints/proyección/runtime B → volver A y verificar scope A. Si B no autorizado/revocado, gate no debe entrar; no reutilizar cache A. Tests: `business_context_required_gate_test.dart`, `post_invitation_bootstrap_stabilization_test.dart`, `app_selected_sync_context_store_test.dart`.

## 10. P2.6C/D/F — diseño a aprobar, no contratos implementados

Referencia **VERIFIED**: `get_branch_sales_report_summary`, `get_branch_profitability_report_summary`, `get_branch_cash_flow_report_summary` aceptan `(p_business_id uuid,p_branch_id uuid,p_from timestamptz,p_to timestamptz)` y devuelven `authoritative_as_of`; Flutter `SalesReportService/Controller`, `ProfitabilityReportService/Controller`, `CashFlowReportService/Controller` usan `ReportSnapshotLocalDao` con scope profile/business/branch, capability y cache revocable. Lo siguiente es **INFERRED/PROPOSED**; requiere decisión del chat principal, migración+pgTAP en fase separada.

| Fase | RPC propuesta / fuente y agregación | Capability, cache/UI, pruebas |
|---|---|---|
| P2.6C Inventory | `get_branch_inventory_report_summary(p_business_id uuid,p_branch_id uuid,p_as_of timestamptz)`; `product_stock_balances` + products activos en branch; count SKU, on_hand/available, valoración con average_cost, agotados/bajo mínimo; definir si `as_of` histórico está soportado (si no, **actual solamente**, no reconstruir de costo actual) | `reports.inventory` + permiso de costo si valor mostrado; snapshot key `inventory:branch:<id>:asof:<UTC>` versionado/profile-scoped; offline cache rotulada; screen `inventory_report_screen.dart`; pgTAP scope/NULL/zero/cross-tenant y Flutter auth/cache/refresh. |
| P2.6D Purchases | `get_branch_purchases_report_summary(p_business_id uuid,p_branch_id uuid,p_from timestamptz,p_to timestamptz)`; purchases/items finalizados, totales `total_cents` exactos, count y unidades; separar `legacy_stored`/exact y no inferir pagos | **UNKNOWN** capability final (`reports.inventory` u otra; decisión requerida); snapshot `purchases:<from>:<to>:v1`; offline cache con fecha/coverage; screen `purchases_report_screen.dart`; pgTAP dinero exacto, status/deleted/cross-branch y Flutter período/revocación. |
| P2.6F Export | Preferir export **de snapshot autorizado** con scope/rango/versión, no RPC SQL masiva; si servidor: `export_branch_report(p_business_id,p_branch_id,p_report_type,p_from,p_to)` con paginación/límite y redacción | `reports.export` **AND** permiso fuente (`reports.sales`, `reports.cash`, `reports.inventory`, `sales.view_costs` si costo); cache no concede export tras revocación; UI acción en cada reporte, formato/PII/límites por decidir; tests de fuga tenant, costo sin permiso, archivo offline/metadata y tamaño. |

No usar `products.stock_quantity`, agregar movimientos locales a RPC Hosted numérico ni consultar tablas protegidas directo desde UI.

## 10.1 Deudas diferidas D11 y D13–D19: recetas de entrada

Estas no habilitan expansión automática del piloto. Para cada una, verificar primero HEAD/branch/status y reproducir antes de implementar.

| ID | Estado/control verificado y condición PASS/FAIL | Diagnóstico, cambio probable, prohibición y pruebas |
|---|---|---|
| D11 catálogo/licencias | `inventario-Backend/tools/catalog_import/catalog_tool.py`, `catalog_importer.py` y `README.md:230` exigen `image_license` cuando hay `image_source_key`; PASS = SKU/barcode único y fuente/licencia trazable del surtido piloto; FAIL = conflicto/asset no autorizado. | `cd inventario-Backend/tools/catalog_import && python catalog_tool.py validate` (lectura del dataset; comprobar help antes de flags adicionales); revisar report, plan y snapshot sin promover lotes. Curar dataset/asset en tarea separada con IDs estables. No importar masivamente durante operación. `tests/test_catalog_tool.py`, `tests/test_catalog_importer.py`. |
| D13 reportes | `inventario-Frontend/lib/features/reports/` implementa ventas/margen/cash flow, no C/D/F; PASS cuando RPC+ACL+cache/UI/pgTAP y Flutter scope/offline/revocación de §10 están aprobados. | Buscar patrones en `sales_report_service.dart`, `profitability_report_service.dart`, `cash_flow_report_service.dart` y sus tests; no reemplazar por consultas cliente directas ni usar stock legacy. |
| D14 void/refund | `inventario-Backend/supabase/migrations/20260615182950_multitenancy_seed_roles_permissions.sql` define `sales.void`/`sales.refund`; `features/sales` no expone UX productiva de devolución ordinaria. PASS = contrato contable de reversa de pago, caja y stock, idempotente; FAIL = editar `sales.status` aislado. | Antes de código, definir política con dueño: venta total/parcial, efectivo entregado, stock retornado, período y auditoría. Tests pgTAP doble void/refund/cross-tenant, Flutter offline/retry. No reciclar el flujo *discard unmaterialized sale* para venta real. |
| D15 administración | `inventario-Frontend/lib/features/administration/presentation/screens/{administration_home_screen,business_team_screen,business_branches_screen}.dart` y `business_administration_service.dart` cubren home/equipo/sucursales; lifecycle completo de membresía/device no aceptado. | Reproducir rol revocado, device reemplazado, custom role y negocio cruzado con fixture autorizado; diseñar RPC/ACL por acción antes de UI. No borrar app_devices remotos ni inferir revocación por nombre de rol. Tests cross-tenant, revocación online/offline y scopes. |
| D16 docs | `docs/ARCHITECTURE.md`, `docs/ROADMAP.md`, `docs/TESTING.md` contienen baseline histórico (schema 8/36 tests en audit); HEAD es schema 17. PASS = cada documento fechado y contrastado con HEAD/tests; FAIL = instrucciones contradictorias. | Actualizar documentación **después** del pilot gate, conservando historia/decisiones. No usar esos archivos como prueba del código actual. Revisión textual y `git diff --check`. |
| D17 dependencias | Flutter 3.44.1/Dart 3.12.1; analyzer previo dejó 27 infos de deprecación/estilo sin errors/warnings. PASS = upgrade separado con analyze, full suite y APK firmado aceptado; FAIL = upgrade durante incidente D01. | `inventario-Frontend/pubspec.yaml`, `pubspec.lock`, `android/app/build.gradle.kts`, `lib/app/theme/shadows.dart`; `flutter analyze --no-pub`, `flutter test --no-pub`, build y smoke manual. No usar upgrade para enmascarar fixture obsoleto. |
| D18 finanzas | `CashMovementService` categoría `supplier_purchase` **no** crea `purchase_payments` ni saldo proveedor. PASS requiere decisión CxP/pagos parciales/ledger reversible; FAIL = llamar “pagada” a toda compra. | Diseño separado backend+Drift+UI con migración y pgTAP de invariantes antes de implementación. No inferir pagos desde total de compras ni reutilizar cash outflow como CxP formal. |
| D19 distribución | APK manual `1.0.0+2`, `com.cronosmanagement.app` y firma release existentes; Store/telemetry no implementados. PASS futura = canal/privacidad/firma/versionCode/rollout validados; FAIL = cambiar package o certificado y esperar upgrade in-place. | `inventario-Frontend/android/app/build.gradle.kts`, `AndroidManifest.xml`, `config/prod.json`; build metadata/hash + prueba de upgrade sin borrar datos. No publicar secrets/telemetry ni generar nueva keystore por conveniencia. |

## 11. Roadmap después del gate de piloto

| Fase | Goal / archivos probables | Backend / Drift / UI | Tests y aceptación |
|---|---|---|---|
| P2.9 | Primer día supervisado; checklist D02/D10, `productive_manual_sync_service.dart`, Caja/POS/Inventario | Sin backend/Drift nuevo previsto; UI sólo por bug demostrado | Venta/compra/caja reales autorizadas, stock+cash y outbox convergen; backup+restore previamente probado. |
| P3.0 | Estabilizar D06–D12 según incidentes; purchase/cash dialog, margin UI, sync retry, tablet/multinegocio | Backend sólo si contrato demostrado insuficiente; Drift sólo con autorización; UI focal | Tests de idempotencia/interrupción, smoke branch/device/textScale; no doble ledger. |
| P3.1 | Reportes C/D/F, void/refund y administración D13–D17 | Backend RPC/RLS/pgTAP probable; Drift cache si se decide; UI report/admin | Cost provenance, ACL cruzada, cache revocable, export redactado, devolución contable y release upgrade. |
| P4 | CxP/purchase_payments, contabilidad, distribución Store/telemetry | Decisiones arquitectónicas nuevas; backend+Drift+UI probables | Ledger financiero y migración histórica propia; release channels/privacy/rollout. |

## 12. File map y symbol map

| Área | Archivo / símbolos | Entrada → salida; efecto; por qué importa; test |
|---|---|---|
| Auth/router | `inventario-Frontend/lib/app/router/app_router.dart`; `productiveAuthPhaseProvider` en `features/auth/application` | Session/profile → ruta/gate; no saltar auth; `productive_auth_routing_test.dart`. |
| Entrada | `features/sync/application/operational_bootstrap_entry_service.dart`: `OperationalBootstrapEntryService.run` | modo/selection → `OperationalBootstrapEntryResult`; discovery, registro device **write normal**, runtime/cache/bootstrap; `operational_bootstrap_entry_service_test.dart`. |
| Gate | `features/sync/presentation/widgets/business_context_required_gate.dart`: `_buildResult` | Entry/readiness → Dashboard/selector/overlay; `business_context_required_gate_test.dart`. |
| Readiness | `features/sync/application/offline_operational_readiness_service.dart`: `evaluate` | profile/business/branch/installation → outcome/reason/missingDatasets; read-only local; `offline_operational_readiness_service_test.dart`. |
| Bootstrap | `features/sync/application/operational_bootstrap_service.dart`: `run` | contexto+runtime+modo → bundles/convergence/issues; aplica remoto en Drift, sin outbox nuevo; tests de bootstrap/recovery. |
| Checkpoint/issues | `features/sync/data/datasources/operational_bootstrap_checkpoint_local_dao.dart`: `getRecord`; `reconciliation_issue_local_dao.dart`: `getOpenBlockingIssues` | scope → checkpoint/issues; base de `offlineReady`; tests de recovery. |
| Proyección/runtime | `authorized_operational_context_local_dao.dart`: `getContextRecord`; `application/app_runtime_context_store.dart`: `getContext/saveContext`; `app_selected_sync_context_store.dart` | auth efectiva en Drift, runtime/selection en prefs; aislamiento profile/branch. |
| Sync coordinator | `features/sync/application/productive_manual_sync_service.dart`: `run`; `app_sync_coordinator_service.dart`: `runManualSync/runScheduledSyncIfDue/runSyncForCashClose` | contexto → uploads/pulls/estado; writes remoto normales **no ejecutar en diagnóstico read-only**; `productive_scheduled_sync_service_test.dart`. |
| Outbox | `features/sync/application/local_sync_outbox_service.dart`: `enqueueUploadBatch`; `data/datasources/local_sync_outbox_dao.dart`; `sync_registration_remote_datasource.dart` | mutaciones/keys → batches y RPC registration; retry/dependencies; `sync_registration_remote_datasource_test.dart`. |
| Caja | `features/cash/application/cash_movement_service.dart`: `recordMovement`, `loadExpectedCashCents`; `cash_session_local_service.dart`; `cash_movement_dialog.dart` | scope/sesión/monto → ledger local+outbox, protección no-negative; `local_cash_movements_test.dart`, dialog tests. |
| POS | `features/sales/data/datasources/pos_local_sale_dao.dart`; `features/sync/application/pos_sync_upload_service.dart` | sale+items+payments+movement → outbox/ACK/recovery; stale sale tests. |
| Compras | `features/inventory/presentation/screens/purchase_entry_screen.dart:_savePurchase`; `features/sync/application/purchases_sync_upload_service.dart`; `purchase_product_dependency_resolver.dart` | compra local + stock → dependencia Product/remote ACK; purchase tests. |
| Inventario | `features/sync/application/inventory_balance_reconciliation_service.dart`; `features/inventory` stock/history DAOs | base remota + no ACK → saldo branch; never `products.stock_quantity`; reconciliation tests. |
| Reportes | `features/reports/application/{sales_report_service,profitability_report_service,cash_flow_report_service}.dart`; `data/datasources/report_snapshot_local_dao.dart` | scope/período → RPC autoritativo + cache; capability y revocación; report tests. |
| Drift | `core/database/app_database.dart` (`AppDatabase.schemaVersion=17`, tablas, migración, beforeOpen FK) | estado local; `app_database.g.dart` generado no editar; `app_database_migration_test.dart`. |
| Backend | `inventario-Backend/supabase/migrations/20260926141000...S1A.sql`, `20260927131000...cash_flow.sql`, `20260924120000...profitability.sql` | RPC/RLS/contract authoritative; pgTAP focal + parity D05. |

Antes de ejecutar cualquier path de test sugerido no confirmado, usar `rg --files inventario-Frontend/test | rg '<patrón>'` y escoger el archivo real. La salida exacta de métodos internos puede cambiar con nuevos commits; inspeccionar diff antes de editar.

## 13. Do-not-touch

Rescue stash (no listar/aplicar/eliminar), `app_database.g.dart` manual, `catalog_import/reports` y `tmp` históricos, APK release untracked, Hosted sin autorización específica, `service_role`/JWT/password/signing key, `config/prod.json` salvo decisión, almacenamiento del dispositivo con operaciones pendientes. No instalar debug sobre piloto ni desinstalar/`pm clear` para “resolver” readiness; no reset/rebase/restore/clean ni commit/push implícitos. No relajar RLS/permissions por el SIGSEGV local documentado en `docs/TESTING.md`.

## 14. Command Index

### SAFE READ-ONLY (sin writes Hosted)

```bash
cd /c/Users/Cronos/Developer/personal/inventario-app
git status --short; git branch --show-current; git log --oneline --decorate -15
git diff --check
cd inventario-Frontend
flutter analyze --no-pub --no-fatal-infos
flutter test --no-pub test/features/auth/productive_auth_routing_test.dart
flutter test --no-pub test/features/auth/productive_registration_test.dart
flutter test --no-pub test/features/sync/operational_branch_switching_test.dart
flutter test --no-pub test/features/sync/offline_operational_readiness_service_test.dart
flutter test --no-pub
sha256sum releases/Cronos-POS-Pilot-1.0.0-build2.apk
cd ../inventario-Backend
npx --no-install supabase --version
npx --no-install supabase migration list --linked
# SQLite: sqlite3 COPIA-FUERA-DEL-REPO 'PRAGMA query_only=ON; SELECT ...;'
```

Tests locales pueden escribir artefactos de build/cache, nunca Hosted. Consultas SQL D01/D05/D10 son sólo lectura. `git diff --check` no incluye untracked.

### LOCAL WRITE — autorización y entorno aislado

```bash
# Backup Hosted: extracción read-only REMOTA pero crea archivos LOCALES sensibles;
# comandos exactos y scope public en sección D03, autorización requerida.
# Restore: createdb/psql en DB local pilot_restore_probe según D03;
# NO ejecutar sobre postgres/Hosted y NO usar db reset sin permiso.
```

### HOSTED WRITE — DO NOT RUN WITHOUT EXPLICIT AUTH

`supabase db push --linked`, `migration repair`, SQL INSERT/UPDATE/DELETE, `process_sync_batch`, `register_pending_sync_*`, `create_business`, `ensure_business_runtime_setup`, sync productivo, import comercial. No convertir estas acciones en “diagnósticos”.

Git commit flow **sólo cuando usuario autorice**: `git status --short` → `git diff --check` → `git diff -- <paths>` → `git add -- <paths exactos>` → `git diff --cached --check` → `git diff --cached --stat` → `git commit -m '<alcance>'`; no `git add .` con reportes históricos. No push por defecto.

## 15. Próximos seis encargos autosuficientes

1. **D04 resto**. HEAD actual `3e9072b`; cambiar sólo los tres tests de §1, manteniendo cinco fixes del commit. Reproducir fallos antes, actualizar literales/assert de implementación actual, ejecutar tres focales, analyzer y full suite. No producción. PASS = 0 errors/warnings y suite verde; si otro test falla, clasificar.
2. **D01 diagnóstico**. Leer §2 y código citado; identificar Moto/build y obtener reason tipado/runtime/selection/checkpoints/issues sin borrar datos. Comparar scope y dataset `cash_pos/cash_movements`; reproducir en test. No fix inicial ni recovery manual. PASS = causa demostrada; si no hay acceso read-only, declarar UNKNOWN.
3. **D05 paridad**. Con CLI 2.118.0 cacheada ejecutar `migration list --linked` read-only; si falla, Dashboard SQL de §3. Comparar S1A/C4A1/event time/report RPCs y ACL; registrar fecha/proyecto. No deploy. PASS = migrations/contratos exactos o discrepancia listada.
4. **D03 backup/restore**. Obtener autorización de extracción y restore local aislado. Export `public` fuera del repo, hash/cifrado, identificar cobertura Auth/Storage/plan, restaurar en `pilot_restore_probe` sin tocar Hosted, comparar conteos/funciones. PASS = ensayo documentado y límites explícitos; no declarar completo si sólo public.
5. **D02 aceptación APK**. Usuario instala manualmente archivo/hash de baseline en device limpio/release-compatible; matriz §5, incluyendo offline con caja cerrada. No transacciones ficticias ni wipe. PASS = todos los pasos críticos sin STOP y paridad stock/cash/outbox.
6. **D10/D12 operación**. Una tienda/device, checklist de 5 minutos §6; registrar pending/partial/issue al inicio y cierre, aplicar matriz §7 a incidentes con tests de interrupción. Nunca editar outbox o Hosted manualmente. PASS = operación explicable, retries sin doble efecto y protocolo de escalado.

## Unknowns que bloquean afirmaciones fuertes

Estado Drift/SharedPreferences/auth real del Moto; reason exacto de offline blocker; historial/ACL efectivo Hosted hoy; plan Supabase y capacidad de restore de Auth/Storage; restore de ensayo; firma verificada nuevamente del APK; ancho seguro de tablet; provenance individual de costos históricos; capability definitiva del reporte Compras y política Export; estado de tres tests D04 tras futuros cambios. No presentar un piloto como aceptado mientras D01–D05 no tengan evidencia.
