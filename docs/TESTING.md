# Estrategia práctica de validación

Este documento define una validación proporcional y reportable para
CronosManagement. Describe pruebas presentes y comprobaciones recomendadas; no
afirma que toda la suite funcione en cualquier máquina o dispositivo.

## Filosofía

- Una modificación no queda validada solo porque compile, porque una herramienta
  la haya editado o porque una prueba aislada pase.
- El resultado debe clasificarse como **fallo real de código**, **fallo de test**,
  **fallo de tooling/entorno** o **prueba no ejecutada**.
- La profundidad de validación debe ser proporcional al riesgo: documentación,
  UI, reglas de negocio, SQL local, esquema Drift, sync y migraciones backend no
  requieren exactamente las mismas comprobaciones.
- Siempre se revisa el diff completo además de ejecutar comandos.
- No se afirma una validación que no pudo ejecutarse.

## Entorno

El frontend Flutter está en `inventario-Frontend/`. La ejecución operacional
principal se realiza en Android/dispositivo. La base de aplicación importa
`dart:io`, `drift/native.dart` y `path_provider`, por lo que Chrome no es un
destino válido para comprobar los flujos Drift/native que dependen de
SQLite/FFI.

La configuración real se carga mediante dart defines. `AppConfig` exige
`SUPABASE_URL` y `SUPABASE_ANON_KEY` y muestra como formas admitidas:

```powershell
flutter run -d <device> --dart-define-from-file=config/dev.json
flutter run -d <device> --dart-define-from-file=config/prod.json
```

Para desarrollo debe preferirse `config/dev.json`. `<device>` se resuelve en el
entorno con `flutter devices`; no existe un ID fijo universal que deba copiarse
a la documentación.

Los tests unitarios que usan `NativeDatabase.memory()` no necesitan escribir la
base operacional del dispositivo, pero siguen dependiendo del tooling Flutter
y de las bibliotecas nativas disponibles en el entorno de test.

## Validación mínima de un cambio Dart

Desde `inventario-Frontend/`:

1. Formatear solo los archivos Dart modificados:

   ```powershell
   dart format <archivos-dart-modificados>
   ```

2. Ejecutar análisis estático:

   ```powershell
   flutter analyze
   ```

3. Ejecutar los tests relevantes, por archivo o directorio:

   ```powershell
   flutter test test/<ruta-relevante>_test.dart
   ```

4. Intentar la suite completa cuando sea razonable y el entorno lo permita:

   ```powershell
   flutter test
   ```

5. Desde la raíz del repositorio, comprobar whitespace y revisar el diff:

   ```powershell
   git diff --check
   git diff
   ```

Si la suite completa no puede ejecutarse, se documentan los tests focalizados
que sí pasaron y el alcance que quedó sin validar.

## Tests actuales

El baseline contiene 36 archivos bajo `inventario-Frontend/test/`, agrupables
así:

- **Database / Drift:** persistencia en memoria y verificación de que la venta
  legacy no modifica `products.stock_quantity`.
- **Guard de `customStatement`:** inspección estática de usos inseguros en
  `lib/core` y `lib/features`.
- **Parámetros SQLite:** normalización de primitives, `Variable`, fechas, JSON y
  bytes.
- **UUID y barcode:** UUID v4/v7, normalización y detección de barcode.
- **Catálogo:** lookup local, modelos locales, requests y responses de pull.
- **Creación de productos de inventario:** modelos y mapeo de mutations al
  outbox.
- **Sync y contexto:** modelos, stores, providers, runtime, selección de
  negocio, permisos y snapshot operacional.
- **Scheduled sync:** política de ventanas/triggers y serialización de modelos.
- **Widgets y gates:** shell, contexto, permisos, lifecycle y pantallas E2E;
  varios son tests de existencia de clase, no pruebas funcionales completas.
- **Smoke test:** construcción básica de `MyApp`.

La existencia de estas áreas no implica cobertura integral de POS, caja,
compras, inventario o backend.

## SQL raw y `customStatement`

Existe `test/core/database/custom_statement_guard_test.dart`. El guard recorre
los bloques `customStatement(...)` de `lib/core` y `lib/features` y rechaza:

- `Variable<T>`;
- `Variable(...)`;
- `DateTime.now()` pasado dentro del bloque.

