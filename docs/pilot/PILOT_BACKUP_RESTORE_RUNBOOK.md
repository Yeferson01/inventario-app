# Cronos POS — backup y ensayo de restauración previo al piloto

Este procedimiento usa Supabase CLI 2.118.0 y PostgreSQL local 17.6. Toda
extracción Hosted es de solo lectura. Nunca ejecutar `db push --linked`,
`migration repair`, `db reset --linked` ni restaurar sobre Hosted como parte de
este ensayo. No usar `db dump --dry-run`: puede mostrar credenciales efímeras.

## Alcance y custodia

Los dumps SQL contienen datos empresariales y de Auth, incluidos posibles
refresh tokens y hashes de credenciales. Guardarlos fuera del
repositorio, en un directorio privado cuyo ACL se haya comprobado, y no mostrar
su contenido en consola, logs, Git ni chat. Conservar SHA-256, una copia primaria
y una segunda copia cifrada en otra ubicación segura. No incluir claves `service_role`,
passwords, URLs de conexión ni secretos en el manifest o el runbook.

El backup de los esquemas `public,auth,storage,private,extensions,` y
`supabase_migrations` cubre tablas, funciones, grants explícitos, RLS, usuarios
Auth, metadata de Storage e historial de migraciones que exporta la CLI. **No es
un backup completo del proyecto Supabase**: no cubre configuración de Auth,
secretos/Vault, definiciones de roles del clúster, privilegios globales, PITR ni
binarios de objetos Storage. Los grants/propietarios declarados en el esquema
requieren roles compatibles al restaurar. Confirmar plan Hosted y retención por
separado; no asumir que existen backups gestionados recuperables.

Antes de un deployment: confirmar proyecto/ref y migration pendiente; comprobar
que schema/data existen fuera del repo y sus hashes coinciden con el manifest;
confirmar ACL privado y una segunda copia cifrada cuando esté disponible;
revisar el resultado del restore aislado, conteos, RPCs y límites de
ownership/default privileges; conocer pending work y estado de Caja en cada
dispositivo piloto. Un ensayo exitoso no autoriza por sí mismo el deploy.

## Backup pre-deployment

Desde `inventario-Backend`, confirmar `git status --short`, proyecto linked,
versión CLI y que la migration que se quiere desplegar sigue local-only. Antes
de escribir, verificar que los nombres destino no existan y que el directorio
esté fuera del repositorio, sin reparse point/symlink y con ACL privado.

```powershell
$backupDir = 'C:\RUTA_PRIVADA_EXTERNA\pre-deployment'
npx --no-install supabase --version
npx --no-install supabase migration list --linked
npx --no-install supabase db dump --linked `
  --schema public,auth,storage,private,extensions,supabase_migrations `
  --file (Join-Path $backupDir 'schema-hosted.sql')
npx --no-install supabase db dump --linked `
  --schema public,auth,storage,private,extensions,supabase_migrations `
  --data-only --use-copy --file (Join-Path $backupDir 'data-hosted.sql')
Get-Item -LiteralPath (Join-Path $backupDir 'schema-hosted.sql'),
  (Join-Path $backupDir 'data-hosted.sql') | Select-Object Name,Length,CreationTimeUtc
Get-FileHash -Algorithm SHA256 -LiteralPath `
  (Join-Path $backupDir 'schema-hosted.sql'),
  (Join-Path $backupDir 'data-hosted.sql')
```

Registrar únicamente nombres y hashes en `SHA256SUMS.txt`. Volver a calcularlos
antes y después del ensayo. Comprobar archivos regulares, tamaño mayor que cero,
`CREATE TABLE` en schema y `COPY` en data sin imprimir filas. Un dump de datos
representa un snapshot en el instante de su extracción; no confundir sus conteos
con conteos Hosted obtenidos mucho después.

No usar `--role-only` sin revisar el archivo en un procedimiento privado: puede
contener credenciales/hashes de roles. La omisión de roles debe quedar anotada.

## Restore rehearsal local aislado

No restaurar sobre la base local `postgres` ni sobre Hosted. Confirmar primero
que `pilot_restore_probe` no existe y que no se perderá trabajo local. El
contenedor local ya debe proporcionar los roles de Supabase. En un PostgreSQL
vacío se requieren también las extensiones `pgcrypto` y `uuid-ossp` en el esquema
`extensions` antes de cargar el dump.

```powershell
docker exec supabase_db_inventario-Backend createdb `
  -U postgres -T template1 pilot_restore_probe
docker exec supabase_db_inventario-Backend psql `
  -U postgres -d pilot_restore_probe -v ON_ERROR_STOP=1 `
  -c 'create schema if not exists extensions; create extension if not exists pgcrypto with schema extensions; create extension if not exists "uuid-ossp" with schema extensions;'
```

