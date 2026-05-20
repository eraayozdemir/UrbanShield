-- Final stabilization: admin account suspension.


alter table public.profiles
add column if not exists is_suspended boolean not null default false;

create index if not exists profiles_is_suspended_idx
on public.profiles(is_suspended);

create or replace function public.current_app_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
    select case
        when coalesce(is_suspended, false) then 'suspended'
        else role
    end
    from public.profiles
    where id = auth.uid()
    limit 1
$$;

create or replace function public.prevent_invalid_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    requester_role text;
    requester_is_suspended boolean;
begin
    if current_setting('app.profile_automation', true) in ('volunteer_acceptance', 'volunteer_release') then
        return new;
    end if;

    select role, coalesce(is_suspended, false)
    into requester_role, requester_is_suspended
    from public.profiles
    where id = auth.uid();

    if requester_is_suspended then
        raise exception 'This account is suspended.';
    end if;

    if requester_role = 'admin' then
        return new;
    end if;

    if new.is_suspended is distinct from old.is_suspended then
        raise exception 'Only admins can suspend or reactivate accounts.';
    end if;

    if requester_role = 'coordinator' then
        if new.email is distinct from old.email
           or new.full_name is distinct from old.full_name
           or new.created_at is distinct from old.created_at
           or new.volunteer_skills is distinct from old.volunteer_skills then
            raise exception 'Coordinators can only update volunteer availability for assignments.';
        end if;

        if new.role = 'volunteer'
           and new.availability_status = 'busy'
           and exists (
               select 1
               from public.help_request_volunteers
               where volunteer_id = new.id
                 and status in ('confirmed', 'in_progress')
           ) then
            return new;
        end if;

        if new.role = old.role
           and new.availability_status = 'available'
           and old.availability_status = 'busy'
           and not exists (
               select 1
               from public.help_request_volunteers
               where volunteer_id = new.id
                 and status in ('confirmed', 'in_progress')
           ) then
            return new;
        end if;

        raise exception 'Coordinator profile update is not allowed.';
    end if;

    if new.role is distinct from old.role then
        if old.role = 'citizen'
           and new.role = 'volunteer'
           and (
               exists (
                   select 1
                   from public.help_requests
                   where volunteer_id = new.id
                     and status in ('confirmed', 'in_progress', 'completed')
               )
               or exists (
                   select 1
                   from public.help_request_volunteers
                   where volunteer_id = new.id
                     and status in ('confirmed', 'in_progress')
               )
           ) then
            return new;
        end if;

        raise exception 'Role changes are not allowed from this client flow.';
    end if;

    return new;
end;
$$;

drop trigger if exists prevent_invalid_profile_role_change_trigger on public.profiles;
create trigger prevent_invalid_profile_role_change_trigger
before update
on public.profiles
for each row
execute function public.prevent_invalid_profile_role_change();

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

create or replace function public.complete_my_volunteer_task(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    active_assignment_id uuid;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to complete this task.';
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
      and status = 'in_progress'
    order by updated_at desc
    limit 1;

    if active_assignment_id is null then
        raise exception 'Only your in-progress volunteer task can be completed.';
    end if;

    update public.help_request_volunteers
    set status = 'completed',
        completed_at = now(),
        updated_at = now()
    where id = active_assignment_id;

    update public.help_requests
    set status = 'completed',
        completed_at = now(),
        updated_at = now()
    where id = p_request_id
      and status = 'in_progress';

    perform public.release_volunteer_if_no_active_tasks(auth.uid());
end;
$$;

grant execute on function public.complete_my_volunteer_task(uuid) to authenticated;

