-- Keep help request severity on one source of truth: urgency_level.
-- Run after the existing coordinator and volunteer-capacity SQL files.

create or replace function public.prevent_coordinator_non_priority_updates()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    requester_role text;
begin
    select role
    into requester_role
    from public.profiles
    where id = auth.uid();

    if requester_role in ('coordinator', 'admin') then
        if new.id is distinct from old.id
           or new.citizen_id is distinct from old.citizen_id
           or new.request_type is distinct from old.request_type
           or new.description is distinct from old.description
           or new.urgency_level is distinct from old.urgency_level
           or new.latitude is distinct from old.latitude
           or new.longitude is distinct from old.longitude
           or new.created_at is distinct from old.created_at then
            raise exception 'Coordinators can only update status or assignment fields.';
        end if;

        if new.status not in ('open', 'confirmed', 'in_progress', 'completed', 'cancelled') then
            raise exception 'Invalid request status.';
        end if;

        if new.status is distinct from old.status then
            if not (
                (old.status in ('open', 'confirmed') and new.status = 'confirmed')
                or (old.status = 'confirmed' and new.status in ('in_progress', 'cancelled'))
                or (old.status = 'in_progress' and new.status in ('completed', 'cancelled'))
                or (old.status = 'open' and new.status = 'cancelled')
            ) then
                raise exception 'Invalid coordinator status transition.';
            end if;
        end if;
    end if;

    return new;
end;
$$;

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

    if tg_op = 'INSERT' and request_record.status not in ('open', 'confirmed') then
        raise exception 'This request is no longer accepting volunteers.';
    end if;

    if tg_op = 'UPDATE' and request_record.status not in ('open', 'confirmed', 'in_progress') then
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

-- Keep the volunteer acceptance RPC aligned with the single urgency field.
-- Capacity is enforced by enforce_help_request_volunteer_capacity() on insert.
create or replace function public.accept_help_request_as_volunteer(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    request_record public.help_requests%rowtype;
    requester_profile public.profiles%rowtype;
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

    if request_record.status not in ('open', 'confirmed') then
        raise exception 'This request is no longer accepting volunteers.';
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

    if exists (
        select 1
        from public.help_request_volunteers
        where request_id = p_request_id
          and volunteer_id = auth.uid()
          and status in ('confirmed', 'in_progress', 'completed')
    ) then
        raise exception 'You have already accepted this request.';
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
      and status in ('open', 'confirmed');

    perform set_config('app.profile_automation', 'volunteer_acceptance', true);

    update public.profiles
    set role = 'volunteer',
        availability_status = 'busy'
    where id = auth.uid();
end;
$$;

grant execute on function public.accept_help_request_as_volunteer(uuid) to authenticated;

drop policy if exists "coordinators can update request priority" on public.help_requests;

alter table public.help_requests
drop column if exists priority_level;
