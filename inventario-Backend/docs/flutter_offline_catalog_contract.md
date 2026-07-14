\# Contrato Flutter Offline-First — Catálogo Local de Productos



\## 1. Objetivo



El catálogo local permite que la app Flutter pueda escanear productos sin depender de internet en cada lectura.



La app debe poder:



\- Buscar productos por código de barras localmente.

\- Sugerir datos desde catálogo maestro.

\- Crear productos locales desde catálogo global.

\- Registrar códigos locales del negocio.

\- Enviar contribuciones para mejorar el catálogo global.

\- Descargar cambios del catálogo 1 o 2 veces al día.

\- No descargar imágenes pesadas durante el sync principal.



Este contrato complementa:



\- `docs/sync\_contract\_flutter\_offline\_first.md`

\- Backend Fase 6.19C — Catálogo offline-first completo.



\---



\## 2. Principio principal



La app NO debe consultar Supabase por cada escaneo.



Flujo correcto:



1\. Usuario escanea código.

2\. Flutter normaliza el código.

3\. Flutter busca en SQLite/Drift local.

4\. Si existe producto local, lo usa.

5\. Si no existe producto local pero existe master product global, propone crear producto local.

6\. Si no existe nada, permite crear producto manual.

7\. Opcionalmente, luego envía una contribución al catálogo.



La RPC `lookup\_product\_by\_barcode` es solo para soporte, refresh o casos puntuales.



\---



\## 3. Normalización de códigos



Flutter debe normalizar códigos igual que backend:



Backend usa:



