# PinTheory Supabase — phase-one backend foundation

**Not deployed. Not database-tested. Not fully shipped auth or offline sync.**
This backend foundation has corresponding Swift sync wire/journal foundation and
regression source; that is not production domain integration. The wire review fix
changes only the Swift wire/tests and backend migration/docs. No Xcode, website,
provider configuration, secrets, or production resources were changed. No commands,
network requests, builds, or test execution were performed for that fix.

## Contents

- [Migration](migrations/202610190001_sync_foundation.sql): transactional, private
  storage + RLS + authenticated-only public RPC entry points.
- [Wire contract](CONTRACT.md): exact arguments, envelopes, conflicts, cursor rules,
  and limitations; authoritative for independent iOS/Android integration.
- [Security regression](tests/security_regression.sql): disposable fixture test in
  one rollback-contained transaction, including two UIDs and anonymous access.
- [Concurrency schedule](tests/concurrency_regression.sql): manually selected
  two-session sections, plus required race variants; NOT a one-shot test file.

## Manual provisioning (no automated deployment or rollback recipe)

1. Obtain operator approval for separate staging and production Supabase projects.
   Select region/data residency, spend alerts, backup/PITR plan, retention,
   restore ownership, and audit/incident procedures. Do not reuse development
   provider quotas or assume any golf data redistribution rights.
2. Confirm final native bundle/package identifiers and app/universal link domains.
   Configure Apple native App ID plus grouped Services ID for Android browser flow,
   Google platform OAuth clients, and email magic links with verified SMTP/domain,
   delivery monitoring, rate/abuse limits and strict redirect allowlists. Disable
   unneeded providers/anonymous sign-ins. Assign Apple browser-secret renewal
   ownership (at most six-month lifetime). Test identity/provider-linking behavior;
   same email/private relay does not imply the same account.
3. Keep provider secrets, SMTP credentials, service-role keys, and database
   credentials in the operator's server-side secret manager. Never paste them into
   SQL source, terminal logs, chat, app bundles, fixtures, or this repository.
   Only the project URL/publishable key belongs in clients, along with session
   tokens protected by native secure storage. A publishable key is not user auth.
4. Review SQL and this contract with the database/security owner. Prerequisites:
   Supabase PostgreSQL with `auth.users`, `auth.uid()`, roles `anon`,
   `authenticated`, `service_role`, and a trusted migration owner able to create
   schemas/functions/policies and bypass table RLS. Function ownership must remain
   that trusted non-client role. No additional extensions are required.
5. Manually execute the migration file in its entirety in staging using approved
   SQL tooling as the migration owner. It is a single BEGIN/COMMIT transaction;
   failures must be investigated, not partially continued. The file is deliberately
   not rerunnable (`IF NOT EXISTS` must not conceal schema drift). Record its
   checksum, operator, project, database version and execution outcome in the
   deployment ledger. Do not claim it has been applied based on source existence.
6. Expose only the usual `public` API schema; never add `pintheory_sync` to exposed
   schemas. Ensure `authenticated` has ordinary `public` schema usage. Check
   actual function ACLs: only authenticated may execute these two RPCs (trusted
   owner/superuser inherently privileged). API roles, including service_role, have
   no direct private table/schema privileges. Confirm project-specific default
   grants haven't created an unintended alternate access path. Keep Realtime off
   for private tables; no Realtime subscription is required for correctness.
7. Only after separate authorization, manually execute the security regression in
   disposable staging with stop-on-first-error and PL/pgSQL assertions enabled.
   It rolls back fixtures; never run against production. Run the concurrency file
   as labelled selected sections in separate SQL sessions; it persists a test UID
   and must use a disposable project. Run every documented race variant, not only
   the first one. Also test RPCs through real Supabase Auth/PostgREST user JWTs;
   SQL role/claim simulation is not provider/JWT validation.
