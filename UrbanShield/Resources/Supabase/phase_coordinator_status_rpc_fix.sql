-- Coordinator status update RPC.
--
-- Run this after the Phase 3 coordinator SQL and volunteer release SQL.
-- It avoids client-side RLS failures when coordinators/admins move requests to
-- in_progress, completed, or cancelled, and keeps volunteer assignments synced.

create or replace function public.coordinator_update_help_request_status(
    p_request_id uuid,
    p_status text
)
returns setof public.help_requests
language plpgsql
security definer
set search_path = public
as $$
declare
    requester_role text;
    request_record public.help_requests%rowtype;
    now_value timestamptz := now();
    assignment_record record;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to update request status.';
    end if;

    select role
    into requester_role
    from public.profiles
    where id = auth.uid()
      and not coalesce(is_suspended, false);

    if requester_role not in ('coordinator', 'admin') then
        raise exception 'Only coordinators can update request status.';
    end if;

    if p_status not in ('open', 'confirmed', 'in_progress', 'completed', 'cancelled') then
        raise exception 'Invalid request status.';
    end if;

    select *
    into request_record
    from public.help_requests
    where id = p_request_id
    for update;

    if request_record.id is null then
        raise exception 'Request could not be found.';
    end if;

    if not (
        (request_record.status = 'open' and p_status = 'cancelled')
        or (request_record.status in ('open', 'confirmed') and p_status = 'confirmed')
        or (request_record.status = 'confirmed' and p_status in ('in_progress', 'cancelled'))
        or (request_record.status = 'in_progress' and p_status in ('completed', 'cancelled'))
    ) then
        raise exception 'Invalid coordinator status transition.';
    end if;

    update public.help_requests
    set status = p_status,
        completed_at = case
            when p_status = 'completed' then now_value
            when p_status in ('open', 'confirmed', 'in_progress') then null
            else completed_at
        end,
        updated_at = now_value
    where id = p_request_id;

    if p_status = 'in_progress' then
        update public.help_request_volunteers
        set status = 'in_progress',
            started_at = coalesce(started_at, now_value),
            updated_at = now_value
        where request_id = p_request_id
          and status in ('confirmed', 'in_progress');
    elsif p_status = 'completed' then
        update public.help_request_volunteers
        set status = 'completed',
            completed_at = coalesce(completed_at, now_value),
            updated_at = now_value
        where request_id = p_request_id
          and status in ('confirmed', 'in_progress');
    elsif p_status = 'cancelled' then
        update public.help_request_volunteers
        set status = 'cancelled',
            updated_at = now_value
        where request_id = p_request_id
          and status in ('confirmed', 'in_progress');
    end if;

    if p_status in ('completed', 'cancelled') then
        for assignment_record in
            select distinct volunteer_id
            from public.help_request_volunteers
            where request_id = p_request_id
        loop
            perform public.release_volunteer_if_no_active_tasks(assignment_record.volunteer_id);
        end loop;
    end if;

    return query
    select *
    from public.help_requests
    where id = p_request_id;
end;
$$;

grant execute on function public.coordinator_update_help_request_status(uuid, text)
to authenticated;

create or replace function public.coordinator_assign_volunteer_to_request(
    p_request_id uuid,
    p_volunteer_id uuid
)
returns setof public.help_requests
language plpgsql
security definer
set search_path = public
as $$
declare
    requester_role text;
    request_record public.help_requests%rowtype;
    volunteer_record public.profiles%rowtype;
    active_count integer;
    capacity integer;
    now_value timestamptz := now();
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to assign volunteers.';
    end if;

    select role
    into requester_role
    from public.profiles
    where id = auth.uid()
      and not coalesce(is_suspended, false);

    if requester_role not in ('coordinator', 'admin') then
        raise exception 'Only coordinators can assign volunteers.';
    end if;

    select *
    into request_record
    from public.help_requests
    where id = p_request_id
    for update;

    if request_record.id is null then
        raise exception 'Request could not be found.';
    end if;

    if request_record.status not in ('open', 'confirmed', 'in_progress') then
        raise exception 'This request is no longer accepting volunteers.';
    end if;

    if request_record.citizen_id = p_volunteer_id then
        raise exception 'A citizen cannot be assigned to their own request.';
    end if;

    select *
    into volunteer_record
    from public.profiles
    where id = p_volunteer_id
    for update;

    if volunteer_record.id is null then
        raise exception 'Volunteer profile could not be found.';
    end if;

    if coalesce(volunteer_record.is_suspended, false) then
        raise exception 'This volunteer account is suspended.';
    end if;

    if volunteer_record.availability_status is distinct from 'available' then
        raise exception 'This volunteer is not available.';
    end if;

    if not (
        request_record.request_type = 'other'
        or (request_record.request_type = 'earthquake' and coalesce(volunteer_record.volunteer_skills, array[]::text[]) && array['search_rescue', 'medical', 'logistics', 'shelter'])
        or (request_record.request_type = 'fire' and coalesce(volunteer_record.volunteer_skills, array[]::text[]) && array['fire_response', 'medical', 'search_rescue'])
        or (request_record.request_type = 'flood' and coalesce(volunteer_record.volunteer_skills, array[]::text[]) && array['flood_rescue', 'transport', 'search_rescue', 'medical'])
        or (request_record.request_type = 'accident' and coalesce(volunteer_record.volunteer_skills, array[]::text[]) && array['medical', 'transport', 'search_rescue'])
        or (request_record.request_type = 'medical' and coalesce(volunteer_record.volunteer_skills, array[]::text[]) && array['medical', 'transport'])
    ) then
        raise exception 'This volunteer does not match the request type.';
    end if;

    if exists (
        select 1
        from public.help_request_volunteers
        where volunteer_id = p_volunteer_id
          and status in ('confirmed', 'in_progress')
    ) then
        raise exception 'This volunteer already has an active task.';
    end if;

    if exists (
        select 1
        from public.help_request_volunteers
        where request_id = p_request_id
          and volunteer_id = p_volunteer_id
          and status in ('confirmed', 'in_progress', 'completed')
    ) then
        raise exception 'This volunteer is already assigned to this request.';
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
        p_volunteer_id,
        'confirmed',
        now_value,
        now_value
    );

    update public.help_requests
    set volunteer_id = coalesce(volunteer_id, p_volunteer_id),
        status = case
            when status = 'open' then 'confirmed'
            else status
        end,
        confirmed_at = coalesce(confirmed_at, now_value),
        updated_at = now_value
    where id = p_request_id
      and status in ('open', 'confirmed', 'in_progress');

    perform set_config('app.profile_automation', 'coordinator_assignment', true);

    update public.profiles
    set role = 'volunteer',
        availability_status = 'busy'
    where id = p_volunteer_id;

    return query
    select *
    from public.help_requests
    where id = p_request_id;
end;
$$;

grant execute on function public.coordinator_assign_volunteer_to_request(uuid, uuid)
to authenticated;
