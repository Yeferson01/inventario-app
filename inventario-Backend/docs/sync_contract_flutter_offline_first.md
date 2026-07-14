\# Contrato final de Sync Flutter / Offline-first



Proyecto: Inventario / POS / Offline-first  

Backend: Supabase + Postgres  

Frontend objetivo: Flutter  

Estado backend: Fase 6.18



\---



\## 1. Objetivo del contrato



Este documento define cómo debe integrarse la app Flutter con la capa offline/sync del backend.



La app debe poder:



\- Trabajar sin internet.

\- Crear ventas, compras, clientes, proveedores, productos y pagos offline.

\- Guardar cambios localmente.

\- Sincronizar cuando haya conexión.

\- Resolver conflictos.

\- Descargar cambios del servidor.

\- Aplicar inventario después de ventas/compras.

\- Mantener trazabilidad completa.

\- Evitar duplicados mediante UUIDs e idempotency keys.



\---



\## 2. Principios obligatorios



\### 2.1 Offline-first real



La app NO debe depender del servidor para crear IDs.



Toda entidad nueva debe nacer localmente con un ID generado por la app.



Recomendación:



```txt

UUIDv7 en Flutter



El backend mantiene defaults con gen\_random\_uuid() solo como fallback, pero el flujo profesional es:



La app genera IDs → la app crea registros locales → luego sincroniza.



2.2 No hard delete



La app no debe borrar físicamente registros de negocio.



Para eliminar algo, debe usar:



deleted\_at

deleted\_by

delete\_reason



Operaciones delete en sync deben considerarse peligrosas. El backend ya bloquea hard delete en entidades críticas.



2.3 Idempotencia obligatoria



Cada operación offline debe tener:



idempotency\_key

client\_mutation\_id

client\_sequence

client\_batch\_id



Regla recomendada:



idempotency\_key = "{deviceInstallationId}:{entityTable}:{entityId}:{operation}:{localSequence}"



Ejemplo:



device-abc:sales:uuid-sale-1:insert:103



2.4 Orden local de escritura



La app debe guardar primero en SQLite/Drift/Isar local, y después crear la mutación pendiente.



Flujo:



1\. Usuario hace acción

2\. App escribe tabla local

3\. App registra sync\_mutation local

4\. UI se actualiza inmediatamente

5\. Sync worker sube cambios cuando hay red

3\. Tablas backend principales de sync

3.1 app\_devices



Representa una instalación de la app.



No es una caja física ni un equipo de inventario. Es el dispositivo/app installation.



Campos importantes:



id

business\_id

profile\_id

branch\_id

installation\_id

device\_name

platform

app\_version

os\_version

status

last\_seen\_at

metadata

sync\_status

versión



3.2 sync\_batches



Representa un intento de sincronización.



Campos importantes:



id

business\_id

app\_device\_id

profile\_id

branch\_id

client\_batch\_id

direction

status

mutation\_count

applied\_count

skipped\_count

conflict\_count

error\_count

metadata

archived\_at



Valores de direction:



upload

download



Estados esperados:



pending

processing

completed

partial

error



3.3 sync\_mutations



Representa una operación offline individual.



Campos importantes:



id

sync\_batch\_id

business\_id

app\_device\_id

profile\_id

branch\_id

client\_mutation\_id

client\_sequence

entity\_table

entity\_id

operation

payload

before\_payload

changed\_fields

base\_version

base\_updated\_at

status

idempotency\_key

metadata



Operaciones:



insert

update

upsert

soft\_delete

delete



Uso recomendado:



insert       → entidad nueva creada offline

update       → entidad existente modificada

upsert       → tolerante para algunos catálogos

soft\_delete  → eliminación lógica

delete       → evitar; backend la bloquea en flujos críticos

3.4 sync\_conflicts



Representa un conflicto detectado por el servidor.



Campos importantes:



id

business\_id

sync\_batch\_id

sync\_mutation\_id

app\_device\_id

profile\_id

branch\_id

entity\_table

entity\_id

operation

client\_mutation\_id

client\_sequence

conflict\_type

severity

status

resolution\_strategy

client\_payload

server\_payload

resolved\_payload

metadata



Tipos comunes de conflicto:



version\_mismatch

updated\_at\_mismatch

missing\_server\_row

deleted\_on\_server

duplicate\_key

permission\_denied

validation\_error

business\_rule\_violation

unknown



Estados:



open

resolved

retry\_requested

ignored

3.5 sync\_cursors



Guarda el cursor de descarga incremental por dispositivo.



La app normalmente no debe manipular esta tabla directamente. Debe usar:



pull\_sync\_changes\_v2(...)



4\. RPCs públicas principales

4.1 Upload / Apply

process\_sync\_batch(sync\_batch\_id, mode)



Modos disponibles:



validate\_only

apply\_catalog

apply\_pos

apply\_purchases

4.2 Inventario posterior al upload



Después de aplicar ventas POS:



apply\_pos\_batch\_inventory\_movements(sync\_batch\_id)



Después de aplicar compras:



apply\_purchase\_batch\_inventory\_movements(sync\_batch\_id)



Estas funciones son idempotentes.



4.3 Pull incremental

pull\_sync\_changes(...)

pull\_sync\_changes\_v2(...)



Usar preferiblemente:



pull\_sync\_changes\_v2(...)



Porque soporta paginación por entidad con next\_page\_tokens.



4.4 Conflictos

get\_sync\_conflict\_summary(sync\_conflict\_id)

resolve\_sync\_conflict\_server\_wins(sync\_conflict\_id, notes)

resolve\_sync\_conflict\_client\_retry(sync\_conflict\_id, notes)

ignore\_sync\_conflict(sync\_conflict\_id, notes)

resolve\_sync\_conflict\_manual(sync\_conflict\_id, resolved\_payload, notes)

apply\_resolved\_sync\_conflict\_payload(sync\_conflict\_id)

4.5 Observabilidad / soporte

get\_sync\_operational\_dashboard(...)

get\_sync\_open\_conflicts(...)

get\_app\_device\_sync\_health(...)

get\_sync\_cleanup\_preview(...)

archive\_old\_sync\_records(...)

get\_sync\_support\_workbench(...)

get\_sync\_support\_batch\_detail(...)

get\_sync\_support\_device\_timeline(...)



Estas son para pantallas admin/soporte, no para el flujo POS normal.



5\. Flujo inicial de la app

5.1 Login



La app usa Supabase Auth.



Después de login:



profile\_id = auth.uid()



La app debe cargar:



business\_members

businesses

branches

roles

permissions



Puede hacerlo mediante pull inicial o consultas directas permitidas por RLS.



5.2 Selección de negocio y sucursal



La app debe tener contexto activo:



currentBusinessId

currentBranchId

currentProfileId

currentAppDeviceId



Toda operación offline debe incluir:



business\_id

branch\_id cuando aplique

created\_by / updated\_by local

5.3 Registro de app\_device



Al instalar la app se crea un installation\_id persistente localmente.



Ejemplo:



installation\_id = UUIDv7 o UUID random estable por instalación



Debe sobrevivir reinicios de app.



La app debe crear o actualizar un app\_devices con:



{

&#x20; "business\_id": "...",

&#x20; "profile\_id": "...",

&#x20; "branch\_id": "...",

&#x20; "installation\_id": "...",

&#x20; "device\_name": "Caja Android 1",

&#x20; "platform": "android",

&#x20; "app\_version": "1.0.0",

&#x20; "os\_version": "Android 14",

&#x20; "status": "active",

&#x20; "metadata": {

&#x20;   "model": "..."

&#x20; }

}



Recomendación:



Guardar app\_device.id localmente por business\_id + installation\_id.



6\. Modelo local recomendado en Flutter



La app debe tener base local.



Recomendado:



Drift / SQLite



Cada tabla local de negocio debería tener, como mínimo:



id

business\_id

branch\_id

created\_at

updated\_at

deleted\_at

version

sync\_status

local\_status

last\_synced\_at

dirty\_at

created\_by

updated\_by

deleted\_by

metadata



Estados locales sugeridos:



synced

pending\_upload

uploading

conflict

error

deleted\_pending

7\. Cola local de mutaciones



La app debe mantener una tabla local similar a:



local\_sync\_mutations



Campos recomendados:



local\_id

server\_sync\_mutation\_id nullable

client\_mutation\_id

client\_sequence

client\_batch\_id nullable

business\_id

branch\_id

app\_device\_id

profile\_id

entity\_table

entity\_id

operation

payload

before\_payload

changed\_fields

base\_version

base\_updated\_at

idempotency\_key

status

retry\_count

last\_error

created\_at

updated\_at



Estados locales:



pending

batched

uploading

applied

skipped

conflict

error

8\. Orden recomendado de upload



La app debe subir por dominios separados.



No mezclar todo en un solo batch si no es necesario.



8.1 Catálogo



Entidades:



categories

customers

suppliers

products



Modo:



apply\_catalog



Orden recomendado:



1\. categories

2\. customers

3\. suppliers

4\. products

8.2 POS



Entidades:



sales

sale\_items

sale\_payments



Modo:



apply\_pos



Orden obligatorio:



1\. sales

2\. sale\_items

3\. sale\_payments

4\. sales update final si aplica



Después:



apply\_pos\_batch\_inventory\_movements(sync\_batch\_id)

8.3 Compras



Entidades:



purchases

purchase\_items



Modo:



apply\_purchases



Orden obligatorio:



1\. purchases

2\. purchase\_items

3\. purchases update final si aplica



Después:



apply\_purchase\_batch\_inventory\_movements(sync\_batch\_id)

8.4 Inventario directo



Para ajustes directos de inventario, usar preferiblemente RPC específica:



create\_inventory\_movement(...)



No subir inventory\_movements como update/delete.



Regla:



inventory\_movements es ledger inmutable.

8.5 Stock counts y transfers



Backend tiene estructura para stock counts/transfers, pero el contrato final de sync automático por process\_sync\_batch debe tratarse como pendiente si todavía no se implementó un modo específico.



Regla actual recomendada:



Implementar stock counts/transfers vía RPC dedicada, no como sync\_mutations genéricas, hasta crear apply\_stock\_counts/apply\_transfers.

9\. Cómo crear un sync batch de upload

9.1 Crear sync\_batch



Ejemplo:



{

&#x20; "id": "uuidv7",

&#x20; "business\_id": "...",

&#x20; "app\_device\_id": "...",

&#x20; "profile\_id": "...",

&#x20; "branch\_id": "...",

&#x20; "client\_batch\_id": "device-abc:batch:000001",

&#x20; "direction": "upload",

&#x20; "status": "pending",

&#x20; "metadata": {

&#x20;   "domain": "pos",

&#x20;   "app\_version": "1.0.0"

&#x20; }

}

9.2 Crear sync\_mutations



Ejemplo POS sales:



{

&#x20; "id": "uuidv7",

&#x20; "sync\_batch\_id": "...",

&#x20; "business\_id": "...",

&#x20; "app\_device\_id": "...",

&#x20; "profile\_id": "...",

&#x20; "branch\_id": "...",

&#x20; "client\_mutation\_id": "device-abc:mutation:000001",

&#x20; "client\_sequence": 1,

&#x20; "entity\_table": "sales",

&#x20; "entity\_id": "sale-uuidv7",

&#x20; "operation": "insert",

&#x20; "payload": {

&#x20;   "id": "sale-uuidv7",

&#x20;   "business\_id": "...",

&#x20;   "branch\_id": "...",

&#x20;   "cash\_session\_id": "...",

&#x20;   "customer\_id": null,

&#x20;   "status": "completed",

&#x20;   "processing\_status": "completed",

&#x20;   "subtotal": 10000,

&#x20;   "discount\_total": 0,

&#x20;   "tax\_total": 0,

&#x20;   "total": 10000,

&#x20;   "paid\_total": 10000,

&#x20;   "change\_amount": 0,

&#x20;   "currency": "COP",

&#x20;   "idempotency\_key": "device-abc:sales:sale-uuidv7:insert"

&#x20; },

&#x20; "changed\_fields": \[

&#x20;   "business\_id",

&#x20;   "branch\_id",

&#x20;   "cash\_session\_id",

&#x20;   "status",

&#x20;   "total",

&#x20;   "paid\_total"

&#x20; ],

&#x20; "base\_version": null,

&#x20; "idempotency\_key": "device-abc:sales:sale-uuidv7:insert"

}



Ejemplo sale\_items:



{

&#x20; "entity\_table": "sale\_items",

&#x20; "entity\_id": "sale-item-uuidv7",

&#x20; "operation": "insert",

&#x20; "payload": {

&#x20;   "id": "sale-item-uuidv7",

&#x20;   "sale\_id": "sale-uuidv7",

&#x20;   "product\_id": "product-uuid",

&#x20;   "quantity": 2,

&#x20;   "unit\_price": 5000,

&#x20;   "discount\_amount": 0,

&#x20;   "tax\_amount": 0,

&#x20;   "total": 10000,

&#x20;   "idempotency\_key": "device-abc:sale\_items:sale-item-uuidv7:insert"

&#x20; },

&#x20; "client\_sequence": 2

}



Ejemplo sale\_payments:



{

&#x20; "entity\_table": "sale\_payments",

&#x20; "entity\_id": "payment-uuidv7",

&#x20; "operation": "insert",

&#x20; "payload": {

&#x20;   "id": "payment-uuidv7",

&#x20;   "sale\_id": "sale-uuidv7",

&#x20;   "business\_id": "...",

&#x20;   "branch\_id": "...",

&#x20;   "payment\_method": "cash",

&#x20;   "amount": 10000,

&#x20;   "currency": "COP",

&#x20;   "status": "completed",

&#x20;   "idempotency\_key": "device-abc:sale\_payments:payment-uuidv7:insert"

&#x20; },

&#x20; "client\_sequence": 3

}



10\. Cómo procesar upload

10.1 Catalog

process\_sync\_batch(batchId, 'apply\_catalog')

10.2 POS

process\_sync\_batch(batchId, 'apply\_pos')



Después:



apply\_pos\_batch\_inventory\_movements(batchId)

10.3 Purchases

process\_sync\_batch(batchId, 'apply\_purchases')



Después:



apply\_purchase\_batch\_inventory\_movements(batchId)

11\. Interpretación de resultado de process\_sync\_batch



Ejemplo:



{

&#x20; "status": "partial",

&#x20; "mutation\_count": 4,

&#x20; "applied\_count": 3,

&#x20; "skipped\_count": 0,

&#x20; "conflict\_count": 1,

&#x20; "error\_count": 0

}



Interpretación:



completed → todo bien

partial   → algunas mutaciones no aplicaron, revisar conflicts/errors

error     → fallo general o errores críticos



La app debe consultar:



sync\_mutations por batch

sync\_conflicts por batch



o usar RPC admin si está en pantalla soporte:



get\_sync\_support\_batch\_detail(batchId)

12\. Pull incremental v2



La app debe usar:



pull\_sync\_changes\_v2(appDeviceId, since, entities, limitPerEntity, pageTokens)

12.1 Bootstrap inicial



Primer pull:



since = null

entities = null

page\_tokens = {}



La app debe repetir mientras:



has\_more = true



usando:



next\_page\_tokens

12.2 Pull incremental normal



Después del bootstrap:



since = null

entities = null

page\_tokens = {}



El servidor usa su cursor sync\_cursors.



12.3 Pull parcial por entidades



Ejemplo:



entities = \['products', 'customers']



Importante:



Si entities no es null, el cursor global no avanza.



Esto es correcto para búsquedas o refresh parcial.



12.4 Orden recomendado de aplicar pull en local



La app debe aplicar cambios descargados en orden seguro:



1\. businesses

2\. branches

3\. profiles

4\. business\_members

5\. roles

6\. permissions

7\. role\_permissions

8\. categories

9\. customers

10\. suppliers

11\. products

12\. cash\_registers

13\. cash\_sessions

14\. sales

15\. sale\_items

16\. sale\_payments

17\. purchases

18\. purchase\_items

19\. product\_stock\_balances

20\. inventory\_movements

13\. Conflictos

13.1 Cuándo hay conflicto



Ejemplos:



version\_mismatch

duplicate\_key

missing\_server\_row

validation\_error

business\_rule\_violation

permission\_denied



La app debe marcar la entidad local como:



conflict



y mostrarla en UI si afecta una acción importante.



13.2 Server wins



Uso:



resolve\_sync\_conflict\_server\_wins(conflictId, notes)



La app debe:



1\. marcar mutación local como skipped

2\. reemplazar estado local con próximo pull

3\. limpiar dirty flag local

13.3 Client retry



Uso:



resolve\_sync\_conflict\_client\_retry(conflictId, notes)



La app debe:



1\. crear nueva mutación local

2\. incrementar client\_sequence

3\. usar nuevo idempotency\_key

4\. volver a subir

13.4 Ignore



Uso:



ignore\_sync\_conflict(conflictId, notes)



La app debe:



1\. marcar mutación local como skipped

2\. dejar entidad local según servidor/pull

13.5 Manual resolution



Uso:



resolve\_sync\_conflict\_manual(conflictId, resolvedPayload, notes)



El payload recomendado:



{

&#x20; "manual\_decision": "apply\_safe\_customer\_update",

&#x20; "final\_payload": {

&#x20;   "full\_name": "Cliente corregido",

&#x20;   "phone": "+57 ..."

&#x20; },

&#x20; "notes": "Decisión manual del administrador"

}



Para entidades seguras:



categories

customers

suppliers



se puede aplicar después con:



apply\_resolved\_sync\_conflict\_payload(conflictId)



No aplica a entidades críticas como:



purchases

sales

inventory\_movements

cash\_sessions



14\. Estados UI recomendados

14.1 Estado global de sync

online

offline

syncing

synced

partial

conflict

error

14.2 Estado por registro

synced

pending\_upload

uploading

conflict

error

deleted\_pending

archived\_remote

14.3 Indicadores POS



En venta offline:



Pendiente de sincronizar

Sincronizada

Sincronizada con conflicto

Inventario aplicado

Inventario pendiente

Error de inventario

15\. Reintentos



La app debe implementar reintentos con backoff.



Recomendación:



1 min

5 min

15 min

1 hora

manual



No reintentar automáticamente si:



permission\_denied

business\_rule\_violation

validation\_error crítico

hard delete blocked



Sí puede reintentar si:



network\_error

timeout

server temporarily unavailable

16\. Manejo de errores comunes

16.1 Insufficient permission



Acción app:



\- detener sync de esa entidad

\- refrescar permisos

\- pedir al usuario reingresar o contactar admin

16.2 version\_mismatch



Acción app:



\- crear conflicto local

\- mostrar comparación cliente/servidor si aplica

\- permitir server wins, retry o manual

16.3 duplicate\_key



Acción app:



\- revisar si la entidad ya existe por idempotency\_key

\- si es duplicado real, resolver server wins

16.4 validation\_error



Acción app:



\- mostrar campos inválidos

\- permitir corregir y reintentar

16.5 business\_rule\_violation



Acción app:



\- no reintentar automático

\- mostrar mensaje claro

\- requerir acción manual

17\. Inventario

17.1 Ventas POS



Después de aplicar POS:



apply\_pos\_batch\_inventory\_movements(batchId)



La app debe guardar en local el resultado:



sales\_checked

sales\_completed

sales\_applied

sales\_already\_applied

movements\_created

error\_count



Si error\_count > 0:



mostrar inventario pendiente/error

17.2 Compras



Después de aplicar compras:



apply\_purchase\_batch\_inventory\_movements(batchId)



La app debe guardar:



purchases\_checked

purchases\_completed

purchases\_applied

purchases\_already\_applied

movements\_created

error\_count

17.3 Ledger inmutable



La app no debe modificar directamente:



inventory\_movements



Solo debe crear movimientos a través de RPCs controladas.



18\. Observabilidad para admin



La app admin puede usar:



get\_sync\_operational\_dashboard

get\_sync\_open\_conflicts

get\_app\_device\_sync\_health

get\_sync\_support\_workbench

get\_sync\_support\_batch\_detail

get\_sync\_support\_device\_timeline



Pantallas recomendadas:



1\. Estado general de sync

2\. Dispositivos y último sync

3\. Conflictos abiertos

4\. Detalle de batch

5\. Mutaciones con error

6\. Historial por dispositivo

7\. Batches archivados

19\. Cleanup



El backend soporta archivado seguro:



get\_sync\_cleanup\_preview

archive\_old\_sync\_records



Reglas:



No hard delete

No archivar pending

No archivar processing

No archivar batches con conflictos open

Solo archivar cerrados y antiguos



La app normal no debería llamar esto. Solo admin/soporte.



20\. Checklist Flutter antes de producción

Auth/contexto

&#x20;Login Supabase Auth

&#x20;Obtener profile\_id

&#x20;Cargar negocios disponibles

&#x20;Seleccionar business\_id

&#x20;Seleccionar branch\_id

&#x20;Registrar app\_device

&#x20;Guardar app\_device\_id localmente

Offline storage

&#x20;Base local SQLite/Drift

&#x20;UUIDv7 local

&#x20;Tabla local de mutaciones

&#x20;Tabla local de sync state

&#x20;Índices locales por business\_id/branch\_id/sync\_status

Upload

&#x20;Crear sync\_batch por dominio

&#x20;Crear sync\_mutations ordenadas

&#x20;Enviar catalog con apply\_catalog

&#x20;Enviar POS con apply\_pos

&#x20;Aplicar inventario POS

&#x20;Enviar purchases con apply\_purchases

&#x20;Aplicar inventario purchases

&#x20;Manejar partial

&#x20;Manejar conflicts

&#x20;Manejar errors

Pull

&#x20;Bootstrap con pull\_sync\_changes\_v2

&#x20;Paginación con next\_page\_tokens

&#x20;Pull incremental normal

&#x20;Aplicar cambios en orden seguro

&#x20;Manejar deleted\_at

&#x20;Actualizar cursor local

Conflicts

&#x20;Listar conflictos

&#x20;Mostrar server/client payload

&#x20;Server wins

&#x20;Client retry

&#x20;Ignore

&#x20;Manual resolution

&#x20;Aplicar payload seguro en categories/customers/suppliers

UI

&#x20;Badge offline/online

&#x20;Estado syncing

&#x20;Contador pendientes

&#x20;Contador conflictos

&#x20;Estado por venta

&#x20;Estado por compra

&#x20;Estado inventario aplicado/pendiente

&#x20;Pantalla soporte/admin

Seguridad

&#x20;No usar service\_role en Flutter

&#x20;No hard delete

&#x20;No modificar inventory\_movements

&#x20;No confiar en roles locales sin refrescar

&#x20;Validar business\_id/branch\_id activos

&#x20;Respetar RLS

21\. Flujo completo recomendado

Al abrir app

1\. Detectar conexión

2\. Validar sesión Supabase

3\. Cargar contexto local

4\. Registrar/actualizar app\_device si hay red

5\. Mostrar datos locales inmediatamente

6\. Ejecutar sync en background si hay red

Sync background

1\. Upload catalog pendiente

2\. Upload purchases pendiente

3\. Aplicar inventario purchases

4\. Upload POS pendiente

5\. Aplicar inventario POS

6\. Pull incremental v2

7\. Actualizar UI/state

8\. Si hay conflictos, notificar

Al hacer venta offline

1\. Crear sale local con UUIDv7

2\. Crear sale\_items locales

3\. Crear sale\_payments locales

4\. Marcar venta pending\_upload

5\. Crear mutaciones locales

6\. Actualizar UI

7\. Cuando haya red, subir batch POS

8\. Aplicar inventario POS

9\. Pull incremental

10\. Marcar venta synced o conflict/error

Al hacer compra offline

1\. Crear purchase local con UUIDv7

2\. Crear purchase\_items locales

3\. Marcar compra pending\_upload

4\. Crear mutaciones locales

5\. Cuando haya red, subir batch purchases

6\. Aplicar inventario purchases

7\. Pull incremental

8\. Marcar compra synced o conflict/error

22\. Reglas que NO se deben romper

No usar service\_role en Flutter.

No borrar físicamente.

No generar IDs en servidor para entidades offline.

No subir inventario como update/delete.

No mezclar dominios críticos en un mismo batch si se puede evitar.

No ignorar partial/conflict/error.

No avanzar estado local a synced hasta confirmar servidor.

No aplicar inventario dos veces manualmente sin revisar resultado idempotente.

23\. Estado backend cubierto



El backend ya tiene:



app\_devices

sync\_batches

sync\_mutations

sync\_conflicts

sync\_cursors

process\_sync\_batch

apply\_catalog

apply\_pos

apply\_purchases

pull\_sync\_changes\_v2

conflict resolution

safe resolved payload application

POS inventory application

purchase inventory application

observability

support/admin RPCs

cleanup/archive

RLS

policies

permissions

idempotency

soft delete

audit metadata

24\. Pendientes futuros sugeridos



Para una versión posterior:



1\. RPC dedicada para registrar app\_device/upsert\_app\_device

2\. apply\_stock\_counts sync mode

3\. apply\_inventory\_transfers sync mode

4\. Endpoint específico para retry de conflicts desde app

5\. Métricas agregadas por día para dashboard histórico

6\. Alertas automáticas por conflictos antiguos

7\. Export de logs de soporte

8\. Pruebas E2E con Flutter + Supabase local

