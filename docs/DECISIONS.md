# Decisiones técnicas vigentes

Este registro conserva decisiones arquitectónicas de CronosManagement y las
distingue del estado implementado. No sustituye la fotografía factual de
[CURRENT_STATE.md](CURRENT_STATE.md), la arquitectura de
[ARCHITECTURE.md](ARCHITECTURE.md) ni las reglas operativas de
[AGENTS.md](../AGENTS.md).

## Formato

- **Estado:** `vigente` cuando la decisión forma parte del contrato actual;
  `zona no decidida` cuando solo se conoce la infraestructura o la deuda.
- **Decisión:** regla que debe preservarse.
- **Motivo:** necesidad que la origina.
- **Consecuencias:** efectos y límites prácticos.

### D-001 — Offline-first real

**Estado:** vigente.

**Decisión:** Drift/SQLite es la fuente local inmediata. Una operación que el
dominio puede resolver localmente se escribe antes del upload, actualiza la UI
desde local y usa IDs generados por el cliente. La sincronización ocurre después.

**Motivo:** ventas, caja, compras y demás operaciones compatibles deben seguir
funcionando durante pérdidas de conectividad.

**Consecuencias:** la disponibilidad de internet no forma parte de la
transacción local; estado local, outbox y estado remoto conservan
responsabilidades separadas. Un dominio puede tener pasos de reconciliación
propios sin dejar de ser offline-first.

### D-002 — Supabase como backend central y servidor de sync

**Estado:** vigente.

**Decisión:** Supabase/Postgres es el servidor central para consolidación,
seguridad multi-tenant, RPCs y procesamiento de sincronización. No debe
convertirse en una dependencia sincrónica de cada acción local.

**Motivo:** centralizar datos y políticas sin hacer que la operación cotidiana
dependa de la red.

**Consecuencias:** los accesos remotos se realizan mediante uploaders y pulls
delimitados. Una consulta remota de soporte no reemplaza la lectura local
operacional.

### D-003 — Contexto multi-tenant por negocio y sucursal

**Estado:** vigente.

**Decisión:** `business` y `branch` son parte central del contexto operacional.
Las operaciones que dependen de ubicación, en especial el inventario, se
delimitan por sucursal.

**Motivo:** un usuario puede operar en negocios o sucursales distintos, con
datos, permisos, caja y existencias diferentes.

**Consecuencias:** servicios, payloads, consultas y saldos deben recibir o
resolver el contexto correcto. Un saldo de producto sin sucursal no representa
el inventario operacional vigente.

### D-004 — Frontera Presentation / Application / Data

**Estado:** vigente.

**Decisión:** la cadena de la UI final es
`presentation → application → data`. Presentation recoge intención y muestra
estado; Application implementa casos de uso y coordinación; Data contiene DAOs,
repositorios y datasources.

**Motivo:** mantener reglas de negocio, persistencia y transporte fuera de las
pantallas y hacer reutilizables los flujos operacionales.

**Consecuencias:** la UI final no implementa reglas de negocio ni accede
directamente a DAOs/datasources, salvo un patrón ya establecido y expresamente
autorizado para el caso. Una pantalla nueva debe reutilizar servicios/providers
de Application antes de abrir otra vía de acceso a datos.

### D-005 — Outbox común e identidad idempotente

**Estado:** vigente.

**Decisión:** `local_sync_batches` y `local_sync_mutations` son el outbox común.
Client batch IDs, client mutation IDs, client sequences e idempotency keys
identifican lógicamente los intentos. Un retry reutiliza la identidad de la
operación que está reintentando.

**Motivo:** tolerar interrupciones y respuestas parciales sin duplicar ventas,
compras, pagos, inventario u otras entidades.

**Consecuencias:** los uploaders por dominio comparten batches, mutations,
estados, errores y contadores de retry. No se reemplaza este mecanismo ni se
crea un outbox paralelo sin una decisión arquitectónica específica. Reintentar
no significa generar una operación de negocio nueva.

### D-006 — Borrado lógico para entidades de negocio