En el stack local, `postgres` no es superuser ni miembro de todos los roles
Hosted. Por eso el ensayo de esquema puede omitir **solo en el stream de
restauración** las líneas `ALTER ... OWNER TO` y `ALTER DEFAULT PRIVILEGES`;
el backup original y su hash permanecen intactos. Esto prueba tablas, datos,
RLS y grants explícitos, **no** ownership ni privilegios por defecto futuros.
Usar `psql -1 -v ON_ERROR_STOP=1` para que un error revierta ese intento.

```powershell
$schemaPath = Join-Path $backupDir 'schema-hosted.sql'
$schemaLines = [IO.File]::ReadAllLines($schemaPath)
$restoreLines = $schemaLines | Where-Object {
  $_ -notmatch '^ALTER .* OWNER TO ' -and
  $_ -notmatch '^ALTER DEFAULT PRIVILEGES'
}
($restoreLines -join "`n") | docker exec -i supabase_db_inventario-Backend `
  psql -X -q -1 -v ON_ERROR_STOP=1 -U postgres -d pilot_restore_probe
Get-Content -LiteralPath (Join-Path $backupDir 'data-hosted.sql') -Raw |
  docker exec -i supabase_db_inventario-Backend `
  psql -X -q -1 -v ON_ERROR_STOP=1 -U postgres -d pilot_restore_probe
```

Si falla, detenerse, clasificar la causa (dump incompleto, versión/CLI,
ordenamiento, Auth/Storage, roles/grants o incompatibilidad PostgreSQL) y
conservar el dump intacto. No cambiar Hosted para hacer pasar el ensayo. Si se
reintenta, recrear únicamente la base aislada tras verificar su nombre y que no
tenga conexiones ni datos únicos. Eliminarla al finalizar si no se necesita
investigar; conservar los dumps privados.

## Verificación

Comparar `COPY` por tabla del dump con `SELECT count(*)` del restore, al menos
para `businesses`, `branches`, `profiles`, `business_members`, `sync_batches`,
`sync_mutations`, `cash_registers`, `cash_sessions`, `cash_movements`, `sales`,
`sale_items`, `sale_payments`, `purchases`, `purchase_items`,
`inventory_movements`, `product_stock_balances`, `auth.users` y
`supabase_migrations.schema_migrations`. No imprimir filas ni payloads.

Consultar `pg_proc` para el entrypoint sync, registro S1A, los tres reportes,
apertura/cierre de Caja y reconciliación stale; `pg_class.relrowsecurity` y
`pg_policy` para RLS; `has_function_privilege` y `pg_proc.proacl` para grants.
No invocar RPCs mutantes. Registrar explícitamente cualquier owner/default
privilege no restaurado y todo desajuste. En un backup **pre-D05S**, el grant
`anon` de `process_sync_batch` es el estado Hosted esperado del backup, no un
fallo del ensayo; debe desaparecer solo tras el deployment autorizado de D05S.

Ejemplos read-only para la base aislada (repetir en Hosted mediante un canal
autorizado y comparar únicamente los conteos, nunca filas):

```powershell
$db = 'pilot_restore_probe'
docker exec supabase_db_inventario-Backend psql -X -At -U postgres -d $db `
  -c 'select count(*) from public.sales;'
docker exec supabase_db_inventario-Backend psql -X -At -U postgres -d $db `
  -c "select proname,prosecdef from pg_proc join pg_namespace n on n.oid=pronamespace where n.nspname='public' and proname in ('process_sync_batch','get_branch_sales_report_summary','get_branch_profitability_report_summary','get_branch_cash_flow_report_summary','open_or_reuse_cash_session','close_cash_session_authoritatively');"
docker exec supabase_db_inventario-Backend psql -X -At -U postgres -d $db `
  -c "select relname,relrowsecurity from pg_class join pg_namespace n on n.oid=relnamespace where n.nspname='public' and relname in ('sales','sale_items','sale_payments','cash_sessions','inventory_movements','sync_batches','sync_mutations');"
docker exec supabase_db_inventario-Backend psql -X -At -U postgres -d $db `
  -c "select has_function_privilege('anon','public.process_sync_batch(uuid,text)','EXECUTE');"
```

La última consulta solo representa el estado pre-D05S; verificar la firma real
de cada RPC en `pg_proc` antes de adaptar una consulta de grants.

## Datos exclusivos del dispositivo

Un backup Hosted no incluye Drift, outbox/mutaciones pendientes, operaciones
local-only, reconciliation issues/checkpoints, SharedPreferences, runtime,
installation ID ni sesión Auth cacheada. Antes de desinstalar o reemplazar un
dispositivo: comprender estado sync, resolver o documentar cada pending mutation,
revisar blockers y controlar/cerrar la Caja. Nunca usar `pm clear` o uninstall
como sustituto de reconciliación.