El motivo del test indica que `customStatement` debe recibir valores SQLite raw
o parámetros normalizados, no wrappers Drift. Cuando se use SQL raw:

- reutilizar `normalizeSqliteParameter` o `normalizeSqliteParameters` de
  `lib/core/database/utils/sqlite_parameter_utils.dart`;
- no introducir `Variable<T>` dentro de un `customStatement`;
- pasar fechas como el valor UTC ISO producido por el helper;
- conservar listas de bytes y serializar mapas/listas no binarias mediante el
  helper existente;
- ejecutar tanto el guard como `sqlite_parameter_utils_test.dart`.

`customSelect` tiene una API distinta y sí usa `Variable` en el código actual;
la prohibición descrita por este guard se limita a los bloques
`customStatement` que inspecciona.

## Cambios de Drift

Si un cambio autorizado modifica tablas o columnas:

1. revisar e incrementar `schemaVersion` cuando el cambio de esquema lo
   requiera;
2. implementar la ruta correspondiente en `MigrationStrategy`, incluyendo
   creación/upgrade e índices aplicables;
3. regenerar Drift desde `inventario-Frontend/`, por ejemplo:

   ```powershell
   dart run build_runner build
   ```

4. no editar `app_database.g.dart` manualmente;
5. ejecutar tests database, el guard de SQL y análisis estático;
6. probar creación limpia y upgrade desde las versiones relevantes cuando el
   riesgo de migración lo exija.

No todo cambio en un DAO o servicio modifica tablas; en esos casos no se
incrementa `schemaVersion` ni se regenera por rutina.

## Validación de sync

Para cualquier dominio de sync, comprobar como mínimo:

- payload y contexto `business`/`branch` correctos;
- client batch ID, client mutation ID y client sequence estables;
- idempotency key consistente con la operación lógica;
- retry sin crear duplicados;
- transición de batch y mutations por `pending`, `uploading` y el resultado
  aplicable (`completed`, `partial`, `error` o conflict);
- errores y retry count conservados;
- reconciliación del estado local tras respuesta/pull;
- ausencia de duplicación remota al repetir el upload.

Después se aplican reglas específicas de `catalog`, `pos`, `purchases`, `cash`
o `inventory`. No se asume que todos los dominios tengan idéntica
reconciliación.

## Validaciones funcionales manuales recomendadas

Estas listas son escenarios manuales; no describen tests automatizados ya
existentes.

### POS

- crear una venta local con caja válida;
- verificar ítems, pagos, movement negativo y saldo local resultante;
- encolar y subir POS;
- reconciliar el saldo remoto/local;
- repetir el sync y verificar que no duplica venta ni inventario.

### Compras

- crear compra e ítems localmente;
- verificar movement positivo y aumento del saldo local;
- si se creó un producto rápido, subir/reparar catálogo antes de la compra;
- subir y comprobar `purchase_items` e impacto remoto de inventario;
- ejecutar un segundo sync y comprobar idempotencia, incluida la ruta
  `completed_remote_already_exists` cuando corresponda.

### Caja

- abrir una cash session local;
- encolar y sincronizar apertura/caja;
- vender dentro de esa sesión;
- ejecutar el cierre visible en orden cash → POS → cierre local → cash;
- comprobar montos, diferencia, asociación de ventas y cierre remoto.

### Inventario

- registrar saldo antes y después de la operación;
- comprobar tipo, signo, origen, referencia e idempotency key del movement;
- verificar `quantity_on_hand`, reserved/available cuando aplique y sucursal;
- comprobar que la operación se rechace si producir stock negativo está
  prohibido por la regla específica;
- verificar que `products.stock_quantity` no se use como saldo operacional.

## Backend y migraciones Supabase

`inventario-Backend/` contiene scripts Node manuales para conexión y flujos de
venta, compra, inventario y productos. `package.json` no define una suite
profesional: su script `test` termina con “no test specified”. Esos scripts son
diagnóstico manual y deben reportarse como tal.

Para una migración Supabase:

- revisar el diff SQL completo y dependencias con migraciones anteriores;
- verificar la lista y orden de migraciones;
- ejecutar primero en Supabase local o en un entorno seguro cuando corresponda;
- validar RLS/policies, permisos, idempotencia y efectos de datos;
- conservar las migraciones locales como fuente versionada y seguir las
  prácticas de backup del proyecto;