8. Review results, limits and restore drill before separate production approval.
   Promote the identical reviewed migration manually, record the ledger entry,
   verify ACL/RLS/RPC behavior, and monitor failures/storage. No destructive down
   migration is supplied. Correct deployed issues with reviewed forward-only
   migrations and a rehearsed backup/restore procedure, not DROP/recreate or a
   rollback that erases queued user data.

## Security / concurrency design review

- UID derives from `auth.uid()` only. There is no owner argument or owner-changing
  path. All data access predicates include that UID; schema-qualified references
  and fixed `search_path = pg_catalog` protect SECURITY DEFINER RPCs.
- Private tables enable RLS with UID SELECT policies but grant no direct access.
  No client INSERT/UPDATE/DELETE policies exist. API function PUBLIC/anon/service
  grants are explicitly revoked; only authenticated EXECUTE is granted.
- One locked account row serializes every mutation, receipt replay and sequence
  allocation for the UID. Records, event, sequence and receipt commit atomically.
  Concurrent different users do not share that lock. Revision mismatch and source
  uniqueness conflict commit receipts without changing records or sequences.
- History snapshots and full request/response receipts reject UPDATE/DELETE using
  triggers, even for ordinary owner DML. API roles cannot TRUNCATE. This is not
  tamper-proof against a database superuser capable of altering/disabling triggers.
- High-water-mark pagination reads immutable bounded snapshots, not mutable rows
  ordered by timestamps. Default READ COMMITTED is assumed. Higher-isolation
  serialization failures need whole-request retries with the same mutation ID.
- Account state is checked under the mutation lock before receipt lookup/write.
  Foreign keys prevent lazy state creation for a removed auth UID. Blocked accounts
  cannot pull, replay, or write via these RPCs.

## Deliberate blockers and risks

1. **Payload allowlisting is NOT complete.** This generic backend checks kind,
   version, object/JSONB size, recursive exact-decimal bounds (magnitude <= 10^20,
   at most 16 fractional places), and the exact optional handicap source UUID key.
   It does not approve any example payload as a production DTO, prohibit nested
   preferences/geometry, enforce domain-specific units/ranges, enforce custom relationships, or
   validate foreign payload references. Typed per-kind domain schemas and tests
   must precede production upload. API ingress body/depth/rate limits and abuse
   protection also need validation; a JSONB size guard runs after parsing, not at
   the network boundary. A 200-event page can approach 13 MiB plus envelopes;
   benchmark and lower page limits for mobile.
2. Define explicit fact-vs-preference client allowlists. Sync saved content only;
   exclude active drafts, UI preferences, recent selections, provider/downloaded
   catalogues, full course geometry, weather/terrain caches and quota ledgers.
   Played-round DTOs need a lightweight licensed scorecard snapshot and
   geometry-independent history. Preserve unit semantics. HCP import stays an
   explicit client action; saved rounds never automatically create handicap rows.
3. iOS/Android stable IDs, account-isolated persistence, durable write-ahead outbox,
   conflict storage/UI, bootstrap gating, secure session restore, sign-in methods,
   logout cancellation and stale callback isolation are not implemented here.
   No automatic adoption of old unowned local stores; quarantine pending explicit
   user action. First login requires connectivity; offline access after prior
   authentication is a client workflow, not proof an expired JWT is valid.
4. **Deletion is a release blocker, not a fake endpoint.** A real privileged,
   recent-authenticated resumable service must first upsert/commit the blocking
   account state, revoke sessions/provider grants (Apple included where required),
   then erase user data/Auth identity with auditable retry semantics and disclosed
   backup retention. History immutability triggers deliberately block cascading
   deletion once history exists: even `auth.users` deletion will fail until a
   reviewed narrowly privileged purge mechanism is designed. Do not globally
   disable triggers or advertise delete-account completion. Keep account state
   blocked throughout failures. Do not remove state while an auth UID can still
   authenticate and lazily reopen it. No client state-reset or unblock RPC exists.
