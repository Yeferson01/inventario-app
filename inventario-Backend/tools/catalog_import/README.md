# P1.2 — Herramientas del catálogo maestro

Este directorio contiene el contrato local y versionado para curar el catálogo
maestro de CronosManagement antes de cualquier importación. El programa usa
exclusivamente la biblioteca estándar de Python, no abre conexiones de red y no
lee ni escribe Supabase.

## Estructura

- `catalog_tool.py`: asignación explícita de UUID, validación y `dry-run`.
- `config/vocabularies.json`: vocabularios controlados y su configuración.
- `datasets/catalog_dataset_manifest.json`: versión y metadata del lote.
- `datasets/master_catalog_seed.csv`: dataset activo de masters comerciales.
- `datasets/master_catalog_barcodes.csv`: dataset activo de códigos primarios y alternos.
- `tests/fixtures/`: datos ficticios aislados para las pruebas.
- `reports/`: reportes locales. Los comandos de poda conservan allí sus filas
  rechazadas por defecto; los reportes JSON siguen siendo opcionales mediante
  `--report`.

Los CSV de `datasets/` son las plantillas comerciales reales. No copie en ellos
las filas de `tests/fixtures/`.

## Requisitos

Python 3.12 o compatible. No hay paquetes que instalar. Desde este directorio:

```powershell
python catalog_tool.py validate
python catalog_tool.py dry-run --report reports/catalog-dry-run.json
python catalog_tool.py allocate-ids
python catalog_tool.py sync-primary-barcodes --dry-run
python catalog_tool.py prune-invalid-barcode-masters --dry-run
python catalog_tool.py prune-exact-semantic-duplicates --help
python catalog_tool.py prune-preflight-blockers --help
```

Si `python` no está en `PATH`, invoque el ejecutable Python disponible en la
máquina seguido de los mismos argumentos.

## Flujo de curación

1. Duplique el dataset en un respaldo privado externo si ya contiene trabajo real.
2. Agregue filas a ambos CSV conservando exactamente sus headers.
3. Para filas nuevas puede dejar vacíos únicamente los UUID que va a asignar.
4. Ejecute `allocate-ids` una vez cuando existan UUID vacíos. Esta operación
   modifica los dos CSV; los comandos explícitos de materialización y poda
   descritos abajo también pueden modificarlos bajo sus propias guardas.
5. Verifique que cada barcode quedó enlazado al `master_product_id` correcto.
6. Ejecute `validate` durante la edición y `dry-run` antes de entregar el lote.
7. Corrija manualmente los errores; el validador nunca reescribe datos.

`allocate-ids` llena solo `master_product_id` y `barcode_id` vacíos. Conserva
los UUID existentes. También puede enlazar un barcode sin master cuando su
código coincide con un único `primary_barcode` del seed; una coincidencia
ambigua queda sin enlazar y fallará la validación posterior.

## Materialización masiva de barcodes primarios

Cuando el seed ya tiene `master_product_id` y `primary_barcode`, pero faltan
las filas relacionales, ejecute primero:

```powershell
python catalog_tool.py sync-primary-barcodes --dry-run `
  --report reports/primary-barcode-sync-dry-run.json
```

El dry-run no modifica archivos. Reporta relaciones correctas, inserts,
promociones inequívocas y conflictos por colisión cross-master, múltiples
primarios, primario contradictorio o alias ambiguo.

Si `can_apply=true`, materialice las relaciones con:

```powershell
python catalog_tool.py sync-primary-barcodes `
  --report reports/primary-barcode-sync-apply.json
```

El comando escribe únicamente `master_catalog_barcodes.csv`. Las filas nuevas
reciben un `barcode_id` UUID y copian `master_product_id`, barcode, tipo,
fuente, confianza y referencia desde el seed validado. Un alias solo se
promueve cuando es la única relación posible y conserva su ID y procedencia.

Antes del reemplazo se valida el resultado completo y se crea un backup fuera
del repositorio, bajo el directorio temporal del sistema
`CronosManagement/catalog_import_backups`. La escritura usa un archivo temporal
y reemplazo atómico. Si hay cualquier conflicto bloqueante, el CSV original no
cambia. Una segunda ejecución sin cambios es un no-op byte-for-byte.

## Retiro de masters con barcode inválido

