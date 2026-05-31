-- Critical capacity fix for in-progress requests + citizen update guard.
--
-- Run this after the existing volunteer capacity / final stabilization SQL.
-- Purpose:
-- - Critical requests can have 3 active volunteers.
-- - If one volunteer starts response, the request becomes in_progress, but the
--   remaining capacity should still be available to other matching volunteers.
-- - Citizens should not change urgency from the Update Request flow; coordinator
--   priority/urgency management stays separate.

create or replace function public.help_request_volunteer_capacity(p_priority text)
returns integer
language sql
immutable
as $$
    select case
        when coalesce(p_priority, 'medium') = 'critical' then 3
        else 1
    end;
$$;

create or replace function public.enforce_help_request_volunteer_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    request_record public.help_requests%rowtype;
    active_count integer;
    capacity integer;
begin
    if new.status not in ('confirmed', 'in_progress') then
        return new;
    end if;

    select *
    into request_record
    from public.help_requests
    where id = new.request_id
    for update;

    if request_record.id is null then
        raise exception 'Request could not be found.';
    end if;

    if tg_op = 'INSERT'
       and request_record.status not in ('open', 'confirmed', 'in_progress') then
        raise exception 'This request is no longer accepting volunteers.';
    end if;

    if tg_op = 'UPDATE'
       and request_record.status not in ('open', 'confirmed', 'in_progress') then
        raise exception 'This request is no longer accepting volunteers.';
    end if;

    if exists (
        select 1
        from public.help_request_volunteers
        where request_id = new.request_id
          and volunteer_id = new.volunteer_id
          and status in ('confirmed', 'in_progress', 'completed')
          and (tg_op = 'INSERT' or id <> old.id)
    ) then
        raise exception 'This volunteer has already accepted this request.';
    end if;

    select count(*)
    into active_count
    from public.help_request_volunteers
    where request_id = new.request_id
      and status in ('confirmed', 'in_progress')
      and (tg_op = 'INSERT' or id <> old.id);

    capacity := public.help_request_volunteer_capacity(request_record.urgency_level);

    if active_count >= capacity then
        raise exception 'This request already has the maximum number of active volunteers for its urgency.';
    end if;

    return new;
end;
$$;

drop trigger if exists enforce_help_request_volunteer_capacity_trigger
on public.help_request_volunteers;

create trigger enforce_help_request_volunteer_capacity_trigger
before insert or update of status, request_id, volunteer_id
on public.help_request_volunteers
for each row
execute function public.enforce_help_request_volunteer_capacity();

create or replace function public.accept_help_request_as_volunteer(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    request_record public.help_requests%rowtype;
    requester_profile public.profiles%rowtype;
    active_count integer;
    capacity integer;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to accept a request.';
    end if;

    select *
    into requester_profile
    from public.profiles
    where id = auth.uid()
    for update;

    if requester_profile.id is null then
        raise exception 'Profile could not be found.';
    end if;

    if coalesce(requester_profile.is_suspended, false) then
        raise exception 'This account is suspended.';
    end if;

    if requester_profile.availability_status is distinct from 'available' then
        raise exception 'You must be available before accepting a request.';
    end if;

    if exists (
        select 1
        from public.help_request_volunteers
        where volunteer_id = auth.uid()
          and status in ('confirmed', 'in_progress')
    ) then
        raise exception 'Complete your active volunteer task before accepting another request.';
    end if;

    select *
    into request_record
    from public.help_requests
    where id = p_request_id
    for update;

    if request_record.id is null then
        raise exception 'Request could not be found.';
    end if;

    if request_record.citizen_id = auth.uid() then
        raise exception 'You cannot volunteer for your own request.';
    end if;

    if request_record.status not in ('open', 'confirmed', 'in_progress') then
        raise exception 'This request is no longer accepting volunteers.';
    end if;

    if exists (
        select 1
        from public.help_request_volunteers
        where request_id = p_request_id
          and volunteer_id = auth.uid()
          and status in ('confirmed', 'in_progress', 'completed')
    ) then
        raise exception 'You have already accepted this request.';
    end if;

    select count(*)
    into active_count
    from public.help_request_volunteers
    where request_id = p_request_id
      and status in ('confirmed', 'in_progress');

    capacity := public.help_request_volunteer_capacity(request_record.urgency_level);

    if active_count >= capacity then
        raise exception 'This request already has the maximum number of active volunteers for its urgency.';
    end if;

    insert into public.help_request_volunteers (
        request_id,
        volunteer_id,
        status,
        accepted_at,
        updated_at
    )
    values (
        p_request_id,
        auth.uid(),
        'confirmed',
        now(),
        now()
    );

    update public.help_requests
    set volunteer_id = coalesce(volunteer_id, auth.uid()),
        status = case
            when status = 'open' then 'confirmed'
            else status
        end,
        confirmed_at = coalesce(confirmed_at, now()),
        updated_at = now()
    where id = p_request_id
      and status in ('open', 'confirmed', 'in_progress');

    perform set_config('app.profile_automation', 'volunteer_acceptance', true);

    update public.profiles
    set role = 'volunteer',
        availability_status = 'busy'
    where id = auth.uid();
end;
$$;

grant execute on function public.accept_help_request_as_volunteer(uuid)
to authenticated;

create or replace function public.prevent_citizen_request_urgency_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    requester_role text;
begin
    if auth.uid() is null then
        return new;
    end if;

    select role
    into requester_role
    from public.profiles
    where id = auth.uid();

    if old.citizen_id = auth.uid()
       and coalesce(requester_role, 'citizen') not in ('coordinator', 'admin')
       and new.urgency_level is distinct from old.urgency_level then
        raise exception 'Citizens cannot change request urgency after creation.';
    end if;

    return new;
end;
$$;

drop trigger if exists prevent_citizen_request_urgency_update_trigger
on public.help_requests;

create trigger prevent_citizen_request_urgency_update_trigger
before update of urgency_level
on public.help_requests
for each row
execute function public.prevent_citizen_request_urgency_update();
