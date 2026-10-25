-- ONE-TIME OPERATOR RECOVERY, not a migration and not an automatic restore policy.
-- Run in the intended Supabase SQL Editor as postgres only after installing
-- the corrected app on BOTH devices. Do not run older app builds during recovery.
-- Restores only the single retained handicap payload for the account confirmed
-- in the support conversation. It does not upload the original device's local
-- version, resolve client journal conflicts, or change other accounts.
-- Uses the normal CAS RPC, so restoration emits an event and retains history.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $$
declare
    v_owner constant uuid := '89510e2a-df18-45bc-9748-641dfcf312f7';
    v_state text;
    v_count integer;
    v_record pintheory_sync.records%rowtype;
    v_result jsonb;
begin
    select state into v_state from pintheory_sync.accounts
    where user_id = v_owner for update;
    if v_state is distinct from 'active' then
        raise exception 'Recovery stopped: expected an existing active sync account';
    end if;

    select count(*) into v_count from pintheory_sync.records
    where user_id = v_owner and kind = 'handicap_round';
    if v_count <> 1 then
        raise exception 'Recovery stopped: expected exactly one handicap record, found %', v_count;
    end if;
    select * into strict v_record from pintheory_sync.records
    where user_id = v_owner and kind = 'handicap_round';
    if v_record.deleted_at is null then
        raise notice 'The handicap record is already active; no changes made';
        return;
    end if;
    if pintheory_sync.payload_valid(v_record.kind, v_record.payload) is distinct from true then
        raise exception 'Recovery stopped: retained handicap payload is invalid';
    end if;

    -- Transaction-local Auth claims for the trusted operator; never expose an
    -- owner-selectable restoration endpoint to application clients.
    perform pg_catalog.set_config('request.jwt.claim.sub', v_owner::text, true);
    perform pg_catalog.set_config('request.jwt.claims',
        pg_catalog.jsonb_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);
    v_result := public.pintheory_sync_mutate(
        pg_catalog.gen_random_uuid(), v_record.record_id, v_record.kind,
        v_record.revision::text, 'put', v_record.schema_version, v_record.payload);
    if v_result->>'status' is distinct from 'applied' then
        raise exception 'Recovery stopped: restoration was not applied';
    end if;
    raise notice 'Restored one handicap entry; its original record identity and history are preserved';
end;
$$;

commit;