P1.2.2 retira únicamente las filas que el validator identifica con
`invalid_barcode`. Antes de aplicar, ejecutar:

```powershell
python catalog_tool.py prune-invalid-barcode-masters --dry-run `
  --report reports/invalid-barcode-prune-dry-run.json
```

El comando exige por defecto el conjunto esperado de 56 filas, bloquea si
cualquiera tiene una relación en `master_catalog_barcodes.csv` y nunca modifica
ese CSV relacional. La aplicación conserva las filas completas en
`reports/rejected_invalid_barcode_rows.csv`, crea un backup externo del seed y
reemplaza el seed mediante un temporal validado:

```powershell
python catalog_tool.py prune-invalid-barcode-masters `
  --report reports/invalid-barcode-prune-apply.json
```

Una segunda ejecución valida la auditoría existente y devuelve `NO_OP` sin
reescribir el seed ni el reporte de rechazados.

## Retiro de duplicados semánticos exactos

P1.2.3 toma el conjunto exclusivamente de los candidatos `exact` emitidos por
el validator. Como el reporte enumera pares, el comando los agrupa por la
`semantic_key` ya calculada y genera para cada grupo un SHA-256 determinista.
No recalcula similitud, elige survivor ni toca candidatos `near`.

Después de inspeccionar los conteos reales, deben pasarse explícitamente como
guardas del dry-run y de la aplicación:

```powershell
python catalog_tool.py prune-exact-semantic-duplicates `
  --expected-group-count 56 `
  --expected-master-count 132 `
  --expected-barcode-count 132 `
  --dry-run `
  --report reports/exact-semantic-prune-dry-run.json
```

El comando exige los conteos esperados de grupos, masters y relaciones, además
de una relación primaria correcta por master. Elimina todas las relaciones de
cada master rechazado y conserva las filas completas en
`reports/rejected_exact_semantic_duplicate_masters.csv` y
`reports/rejected_exact_semantic_duplicate_barcodes.csv`. Ambos datasets se
validan juntos antes del reemplazo, reciben backups externos y se restauran si
el segundo reemplazo falla. Un rerun correcto es `NO_OP` byte-for-byte.

## Retiro de blockers del preflight Hosted

Después de generar un plan P1.3 revisado, `prune-preflight-blockers` puede
retirar localmente y sin red únicamente sus acciones `REVIEW` y `CONFLICT`.
El plan sigue siendo la autoridad: el comando no recalcula similitud ni escoge
survivors. Los conteos esperados se pasan como guardas explícitas:

```powershell
python catalog_tool.py prune-preflight-blockers `
  --expected-review-count 206 `
  --expected-conflict-count 1 `
  --dry-run `
  --report reports/preflight-blocker-prune-dry-run.json
