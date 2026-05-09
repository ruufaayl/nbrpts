-- Phase 3: B-Form lifecycle functions.
--
-- authorize_bform — officer marks an existing B-Form as authorized,
--                   moves notification from QUEUED to SENT.
-- reissue_bform   — generates a new version, marks the prior current
--                   version as is_current = false, queues a new SMS.

-- ---------------------------------------------------------------------------
-- authorize_bform
-- ---------------------------------------------------------------------------
create or replace function public.authorize_bform(
  p_bform_id   uuid,
  p_officer_id uuid
)
returns public.bform
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bform     public.bform;
  v_start     timestamptz := clock_timestamp();
begin
  -- Set actor for the audit trigger.
  perform set_config('app.actor_type', 'NADRA_OFFICER', true);
  perform set_config('app.actor_id',   p_officer_id::text, true);

  update public.bform
     set authorized_at = now()
   where bform_id = p_bform_id
     and authorized_at is null
   returning * into v_bform;

  if v_bform is null then
    raise exception 'B-Form % not found or already authorized', p_bform_id;
  end if;

  -- Promote the matching queued SMS to SENT (mocked).
  update public.notifications
     set status = 'SENT', sent_at = now(),
         body = replace(body, 'You will receive another message when it is authorized for collection.',
                              'It is now ready for collection at your nearest NADRA office.')
   where related_table = 'bform'
     and related_id    = v_bform.bform_number
     and status        = 'QUEUED';

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned)
  values ('authorize_bform',
          'update bform set authorized_at = now() where bform_id = $1',
          jsonb_build_object('bform_id', p_bform_id, 'officer_id', p_officer_id),
          extract(epoch from (clock_timestamp() - v_start)) * 1000,
          1);

  return v_bform;
end$$;

grant execute on function public.authorize_bform(uuid, uuid) to anon, authenticated;

comment on function public.authorize_bform(uuid, uuid) is
  'Officer authorizes a B-Form for collection. Sets authorized_at and promotes the queued SMS to SENT.';

-- ---------------------------------------------------------------------------
-- reissue_bform
-- ---------------------------------------------------------------------------
create or replace function public.reissue_bform(
  p_child_id      uuid,
  p_officer_id    uuid,
  p_reason        text
)
returns public.bform
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prev_version  integer;
  v_new_number    text;
  v_new_bform     public.bform;
  v_mother_phone  text;
  v_start         timestamptz := clock_timestamp();
begin
  if p_reason is null or length(trim(p_reason)) = 0 then
    raise exception 'Reissue reason is required';
  end if;

  perform set_config('app.actor_type', 'NADRA_OFFICER', true);
  perform set_config('app.actor_id',   p_officer_id::text, true);

  -- Lock the prior current row.
  select version into v_prev_version
    from public.bform
   where child_id = p_child_id and is_current = true
   for update;

  if v_prev_version is null then
    raise exception 'No current B-Form found for child %', p_child_id;
  end if;

  -- Mark prior version as not current.
  update public.bform
     set is_current = false
   where child_id = p_child_id and is_current = true;

  -- Mint new number and insert new version.
  v_new_number := 'BF-' || to_char(now(), 'YYYY') || '-' ||
                  lpad(nextval('public.bform_seq')::text, 8, '0');

  insert into public.bform
    (bform_number, child_id, issued_by, version, is_current,
     reissue_reason, authorized_at)
  values
    (v_new_number, p_child_id, p_officer_id,
     v_prev_version + 1, true, p_reason, now())
  returning * into v_new_bform;

  -- Queue an SMS to the primary mother.
  select pg.contact_number
    into v_mother_phone
    from public.child_guardian cg
    join public.parent_guardian pg on pg.guardian_id = cg.guardian_id
   where cg.child_id = p_child_id
     and cg.relationship_type = 'MOTHER'
   limit 1;

  if v_mother_phone is not null then
    insert into public.notifications
      (recipient_type, recipient_contact, channel, body,
       status, related_table, related_id, sent_at)
    values
      ('PARENT', v_mother_phone, 'SMS',
       'Your child''s B-Form has been reissued as ' || v_new_number ||
       ' (reason: ' || p_reason || '). Ready for collection at your nearest NADRA office.',
       'SENT', 'bform', v_new_number, now());
  end if;

  insert into public.query_log (caller, sql_text, params, duration_ms, rows_returned)
  values ('reissue_bform',
          'update bform set is_current=false, insert new version, queue notification',
          jsonb_build_object('child_id', p_child_id, 'officer_id', p_officer_id, 'reason', p_reason),
          extract(epoch from (clock_timestamp() - v_start)) * 1000,
          1);

  return v_new_bform;
end$$;

grant execute on function public.reissue_bform(uuid, uuid, text) to anon, authenticated;

comment on function public.reissue_bform(uuid, uuid, text) is
  'Versioned B-Form reissuance. Marks prior version not current, inserts new version, queues SMS.';