**Estado:** vigente.

**Decisión:** no se implementa hard delete para entidades de negocio sin una
decisión específica. Se preservan soft delete y tombstones donde aplica el
contrato.

**Motivo:** mantener trazabilidad y permitir que eliminaciones se propaguen de
forma segura entre dispositivos.

**Consecuencias:** el filtrado de activos y el pull deben contemplar registros
borrados lógicamente; una operación `delete` de sync no autoriza por sí misma un
borrado físico.

### D-007 — Catálogo y barcode lookup local-first

**Estado:** vigente.

**Decisión:** un escaneo normaliza el barcode y busca primero el producto local
del negocio, luego el catálogo maestro local. Si no hay coincidencia puede
crearse un producto manual siguiendo el flujo previsto. No se consulta
Supabase por cada escaneo.

**Motivo:** permitir búsqueda rápida y venta sin conectividad, evitando una
petición remota por lectura.

**Consecuencias:** el catálogo maestro se descarga y actualiza mediante pull; la
creación y las contribuciones se sincronizan después. Los RPCs remotos de lookup
son soporte o excepción, no la ruta operacional normal.

### D-008 — Saldo y trazabilidad de inventario separados de Products

**Estado:** vigente.

**Decisión:** `local_product_stock_balances` contiene el saldo local operativo
por negocio, sucursal y producto; `local_inventory_movements` contiene el
ledger y su trazabilidad. `products.stock_quantity` es legacy y no es source of
truth. `products.minimum_stock` es configuración, no saldo.

**Motivo:** representar correctamente inventario por sucursal y explicar cada
variación mediante movimientos.

**Consecuencias:** ventas y compras afectan balances y movements mediante sus
flujos existentes. No se crea un segundo sistema de stock ni se recupera
`stock_quantity` como autoridad accidental. Los umbrales pueden leer
`minimum_stock`, pero siempre los comparan con el saldo operacional.

### D-009 — Ubicación vigente del POS

**Estado:** vigente para el baseline actual.

**Decisión:** el flujo POS operacional vive en `features/sales`.
`features/pos` es un scaffold sin implementación operacional relevante y no se
asume como destino automático de cambios.

**Motivo:** documentar la realidad del código sin ejecutar una reorganización
arquitectónica implícita.

**Consecuencias:** los cambios del POS actual parten de `features/sales`. Mover
responsabilidades a `features/pos` requiere una decisión explícita de
reorganización.

### D-010 — Caja como precondición operacional del POS

**Estado:** vigente.

**Decisión:** el POS aplica las reglas actuales de cash session: necesita el
contexto de caja abierto y, para el upload, la preparación remota requerida por
el uploader. El cierre visible sigue
`cash → POS → cierre local → cash`.

**Motivo:** asociar las ventas a una sesión válida y evitar cerrar caja dejando
ventas locales pendientes antes del cierre remoto.

**Consecuencias:** abrir, sincronizar y cerrar caja usan los servicios existentes.
La secuencia visible de cierre no debe confundirse con el trigger de scheduled
sync.

### D-011 — E2E/debug es laboratorio

**Estado:** vigente.

**Decisión:** pantallas y servicios E2E/debug validan infraestructura y flujos
controlados, pero no definen la UI final ni el diseño terminado del producto.

**Motivo:** conservar herramientas de diagnóstico sin promover sus botones y
atajos a contratos de presentación.

**Consecuencias:** una capacidad demostrada en el laboratorio no se marca como
UI final completada. La UI productiva usa servicios de Application y sus propias
reglas de interacción.

### D-012 — Sync automatizable y coordinado

**Estado:** decisión vigente; cobertura implementada parcial.

**Decisión:** un producto offline-first debe poder automatizar y coordinar la
sincronización sin hacer depender la operación local de ella.

**Motivo:** enviar cambios pendientes y refrescar datos sin exigir que cada
acción del usuario gestione manualmente toda la sincronización.