```

La aplicación valida el hash del plan, su vínculo con el snapshot y el payload
completo de todos los `INSERT` que permanecerán activos. También exige una única
relación primaria por target y conserva por separado los rechazos semánticos y
los conflictos Hosted. Ambos datasets reciben backups externos antes de su
reemplazo lógico. Un rerun con el mismo plan y snapshot es `NO_OP` byte-for-byte.

## Contrato de los CSV

`master_catalog_seed.csv` tiene una fila por presentación/formulación vendible.
Su `master_product_id` es la identidad estable. El nombre, el barcode y una
imagen no son identidades.

`master_catalog_barcodes.csv` tiene una fila por código. Cada master debe tener
exactamente una fila `is_primary=true` cuyo código y tipo coincidan con
`primary_barcode` y `barcode_type` del seed. Los códigos adicionales usan
`is_primary=false`, conservan su propia procedencia y generan un warning de
revisión física. No cree masters distintos para aliases de la misma presentación.

Los campos obligatorios del master son:

- `master_product_id`, `primary_barcode`, `barcode_type`, `name`;
- `category_name`, `unit_type`, `source`, `verification_status`;
- `confidence_score`, `source_reference`.

`package_size` y `package_unit` aparecen juntos. Presentaciones cuantificables
como bolsa, botella, caja, paquete, lata, frasco, sobre, tubo o rollo requieren
ambos. `package_size` y `confidence_score` son decimales base 10 exactos, nunca
notación científica; confidence debe estar entre 0 y 1 inclusive.

## Barcodes y hojas de cálculo

Los barcodes son texto. Los ceros iniciales son significativos.

En Excel, use **Datos → Desde texto/CSV** y establezca como tipo **Texto** las
columnas `primary_barcode` y `barcode` antes de cargar. No abra el CSV mediante
doble clic si Excel puede inferir números. En Google Sheets, formatee primero
esas columnas como texto sin formato y desactive la conversión automática de
texto a números durante la importación. Antes de guardar, confirme visualmente
los ceros iniciales.

Valores como `7.702511E+12` son rechazados: no intente repararlos sin volver a
consultar la fuente original. Los tipos globales admitidos son `ean8`, `upc`,
`ean13` y `gtin` (GTIN-14), con longitud y dígito de control válidos. `internal`
y `local_sku` no pertenecen al seed global.

## Normalización y duplicados

El preview normaliza texto a Unicode NFC, elimina espacios exteriores y colapsa
espacios internos, conservando tildes, `ñ` y mayúsculas visibles. Los códigos
siguen el contrato backend: trim, uppercase y eliminación de caracteres no
alfanuméricos. El CSV original no cambia durante `validate` o `dry-run`.

Un código normalizado repetido para el mismo master es warning/no-op. El mismo
código en masters distintos es un error bloqueante. Una clave semántica exacta
por nombre, marca, tamaño, unidad y tipo es bloqueante para revisión; una
coincidencia cercana es warning. El programa nunca fusiona registros.

## Vocabularios

Los valores permitidos se encuentran únicamente en
`config/vocabularies.json`. Para ampliar una categoría, unidad, fuente o
licencia, modifique ese archivo mediante una revisión controlada y actualice los
tests pertinentes. No invente un valor directamente en el CSV.

`verification_status` refleja exactamente el `CHECK` vigente del backend:
`unverified`, `community`, `verified`, `gs1_verified`, `rejected` y
`deprecated`. El lote inicial curado usa `unverified`.

## Procedencia e imágenes

Cada fila requiere `source` y `source_reference`. La referencia debe permitir a
otro curador localizar la evidencia (documento del fabricante/proveedor,
dataset abierto, ticket de contribución o registro de curación). No incluya
tokens, claves, secretos ni URLs con credenciales.

Si `image_source_key` tiene valor, `image_license` es obligatoria. Las licencias
que exigen atribución también requieren `image_attribution`. El script comprueba
que la documentación exista, pero no emite una conclusión jurídica sobre ella.

El reporte calcula un SHA-256 estable por fila desde su representación
normalizada. No agregue ese hash al CSV: en P1.3 servirá para decidir
no-op/update y para metadata del lote.

## Datos prohibidos

Este catálogo no contiene precios, stock, `stock_quantity`, `minimum_stock`,
business, branch, supplier ni ninguna configuración operacional. Tampoco puede
contener API keys, JWT o secretos. Esos datos pertenecen a otros contratos.

## Reportes y exit codes

`validate` produce un informe humano. `dry-run` produce el mismo resumen y un
JSON determinista cuando se pasa `--report`; sin `--report`, el JSON va a stdout
y el resumen humano a stderr. El JSON incluye versión, conteos, errores,
warnings, conflictos, candidatos semánticos, preview normalizado, hashes y
estado de procedencia de imágenes.

- exit `0`: no hay errores bloqueantes; puede haber warnings para revisión.
- exit `1`: dataset inválido con al menos un error bloqueante.
- exit `2`: uso, configuración, JSON/CSV ilegible o fallo de I/O.

Revise siempre los warnings antes de aprobar un lote, aunque no cambien el exit
code.

## De P1.2 a P1.3

P1.2 prepara y valida archivos locales; no genera filas SQL ni consulta Hosted.
P1.3 agrega `catalog_importer.py`, que mantiene separados snapshot, plan,
aplicación y verificación.

### Snapshot administrativo read-only

Configure las credenciales únicamente como variables de entorno locales:

```powershell
$env:SUPABASE_URL = "https://PROJECT.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY = "<secret local no versionado>"
python catalog_importer.py snapshot --output reports/existing_catalog_snapshot.json
```

El comando invoca solo `export_master_catalog_snapshot`. No incluya la service
key en argumentos, archivos, reportes o historial del shell. El snapshot
contiene masters y códigos globales, incluyendo tombstones y versiones; debe
tratarse como información administrativa.

### Plan determinista

Asigne fuera del script un UUID estable para esa ejecución y consérvelo:

```powershell
python catalog_importer.py plan `
  --against reports/existing_catalog_snapshot.json `
  --import-batch-id 33333333-3333-4333-8333-333333333333 `
  --output reports/import-plan.json
```