```sql

private.normalize\_barcode(text)



Regla equivalente en Dart:



String normalizeBarcode(String input) {

&#x20; return input.trim().toUpperCase().replaceAll(RegExp(r'\[^A-Z0-9]'), '');

}



Ejemplos:



" local - 123 " -> "LOCAL123"

"770 619 1234567" -> "7706191234567"

"abc-001" -> "ABC001"

4\. Tablas locales recomendadas en SQLite/Drift

4.1 local\_master\_products\_catalog



Representa productos globales del catálogo maestro.



Campos mínimos:



id TEXT PRIMARY KEY

barcode TEXT

gtin TEXT

barcode\_normalized TEXT



name TEXT

product\_name TEXT

normalized\_name TEXT



brand TEXT

manufacturer TEXT

category\_name TEXT

subcategory\_name TEXT



package\_size REAL

package\_unit TEXT

unit\_type TEXT



has\_image INTEGER

image\_thumb\_url TEXT

image\_hash TEXT



source TEXT

verification\_status TEXT

confidence\_score REAL

catalog\_version INTEGER



sync\_status TEXT

version INTEGER

updated\_at TEXT

deleted\_at TEXT



last\_synced\_at TEXT



Índices locales recomendados:



barcode\_normalized

normalized\_name

brand

category\_name

updated\_at

catalog\_version

4.2 local\_product\_barcodes



Representa códigos globales y códigos locales del negocio.



Campos mínimos:



id TEXT PRIMARY KEY



scope TEXT

business\_id TEXT

product\_id TEXT

master\_product\_id TEXT



barcode TEXT

barcode\_normalized TEXT

barcode\_type TEXT



is\_primary INTEGER

status TEXT

source TEXT

confidence\_score REAL



sync\_status TEXT

version INTEGER

updated\_at TEXT

deleted\_at TEXT



last\_synced\_at TEXT



Índices locales recomendados:



barcode\_normalized

scope

business\_id

product\_id

master\_product\_id

status

updated\_at



Reglas:



scope = global:

&#x20; business\_id = null

&#x20; product\_id = null

&#x20; master\_product\_id requerido



scope = business:

&#x20; business\_id requerido

&#x20; product\_id requerido

&#x20; master\_product\_id opcional

4.3 local\_catalog\_sync\_state



Controla estado de descarga del catálogo.



Campos sugeridos:



id TEXT PRIMARY KEY

business\_id TEXT NOT NULL



last\_catalog\_pull\_at TEXT

last\_server\_time TEXT

last\_since\_updated\_at TEXT

last\_catalog\_version INTEGER



last\_page\_token TEXT

is\_syncing INTEGER

last\_error TEXT



created\_at TEXT

updated\_at TEXT



Uso:



Guardar último server\_time devuelto por backend.

En el siguiente pull usar ese tiempo como p\_since\_updated\_at.

Si hubo paginación incompleta, guardar next\_page\_token.

Si has\_more = true, continuar antes de avanzar el cursor local.

4.4 local\_catalog\_contribution\_queue



Cola local para contribuciones generadas offline.



Campos sugeridos:



id TEXT PRIMARY KEY

business\_id TEXT NOT NULL

branch\_id TEXT



local\_product\_id TEXT

master\_product\_id TEXT



contribution\_type TEXT

barcode TEXT

barcode\_normalized TEXT

barcode\_type TEXT



suggested\_name TEXT

suggested\_brand TEXT

suggested\_manufacturer TEXT

suggested\_category\_name TEXT

suggested\_subcategory\_name TEXT

suggested\_package\_size REAL

suggested\_package\_unit TEXT

suggested\_unit\_type TEXT



suggested\_image\_url TEXT

suggested\_image\_thumb\_url TEXT

suggested\_image\_hash TEXT



source TEXT

confidence\_score REAL

metadata\_json TEXT



local\_status TEXT

server\_contribution\_id TEXT

retry\_count INTEGER

last\_error TEXT



created\_at TEXT

updated\_at TEXT

synced\_at TEXT



Estados locales:



pending

syncing

synced

error

discarded



5\. Pull del catálogo desde Supabase



RPC principal:



public.pull\_product\_catalog\_delta(

&#x20; p\_business\_id uuid,

&#x20; p\_since\_updated\_at timestamptz default null,

&#x20; p\_limit integer default 1000,

&#x20; p\_page\_token jsonb default '{}',

&#x20; p\_include\_deleted boolean default false

)



Uso recomendado:



Bootstrap inicial



Cuando el negocio inicia por primera vez en el dispositivo:



p\_since\_updated\_at = null

p\_limit = 1000 o 2000

p\_page\_token = {}

p\_include\_deleted = false



Repetir mientras:



has\_more = true

Sync diario



1 o 2 veces al día:



p\_since\_updated\_at = local\_catalog\_sync\_state.last\_server\_time

p\_limit = 1000 o 2000

p\_page\_token = {}

p\_include\_deleted = true si se quieren procesar soft deletes

6\. Orden correcto para aplicar records localmente



La RPC devuelve records mezclados:



master\_product

global\_barcode

business\_barcode



Flutter debe aplicarlos en este orden:



1\. master\_product

2\. global\_barcode

3\. business\_barcode



Motivo:



global\_barcode.master\_product\_id puede apuntar a master product.

business\_barcode.master\_product\_id puede apuntar a master product.

business\_barcode.product\_id apunta a producto local.



Regla práctica:



Primero guardar todos los records en memoria.

Luego separar por entity\_type.

Después hacer upsert en orden.

7\. Manejo de imágenes



El sync principal del catálogo NO debe descargar imágenes pesadas.



La RPC solo devuelve:



has\_image

image\_thumb\_url

image\_hash



No debe devolver:



image\_url pesado



Flutter debe:



Mostrar placeholder.

Usar image\_thumb\_url solo en detalle/listados importantes.

Descargar thumbnail lazy.

Guardar en caché local por image\_hash.

Si cambia image\_hash, invalidar caché.

No bloquear ventas por imágenes.

8\. Búsqueda local por escaneo



Cuando el usuario escanea:



Paso 1 — Normalizar

final normalized = normalizeBarcode(scannedValue);

Paso 2 — Buscar código local del negocio



Buscar en local\_product\_barcodes:



scope = business

business\_id = currentBusinessId

barcode\_normalized = normalized

status = active

deleted\_at is null



Si encuentra:



Usar product\_id.

Abrir producto local.

Agregar a venta/inventario.

Paso 3 — Buscar código global



Si no encontró código local:



scope = global

barcode\_normalized = normalized

status = active

deleted\_at is null



Si encuentra:



Buscar master\_product\_id en local\_master\_products\_catalog.

Proponer crear producto local desde master product.

Paso 4 — Crear producto manual



Si no encuentra nada:



Mostrar formulario de creación manual.

Guardar producto local.

Crear contribución pendiente si el usuario acepta compartir datos.

9\. RPC lookup puntual



RPC:



public.lookup\_product\_by\_barcode(

&#x20; p\_business\_id uuid,

&#x20; p\_barcode text

)



Uso permitido:



✅ soporte

✅ refresh manual

✅ caso excepcional cuando el catálogo local está vacío

✅ fallback controlado si el usuario tiene internet



Uso NO recomendado:



❌ cada escaneo

❌ cada búsqueda en pantalla

❌ cada agregado a venta

10\. Crear producto local desde master product



Cuando match\_type = global o cuando el catálogo local encuentra un master product global, Flutter debe crear un producto local con:



business\_id = currentBusinessId

branch\_id opcional según diseño

master\_product\_id = master.id



name = master.name

barcode = master.barcode o código escaneado

category sugerida = master.category\_name

brand = master.brand

unit\_type = master.unit\_type

package\_size = master.package\_size

package\_unit = master.package\_unit



stock inicial = 0

precio venta = requerido por usuario

costo = opcional

sync\_status = pending

local\_status = dirty



Importante:



El producto local pertenece al negocio.

El master product global no se modifica desde Flutter directamente.

11\. Códigos locales del negocio



Un negocio puede crear códigos internos/locales.



Ejemplos:



SKU-001

LOCAL-COCA-400

CODIGO-MANUAL-123



Deben guardarse como:



scope = business

business\_id = currentBusinessId

product\_id = localProductId

barcode\_type = local\_sku o internal

barcode\_normalized = normalizeBarcode(barcode)



Estos códigos son válidos para todas las sucursales del negocio.



12\. Contribuciones al catálogo



RPC:



public.submit\_product\_catalog\_contribution(...)



Uso:



Cuando el usuario crea un producto no encontrado.

Cuando corrige nombre/marca/categoría.

Cuando agrega presentación/tamaño.

Cuando sugiere imagen.

Cuando detecta alias de código.



Regla:



Las contribuciones NO modifican el catálogo maestro directamente.

Quedan en pending\_review.



Estados backend:



pending\_review

accepted

rejected

merged

duplicate

ignored



Estados locales recomendados:



pending

syncing

synced

error

discarded

13\. Review de contribuciones



RPC backend:



public.review\_product\_catalog\_contribution(...)



Acciones soportadas:



accept\_new\_product

accept\_improvement

reject

duplicate

ignore



Esta RPC es para admin/revisión, no para tendero común.



Flujo:



tendero sugiere

→ contribución pending\_review

→ admin/proceso revisa

→ accepted / merged / rejected / duplicate / ignored

14\. Sync recomendado diario



Al iniciar app con internet:



1\. register\_or\_update\_app\_device

2\. ensure\_business\_runtime\_setup

3\. pull\_sync\_changes\_v2 para datos operativos

4\. pull\_product\_catalog\_delta para catálogo maestro/barcodes

5\. procesar colas locales pendientes



Durante el día:



\- ventas offline

\- compras offline

\- productos locales offline

\- contribuciones offline

\- búsqueda de barcode local



Al recuperar internet:



1\. subir sync\_batches normales

2\. aplicar inventario POS/compras

3\. subir contribuciones pendientes

4\. pull\_product\_catalog\_delta

5\. actualizar caché local

15\. Reglas de rendimiento



Para negocios pequeños/medianos:



p\_limit = 1000



Para catálogos grandes:



p\_limit = 2000 a 5000



Flutter debe paginar hasta:



has\_more = false



Nunca asumir que una sola llamada trae todo.



16\. Reglas de seguridad



Flutter nunca debe:



❌ modificar master\_products\_catalog directamente

❌ modificar product\_barcodes globales directamente

❌ confiar en datos de usuario como catálogo global verificado

❌ borrar físicamente productos/códigos/contribuciones



Flutter sí puede:



✅ crear productos locales

✅ crear códigos locales del negocio

✅ enviar contribuciones

✅ guardar catálogo global localmente

✅ usar master\_product\_id como referencia

17\. Reglas para SQLite/Drift



Todas las tablas locales sincronizables deben tener:



id

created\_at

updated\_at

deleted\_at

sync\_status

local\_status

version

last\_synced\_at

metadata\_json



Estados local\_status sugeridos:



clean

dirty

pending\_upload

syncing

conflict

error

deleted\_pending\_sync

18\. Checklist Flutter para catálogo



Antes de considerar terminado el módulo Flutter de catálogo:



\[ ] Existe tabla local\_master\_products\_catalog.

\[ ] Existe tabla local\_product\_barcodes.

\[ ] Existe tabla local\_catalog\_sync\_state.

\[ ] Existe tabla local\_catalog\_contribution\_queue.

\[ ] Existe normalizeBarcode() compatible con backend.

\[ ] El escaneo busca primero código local business.

\[ ] El escaneo busca después código global.

\[ ] El escaneo permite crear producto manual si no encuentra nada.

\[ ] La app no llama Supabase por cada escaneo.

\[ ] pull\_product\_catalog\_delta pagina hasta has\_more=false.

\[ ] Los records se aplican en orden master\_product → global\_barcode → business\_barcode.

\[ ] image\_url pesado no se descarga en sync principal.

\[ ] image\_thumb\_url se cachea lazy.

\[ ] contribuciones se pueden crear offline.

\[ ] contribuciones se suben cuando vuelve internet.

\[ ] errores de sync quedan visibles al usuario/admin.

\[ ] productos locales creados desde master guardan master\_product\_id.

\[ ] códigos locales guardan scope=business.

\[ ] catálogo global se considera solo sugerencia, no inventario real.

19\. RPCs relacionadas



Catálogo:



lookup\_product\_by\_barcode

pull\_product\_catalog\_delta

submit\_product\_catalog\_contribution

review\_product\_catalog\_contribution



Runtime/offline:



register\_or\_update\_app\_device

ensure\_business\_runtime\_setup

pull\_sync\_changes\_v2

process\_sync\_batch



Inventario relacionado:



apply\_pos\_batch\_inventory\_movements

apply\_purchase\_batch\_inventory\_movements

create\_inventory\_movement



20\. Estado backend requerido



Este contrato asume completadas:



✅ 6.19A register\_or\_update\_app\_device

✅ 6.19B ensure\_business\_runtime\_setup

✅ 6.19C catálogo offline-first completo

✅ 6.14 pull\_sync\_changes\_v2

✅ 6.15 compras offline

✅ 6.13 POS inventory application

✅ 6.16 resolución de conflictos

✅ 6.17 observabilidad/soporte