**Estado actual implementado:** `ScheduledSyncService` solo sube batches de
catálogo y hace pull delta de catálogo. `AppSyncCoordinatorService` agrega el
preflight, la verificación online, la preparación de runtime y el pull de
contexto operacional antes de delegar. POS, purchases, cash e inventory no
forman parte de esa cadena programada actual.

**Consecuencias:** “solo catálogo” describe el baseline, no una decisión
arquitectónica definitiva sobre el alcance futuro del scheduled sync.

### D-013 — Conflictos de sincronización locales

**Estado:** zona no decidida.

**Hecho confirmado:** el backend implementa `sync_conflicts` y RPCs relacionados.
El schema Drift 8 no contiene una tabla local equivalente.

**Decisión pendiente:** no está confirmado qué modelo local o experiencia de UI
debe representar y resolver conflictos.

**Consecuencias:** no se inventa una tabla, servicio, política de resolución o
UI local. La infraestructura remota existente no cierra esta decisión.

### D-014 — Cambios autorizados del esquema Drift

**Estado:** vigente.

**Decisión:** `app_database.g.dart` es generado y no se edita manualmente.
`build_runner` y la generación Drift se ejecutan cuando una modificación
autorizada cambia el esquema.

**Motivo:** mantener consistentes tablas, companions, migraciones y código
generado.

**Consecuencias:** un cambio real de tablas exige revisar `schemaVersion`, la
estrategia de migración, regenerar y probar la base. Un cambio Dart que no
altera tablas no obliga por sí mismo a incrementar `schemaVersion`.

### D-015 — Autorización efectiva y ciclo financiero de caja

**Estado:** vigente.

**Decisión:** la autorización es capability/effective-permission based, no
active-role based. Los permisos efectivos de las memberships aplicables se
usan como unión server-authoritative; los nombres de roles son descriptivos.

Una cash session representa el ciclo financiero de una caja. No es una sesión
de autenticación ni un rol activo. Cambiar de módulo dentro del mismo contexto
operacional no exige cerrar caja.

**Consecuencias:** POS, Caja, Inventario y Compras se muestran y habilitan por
sus permission keys reales. Un usuario puede operar simultáneamente los módulos
que su unión de permisos autorice. El gating de UI mejora la UX, pero no
sustituye los guards de Application/Domain ni la autorización backend.

### D-016 — Identidad de Product, MasterProduct y códigos

**Estado:** vigente.

**Decisión:** `products.id` es la identidad empresarial estable;
`master_product_id` es una identidad global opcional y vinculable después sin
cambiar el Product UUID. Los códigos se modelan como asociaciones 1:N. Un
código `internal`/`local_sku` pertenece exclusivamente a un business y nunca es
identidad inter-tenant. Solo un vínculo explícito con MasterProduct y sus
códigos globales permite correlación automática entre negocios.

**Consecuencias:** un Product sin master ni GS1 continúa siendo válido para
compras, ventas e inventario. El lookup prioriza el código empresarial; los
códigos internos no caen al catálogo global. Imágenes u otra metadata global se
resuelven mediante `master_product_id`, sin duplicarlas en Product.

### D-017 — Convergencia del catálogo maestro por ventanas

**Estado:** vigente.

**Decisión:** el cursor comprometido del catálogo avanza únicamente cuando la
ventana completa termina. Cada página y su token de reanudación se persisten en
la misma transacción local; una interrupción reanuda la ventana firmada o la
repite desde el último cursor comprometido. Los tombstones forman parte del
pull y las filas se aplican por `version`, sin sobrescribir una versión más
nueva ni estado local dirty.

**Consecuencias:** alcanzar el presupuesto de páginas produce un resultado
incompleto y reanudable, no success. Reaplicar páginas es seguro y preferible a
omitir registros; catálogo maestro y bootstrap operacional conservan
mecanismos separados.

### D-018 — Autoridad del catálogo maestro

**Estado:** vigente.

**Decisión:** los permisos empresariales sobre Products nunca conceden autoridad
sobre el catálogo maestro global. Las contribuciones separan la autoridad
tenant para proponer cambios de la autoridad global para revisarlos.