5. Events, receipts (including losing payloads), and tombstones are retained
   indefinitely, with cost/privacy implications. No GC/compaction or full-rebootstrap
   watermark protocol exists. Add reviewed retention and account erasure handling
   before production scale. Source-link uniqueness includes tombstones but links
   can be explicitly changed/removed by CAS; permanent provenance is not enforced.
6. Lazy RPC account creation is not an entitlement/admission check. Configure
   signup policy/abuse prevention separately. Row locks cannot retract a read
   already in flight or a write ordered before the block. Never trust client-set
   JWT claims outside trusted SQL test sessions; actual Auth/JWT validation is a
   Supabase gateway prerequisite.
7. No provider login, network failure, two-device/offline crash scenario, SQL
   function compilation, RLS execution, or concurrency race has been run here.
   Source review and local whitespace checks are not deployment validation.
   Privacy policy/store declarations, retention, support, monitoring, backups,
   auth review and App Store account/deletion compliance remain open release gates.

## Wire review corrections / pending regression checks

The original migration remains **undeployed** and was amended in place. Do not
edit an already deployed copy: use a reviewed forward migration and audit existing
records, immutable events and receipts for out-of-domain numbers first. A payload
accepted by SQL must remain decodable and durably applicable on every client.

- SQL now validates every nested numeric value using exact `numeric` comparison
  and `round(value, 16)`, before account/receipt/event writes and in the records
  constraint. No float conversion, numeric-string conversion, or bool coercion.
- Swift uses matching Decimal checks at decode, encode and recursive payload
  validation, including directly constructed values before journal persistence.
  Exact domain values, including 16-place coordinates, survive without rounding.
- The 65,536-byte JSONB-text limit belongs to SQL only. Swift no longer re-encodes
  records to impose a different 65,536-byte limit on mutations, receipts, pulls or
  journal reopen. Slash-heavy accepted payloads can exceed that many bytes in a
  Swift journal without poisoning cursor progress. Oversized local puts can still
  be queued and rejected by SQL; pending/error handling must not claim cloud save.
- No new transport-size bound is implied. The current foundation transport buffers
  a response before decoding and has no explicit response-byte cap; ingress,
  response, nesting and local-disk abuse limits require separate reviewed work.

Regression source was added to the existing Swift sync test suite for numeric
boundaries, nested invalid/directly constructed numbers, unchanged journal bytes
on invalid pages, exact decimal round trips, and a 65,536-byte slash payload through
receipt acknowledgement, pull, reopen and subsequent cursor advancement. Tests,
builds and SQL execution were **not run** for this review fix.

After authorization, extend/run disposable staging SQL regressions with this matrix:

| Case (also nested inside object -> array -> object)                                                        | Expected                                 |
| ---------------------------------------------------------------------------------------------------------- | ---------------------------------------- |
| `0`, `-0`, `true`, `false`, JSON null, empty objects/arrays                                                | Accepted, types preserved                |
| `1e20`, `-1e20`, `1e-16`, `-1e-16`, `1.23000000000000000`                                                  | Accepted                                 |
| `9007199254740993.125`, `57.6234567890123456`, `99999999999999999999.9999999999999999` and their negatives | Accepted exactly                         |
| `1e200`, `-1e200`, `100000000000000000001`, `-100000000000000000001`                                       | SQLSTATE `22023`                         |
| `1e-17`, `-1e-17`, `57.12345678901234567`                                                                  | SQLSTATE `22023`                         |
| Object with `label` containing 65,523 slashes (65,536 JSONB-text bytes)                                    | Accepted; feed/receipt payload preserved |
| Same object with 65,524 slashes (65,537 JSONB-text bytes)                                                  | SQLSTATE `22023`                         |

For every rejected RPC assert no receipt/event/sequence change, including a losing
CAS request; verify the record CHECK also rejects out-of-domain direct owner DML.
For accepted mutations assert exact payload equality in record, receipt and event,
then replay the identical mutation ID and pull the bounded feed. These are pending
acceptance checks, not claims that database regression coverage has executed.
