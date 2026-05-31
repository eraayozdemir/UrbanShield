-- Volunteer cancellation before response start + suspend cleanup.
--
-- Run after the request capacity / admin suspension SQL files.
-- This keeps assignment state and profile availability consistent when:
-- - a volunteer cancels before pressing Start Response
-- - an admin suspends a user who currently has active volunteer work

create or replace function public.recalculate_help_request_after_assignment_change(
    p_request_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    next_assignment public.help_request_volunteers%rowtype;
begin
    select *
    into next_assignment
    from public.help_request_volunteers
    where request_id = p_request_id
      and status in ('in_progress', 'confirmed')
    order by
      case when status = 'in_progress' then 0 else 1 end,
      updated_at desc
    limit 1;

    if next_assignment.id is null then
        update public.help_requests
        set volunteer_id = null,
            status = case
                when status in ('confirmed', 'in_progress') then 'open'
                else status
            end,
            updated_at = now()
        where id = p_request_id
          and status in ('open', 'confirmed', 'in_progress');
    else
        update public.help_requests
        set volunteer_id = next_assignment.volunteer_id,
            status = next_assignment.status,
            confirmed_at = coalesce(confirmed_at, next_assignment.accepted_at),
            updated_at = now()
        where id = p_request_id
          and status in ('open', 'confirmed', 'in_progress');
    end if;
end;
$$;

create or replace function public.release_volunteer_if_no_active_tasks(
    p_volunteer_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if p_volunteer_id is null then
        return;
    end if;

    if exists (
        select 1
        from public.help_request_volunteers
        where volunteer_id = p_volunteer_id
          and status in ('confirmed', 'in_progress')
    ) then
        return;
    end if;

    perform set_config('app.profile_automation', 'volunteer_release', true);

    update public.profiles
    set role = case
            when role = 'volunteer' then 'citizen'
            else role
        end,
        availability_status = case
            when coalesce(is_suspended, false) then 'offline'
            else 'available'
        end
    where id = p_volunteer_id
      and (
          role = 'volunteer'
          or (
              coalesce(is_suspended, false)
              and availability_status is distinct from 'offline'
          )
          or (
              not coalesce(is_suspended, false)
              and availability_status is distinct from 'available'
          )
      );
end;
$$;

create or replace function public.cancel_my_confirmed_volunteer_task(
    p_request_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    active_assignment_id uuid;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to cancel this task.';
    end if;

    if exists (
        select 1
        from public.profiles
        where id = auth.uid()
          and coalesce(is_suspended, false)
    ) then
        raise exception 'This account is suspended.';
    end if;

    select id
    into active_assignment_id
    from public.help_request_volunteers
    where request_id = p_request_id
      and volunteer_id = auth.uid()
      and status = 'confirmed'
    order by updated_at desc
    limit 1
    for update;

    if active_assignment_id is null then
        raise exception 'Only confirmed volunteer tasks can be cancelled before response starts.';
    end if;

    update public.help_request_volunteers
    set status = 'cancelled',
        updated_at = now()
    where id = active_assignment_id;

    perform public.recalculate_help_request_after_assignment_change(p_request_id);
    perform public.release_volunteer_if_no_active_tasks(auth.uid());
end;
$$;

grant execute on function public.cancel_my_confirmed_volunteer_task(uuid)
to authenticated;

create or replace function public.set_profile_suspension(
    p_user_id uuid,
    p_is_suspended boolean
)
returns setof public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
    requester_role text;
    affected_request_ids uuid[];
    affected_request_id uuid;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to manage users.';
    end if;

    select role
    into requester_role
    from public.profiles
    where id = auth.uid()
      and not coalesce(is_suspended, false);

    if requester_role is distinct from 'admin' then
        raise exception 'Only admins can suspend or reactivate accounts.';
    end if;

    if p_user_id = auth.uid() then
        raise exception 'You cannot suspend your own admin account from the app.';
    end if;

    if p_is_suspended then
        select coalesce(array_agg(distinct request_id), array[]::uuid[])
        into affected_request_ids
        from public.help_request_volunteers
        where volunteer_id = p_user_id
          and status in ('confirmed', 'in_progress');

        update public.help_request_volunteers
        set status = 'cancelled',
            updated_at = now()
        where volunteer_id = p_user_id
          and status in ('confirmed', 'in_progress');

        foreach affected_request_id in array affected_request_ids loop
            perform public.recalculate_help_request_after_assignment_change(affected_request_id);
        end loop;

        perform set_config('app.profile_automation', 'volunteer_release', true);

        update public.profiles
        set is_suspended = true,
            role = case
                when role = 'volunteer' then 'citizen'
                else role
            end,
            availability_status = 'offline'
        where id = p_user_id;
    else
        update public.profiles
        set is_suspended = false,
            availability_status = case
                when availability_status = 'offline' then 'available'
                else availability_status
            end
        where id = p_user_id;
    end if;

    return query
    select *
    from public.profiles
    where id = p_user_id;
end;
$$;

grant execute on function public.set_profile_suspension(uuid, boolean)
to authenticated;