- no asumir que el plan Free proporciona un backup administrado recuperable.

Una migración presente en el repositorio no demuestra que haya sido aplicada ni
probada en una instancia concreta.

### Issue conocido: denegación de funciones en Supabase local

En el stack local usado durante ORG-1B.1, PostgreSQL 17.6 con la imagen Supabase
PostgreSQL 17.6.1.111 puede terminar el proceso con `SIGSEGV` cuando `anon` o
`authenticated` invocan una función para la que no tienen `EXECUTE`. El entorno
afectado usa Supabase CLI 2.115.0 y PostgREST 14.5. El repro ocurre incluso con
una función mínima sin `EXECUTE`, antes de ejecutar su cuerpo; la misma función
opera normalmente con `service_role`. `PGRST001` es una consecuencia del crash
y recovery de PostgreSQL, no su causa.

En stacks locales afectados, los tests de denegación deben comprobar
`has_function_privilege(...)=false` y los ACL de `pg_proc.proacl`. Cuando una
Edge Function exponga el RPC, también debe verificarse que rechace al caller no
autorizado antes de invocar la función administrativa. La Edge Function de
ORG-1B ya devuelve 403 para `authenticated` ordinario y Owner antes del RPC.

Esta limitación conocida del entorno local de testing **no justifica conceder
`EXECUTE` a `anon` o `authenticated` ni debilitar ACLs de producción**. Debe
reevaluarse después de actualizar Supabase PostgreSQL/supautils.

## Auth productivo e invitaciones privadas

Las pruebas focales de ORG-1C deben separar sesión Auth de autorización de
Business: sin sesión se espera Login; con sesión se prueban contextos,
invitaciones y ausencia de acceso como resultados distintos. Los callbacks
`cronosmanagement-dev://auth-callback` y
`cronosmanagement://auth-callback` son procesados por `supabase_flutter`; no se
construyen tokens manuales en tests.

Antes de desplegar, Supabase Hosted debe allowlistear el redirect del entorno,
la Edge Function debe configurar `PLATFORM_INVITATION_REDIRECT_URL` con ese
valor exacto y `Allow new users to sign up` debe permanecer **OFF**. Validar en
Android real invitación nueva, usuario existente, recuperación de contraseña y
reinicio con sesión persistida. La falta de red al consultar invitaciones no
debe bloquear un contexto operacional local previamente válido.

## Fallos de entorno

Si Codex o una persona no puede ejecutar una prueba, el reporte debe incluir:

- comando exacto;
- error observado;
- clasificación probable: tooling, SDK, dependencia, dispositivo, path,
  credenciales/configuración o prueba no ejecutable en ese entorno;
- validaciones que sí se completaron;
- alcance que permanece sin validar.

No se modifica código únicamente para silenciar un fallo ambiental. Primero se
separa el defecto reproducible de aplicación/test de la limitación del entorno.

## Matriz de validación

| Tipo de cambio | Mínimo | Recomendado según riesgo |
| --- | --- | --- |
| Solo documentación | `git diff --check`, enlaces/rutas, revisión del diff | Contrastar afirmaciones con código, contratos y estado vigente. |
| Solo UI | `dart format`, `flutter analyze`, tests de widget relevantes, diff | Ejecutar en Android/device y recorrer estados vacío, carga, error y responsive. |
| Application/service | Formato, analyze y tests focalizados de reglas/modelos | Escenario integrado con DAO/datasource falso o entorno controlado. |
| DAO/SQL local | Formato, analyze, database tests, guard `customStatement` | Casos transaccionales, rollback, índices, concurrencia y datos límite. |
| Esquema Drift | Revisión de versión/migración, generación y database tests | Creación limpia, upgrade desde versiones soportadas y prueba en dispositivo. |
| Sync | Tests focalizados, payload/idempotencia/estados/retry | Upload real controlado, repetición sin duplicados y reconciliación/pull. |
| Migración backend | Diff SQL, orden de migración y revisión RLS | Aplicación en Supabase local/seguro, pruebas RPC/policies y plan de recuperación. |
