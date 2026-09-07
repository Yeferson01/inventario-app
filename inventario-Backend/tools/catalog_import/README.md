# P1.2 — Herramientas del catálogo maestro

Este directorio contiene el contrato local y versionado para curar el catálogo
maestro de CronosManagement antes de cualquier importación. El programa usa
exclusivamente la biblioteca estándar de Python, no abre conexiones de red y no
lee ni escribe Supabase.

## Estructura

- `catalog_tool.py`: asignación explícita de UUID, validación y `dry-run`.
- `config/vocabularies.json`: vocabularios controlados y su configuración.
- `datasets/catalog_dataset_manifest.json`: versión y metadata del lote.
- `datasets/master_catalog_seed.csv`: masters comerciales; empieza solo con el header.
- `datasets/master_catalog_barcodes.csv`: códigos primarios y alternos; empieza solo con el header.
- `tests/fixtures/`: datos ficticios aislados para las pruebas.
- `reports/`: destino opcional para reportes locales; el programa no escribe allí por defecto.

Los CSV de `datasets/` son las plantillas comerciales reales. No copie en ellos
las filas de `tests/fixtures/`.

## Requisitos

Python 3.12 o compatible. No hay paquetes que instalar. Desde este directorio:

```powershell
python catalog_tool.py validate
python catalog_tool.py dry-run --report reports/catalog-dry-run.json
python catalog_tool.py allocate-ids
```

Si `python` no está en `PATH`, invoque el ejecutable Python disponible en la
máquina seguido de los mismos argumentos.

## Flujo de curación

1. Duplique el dataset en un respaldo privado externo si ya contiene trabajo real.
2. Agregue filas a ambos CSV conservando exactamente sus headers.
3. Para filas nuevas puede dejar vacíos únicamente los UUID que va a asignar.
4. Ejecute `allocate-ids` una vez. Esta es la única operación que modifica CSV.
5. Verifique que cada barcode quedó enlazado al `master_product_id` correcto.
6. Ejecute `validate` durante la edición y `dry-run` antes de entregar el lote.
7. Corrija manualmente los errores; el validador nunca reescribe datos.

`allocate-ids` llena solo `master_product_id` y `barcode_id` vacíos. Conserva
los UUID existentes. También puede enlazar un barcode sin master cuando su
código coincide con un único `primary_barcode` del seed; una coincidencia
ambigua queda sin enlazar y fallará la validación posterior.

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
La interfaz prevista para P1.3 es un argumento local como
`--against existing_catalog_snapshot.json`: comparará identidades, códigos y
hashes contra un snapshot exportado, nunca contra una conexión live implícita.
Su implementación y el dry-run remoto se reservan para el preflight P1.3. Hasta
entonces, no use estas herramientas para importar, actualizar o borrar datos de
Supabase.
