# C1 — Inactive cash movement foundation

This ledger is storage, not a productive feature. No UI/application writer,
outbox serializer, sync entity, ACK or recovery dataset is enabled in C1.
Authenticated clients have SELECT only, scoped by active membership/branch and
`cash.read`. This permission includes amounts and notes of ordinary cash activity;
it does not expose inventory costs or profitability. Notes must not contain
payroll personal details or secrets. Service-role INSERT is infrastructure-only.

`cash.disburse` authorizes future outflows; `cash.receive` future inflows.
Only system owner/admin receive both by default. They do not grant INSERT in C1.

Amounts are positive, exact cents locally (`BigInt`/SQLite INTEGER), exact numeric
remotely, maximum 999999999999.99 currency units and at most two decimals.
Direction supplies the sign. Category is classification, NOT an expense flag.
Utilities can represent water/electricity/internet using a note. A cash deposit
can be classified as `other_income`/`other` without extending the pilot vocabulary.

Idempotency is UNIQUE (business_id, idempotency_key), following the existing cash
adjustment pattern. C2 keys must include the installation/operation identity; the
same key cannot create another movement in the business, even on another branch.
No global tenant-crossing key uniqueness is imposed.

Backend guards enforce consistent business/branch/register/session and same-scope
reversal references. C1 deliberately permits structural rows for closed sessions
in internal tests/imports: this is not authorization to create ordinary movements
against closed sessions. C2 must validate open state atomically with insertion,
using the same session lock ordering as authoritative close, and derive actor
from auth.uid(), never from an untrusted payload.

Backend rows are immutable, including metadata. Local economic fields are also
immutable; only local transport state/updated_at can change. No soft deletion is
needed for an append-only ledger. Reversal reference reserves a future workflow;
it does not authorize or implement reversal amounts, timing or approval.

Future purchase representation: source_type=purchase, source_id=purchase UUID,
category=supplier_purchase, direction=outflow. This is a reference contract only,
not purchase payment integration or expense recognition.

## C2 activation gate

Before ANY creation/sync surface is enabled, implement together:

- Local transactional recording/outbox and direction-specific authorization.
- Exact expected cash: opening + completed cash sale payments + ordinary inflows
  - ordinary outflows +/- stale-reconciliation adjustments, locally and remotely.
- Canonical idempotent sync projection and ACK states pending/applied/rejected.
- Recovery hydration, pending preservation and explicit stale/closed-session
  conflicts. An offline movement whose session was closed elsewhere must NOT be
  discarded, silently reassigned or automatically applied to a new session.
- Full scope/actor validation and capability checks on every active write path.

`cash_session_adjustments`, sale payments, cash closing, scheduler and existing
recovery retain their previous meaning and implementation throughout C1.