**Consecuencias:** un usuario autenticado y autorizado puede enviar propuestas
desde su contexto empresarial, pero inicialmente solo `service_role` puede
revisarlas y escribir MasterProducts o códigos globales. Los roles y permisos
del negocio no sustituyen una futura capability administrativa de plataforma.

### D-019 — Contrato único de creación empresarial de Product

**Estado:** vigente.

**Decisión:** todos los entry points de creación empresarial de Product usan
`BusinessProductCreationService`, la fachada Application offline-first que
prioriza el Product empresarial existente, puede materializar una sugerencia
del catálogo maestro local y delega creación manual, vínculo posterior y
outbox a los servicios de catálogo ya establecidos.

**Consecuencias:** Presentation no forma mutaciones ni consulta Supabase durante
el lookup. Crear exige `products.create`; vincular un Product existente a master
exige `products.update`. Los precios, `category_id`, `minimum_stock`, unidad y
overrides pertenecen al negocio; la identidad y metadata descriptiva global son
master-owned/sugeridas y no sobrescriben esos campos comerciales.

### D-020 — Lectura global del catálogo y ACL mínimas

**Estado:** vigente.

**Decisión:** los datos de referencia activos y sincronizados del catálogo
maestro global son legibles directamente por usuarios autenticados. Ese acceso
de lectura no concede autoridad de mutación global. Los clientes envían
propuestas mediante el RPC de contribuciones; solo la autoridad administrativa
de plataforma puede revisarlas.

Los roles cliente reciben ACL explícitas y mínimas. RLS delimita las filas que
puede leer un rol autorizado, pero no sustituye la revocación de privilegios
destructivos de tabla como `TRUNCATE`, `REFERENCES` o `TRIGGER`. Los tombstones
necesarios para sincronización permanecen disponibles mediante el RPC
`SECURITY DEFINER`, no mediante el `SELECT` directo.

**Consecuencias:** `anon` no accede directamente a las tres tablas endurecidas
ni a los RPCs de pull/submit/review; `authenticated` tiene lectura directa
acotada y usa los RPCs autorizados para pull/submit; la revisión global
permanece reservada a `service_role`.

### D-021 — Inmutabilidad de migraciones compartidas

**Estado:** vigente.

**Decisión:** una migración se vuelve inmutable cuando ha sido aplicada a un
entorno compartido o remoto. Una migración que nunca fue desplegada remotamente
puede corregirse antes de su primer despliegue cuando hacerlo evita publicar un
estado intermedio conocido como inválido.

**Consecuencias:** la corrección PostgreSQL del token vacío queda incorporada
directamente en CATALOG-2B antes de su primer despliegue y la migración local
redundante CATALOG-2B.1 se retira del conjunto futuro. Esta excepción no permite
reescribir migraciones ya compartidas.

### D-022 — Onboarding privado mediante invitación durable

**Estado:** vigente.

**Decisión:** crear un nuevo tenant requiere una invitación durable de
plataforma emitida exclusivamente por `service_role`. Business Owner/Admin no
es autoridad de plataforma. La invitación fija los IDs canónicos de Business y
de su Branch primaria; su aceptación autenticada consume la invitación y
reutiliza `create_business` en una única transacción. `create_business` no es
una capability directa del rol `authenticated`.

La primera Branch activa tiene identidad formal mediante `is_primary` y existe
como máximo una primaria no eliminada por Business. El Owner inicial conserva
membership business-wide (`branch_id IS NULL`). El `app_device` se registra
después de discovery y selección, no durante la aceptación.

**Motivo:** impedir signup empresarial abierto, replay y duplicación accidental
por retries con UUID nuevos, sin crear un segundo motor de aprovisionamiento ni
confundir autoridad de tenant con autoridad global de Cronos.

**Consecuencias:** la emisión y el estado de entrega de email son server-side y
separados de la autoridad de aceptación. Usuarios y negocios existentes no
requieren invitaciones retroactivas. `operationalReady` y `catalogReady` son
estados distintos; la inicialización del catálogo se implementará en ORG-1D.
