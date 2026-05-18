-- Fix volunteer completion flow and cleanup availability after deleted assignments.
--
-- Run this after the Phase 3 / Phase 5.1 SQL files.
-- The app calls complete_my_volunteer_task() when a volunteer marks a task completed.

-- Allow only internal DB automation to release a temporary volunteer profile
-- back to citizen/available. Normal client role changes remain blocked.
create or replace function public.prevent_invalid_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    requester_role text;
begin
    if current_setting('app.profile_automation', true) = 'volunteer_release' then
        return new;
    end if;

    select role
    into requester_role
    from public.profiles
    where id = auth.uid();

    if requester_role = 'admin' then
        return new;
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
           and exists (
               select 1
               from public.help_requests
               where volunteer_id = new.id
                 and status in ('confirmed', 'in_progress', 'completed')
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

-- Remove older assignment triggers that tried to mutate profile roles from
-- help_request_volunteers. Completion role release now happens in the guarded
-- release_volunteer_if_no_active_tasks() function below.
do $$
declare
    trigger_record record;
begin
    for trigger_record in
        select t.tgname
        from pg_trigger t
        join pg_class c on c.oid = t.tgrelid
        join pg_namespace n on n.oid = c.relnamespace
        join pg_proc p on p.oid = t.tgfoid
        where n.nspname = 'public'
          and c.relname = 'help_request_volunteers'
          and not t.tgisinternal
          and (
              p.proname ilike '%profile%'
              or p.proname ilike '%role%'
              or pg_get_functiondef(p.oid) ilike '%public.profiles%'
              or pg_get_functiondef(p.oid) ilike '% role %'
          )
    loop
        execute format(
            'drop trigger if exists %I on public.help_request_volunteers',
            trigger_record.tgname
        );
    end loop;
end $$;

create or replace function public.release_volunteer_if_no_active_tasks(p_volunteer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if p_volunteer_id is null then
        return;
    end if;

    if not exists (
        select 1
        from public.help_request_volunteers
        where volunteer_id = p_volunteer_id
          and status in ('confirmed', 'in_progress')
    ) then
        perform set_config('app.profile_automation', 'volunteer_release', true);

        update public.profiles
        set role = case
                when role = 'volunteer' then 'citizen'
                else role
            end,
            availability_status = 'available'
        where id = p_volunteer_id
          and (
              role = 'volunteer'
              or availability_status is distinct from 'available'
          );
    end if;
end;
$$;

create or replace function public.handle_assignment_availability_cleanup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if tg_op = 'DELETE' then
        perform public.release_volunteer_if_no_active_tasks(old.volunteer_id);
        return old;
    end if;

    if new.status in ('completed', 'cancelled')
       and old.status is distinct from new.status then
        perform public.release_volunteer_if_no_active_tasks(new.volunteer_id);
    end if;

    return new;
end;
$$;

drop trigger if exists help_request_volunteer_availability_cleanup_trigger
on public.help_request_volunteers;

create trigger help_request_volunteer_availability_cleanup_trigger
after update of status or delete
on public.help_request_volunteers
for each row
execute function public.handle_assignment_availability_cleanup();

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

-- One-time cleanup for profiles that were left as volunteer/busy before this
-- trigger existed, for example after manually deleting an in-progress request.
do $$
begin
    perform set_config('app.profile_automation', 'volunteer_release', true);

    update public.profiles p
    set role = case
            when p.role = 'volunteer' then 'citizen'
            else p.role
        end,
        availability_status = 'available'
    where p.role in ('citizen', 'volunteer')
      and (
          p.role = 'volunteer'
          or p.availability_status is distinct from 'available'
      )
      and not exists (
          select 1
          from public.help_request_volunteers hrv
          where hrv.volunteer_id = p.id
            and hrv.status in ('confirmed', 'in_progress')
      );
end $$;