El plan clasifica cada fila como `INSERT`, `UPDATE`, `NO_OP`, `CONFLICT` o
`REVIEW`. Un tombstone, cambio de primary no explícito, candidato semántico o
conflicto bloquea `ready_to_apply`. Los updates incluyen la `expected_version`
del snapshot; el servidor vuelve a validarla bajo lock. El plan y su SHA-256 son
deterministas cuando dataset, snapshot e `import_batch_id` no cambian.

### Preparación chunked y reanudable

El RPC limita cada request a 100 masters y 500 barcodes. Por eso un plan
comercial se divide antes de cualquier escritura, conservando cada master y
todos sus códigos en el mismo chunk. Prepare el manifiesto durable y revíselo:

```powershell
python catalog_importer.py prepare-apply `
  --plan reports/import-plan.json `
  --against reports/existing_catalog_snapshot.json `
  --output reports/commercial-import-execution.json
```

El `import_batch_id` del plan identifica el lote lógico raíz y no se envía
repetidamente al RPC. Cada chunk recibe un `child_import_batch_id` UUIDv5
determinista, derivado del root batch, el hash del plan, el índice y el hash de
su payload. El manifiesto liga root batch, versión y hashes del dataset,
snapshot, plan, contrato de chunking, IDs y payloads. Un rerun idéntico verifica
el archivo existente sin sobrescribirlo; cualquier binding stale falla cerrado.

El manifiesto se reemplaza atómicamente al cambiar de `pending` a `in_flight`,
`failed` o `completed`. Si el RPC tuvo éxito y el proceso murió antes de guardar
el resultado, el retry reenvía exactamente el mismo child ID y payload; la
idempotencia server-side devuelve el resultado autoritativo y permite continuar.
El primer error no resuelto detiene los chunks posteriores.
Antes del primer `apply` se debe refrescar snapshot y plan, y volver a verificar
el manifiesto. Para reanudar el mismo root import parcialmente aplicado se
conservan los artefactos exactos ya ligados; no se inicia otro lote lógico.

### Aplicación y verificación

La escritura real queda reservada para P1.4 y exige confirmación explícita del
batch ID:

```powershell
python catalog_importer.py apply `
  --plan reports/import-plan.json `
  --against reports/existing_catalog_snapshot.json `
  --execution-manifest reports/commercial-import-execution.json `
  --confirm-import-batch-id 33333333-3333-4333-8333-333333333333 `
  --output reports/import-result.json

python catalog_importer.py snapshot --output reports/post-import-snapshot.json
python catalog_importer.py verify `
  --plan reports/import-plan.json `
  --against reports/post-import-snapshot.json `
  --output reports/post-import-verification.json
```

`apply` revalida dataset, snapshot, plan y manifiesto, y llama exclusivamente a
`import_master_catalog_batch` para cada chunk pendiente. Cada llamada es una
transacción independiente: la ejecución global es chunk-atomic, reanudable e
idempotente, no una única transacción PostgreSQL para todo el catálogo. El mismo
child batch/request devuelve `already_applied`; reutilizar el child ID con otro
request falla. Antes de marcar un chunk como completo, el executor valida el
child ID, dataset, status, `request_hash` autoritativo y los tres conteos remotos
obligatorios (`inserted`, `updated`, `no_op`) contra las operaciones del plan.
Esto también aplica a `already_applied`. Un nuevo batch con el mismo payload
produce no-op sin incrementar versiones.

La compensación administrativa se realiza únicamente mediante
`compensate_master_catalog_import_batch(batch_id, reason)`. Solo admite batches
insert-only cuyas entidades no tengan dependencias ni cambios posteriores, y
usa soft delete. Los updates requieren restauración manual basada en el audit
pre-update; nunca se hace rollback destructivo o hard delete.
No hay compensación global automática para una ejecución parcialmente
completada: primero se reanuda; cualquier compensación requiere autorización
administrativa separada.

P1.3 no importa automáticamente el CSV ni genera SQL ad-hoc. No ejecute
`apply` con el dataset comercial hasta la autorización y el preflight P1.4.
