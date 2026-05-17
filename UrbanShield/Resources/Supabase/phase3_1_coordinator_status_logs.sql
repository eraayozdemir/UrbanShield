-- Coordinator status update + coordination logs

create or replace function public.current_app_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
    select role
    from public.profiles
    where id = auth.uid()
    limit 1
$$;

create table if not exists public.coordination_logs (
    id uuid primary key default gen_random_uuid(),
    request_id uuid not null references public.help_requests(id) on delete cascade,
    coordinator_id uuid not null references public.profiles(id),
    action_type text not null,
    old_value text,
    new_value text,
    message text not null,
    created_at timestamptz not null default now()
);

alter table public.coordination_logs enable row level security;

alter table public.coordination_logs
drop constraint if exists coordination_logs_action_type_check;

alter table public.coordination_logs
add constraint coordination_logs_action_type_check
check (action_type in ('priority_updated', 'status_updated', 'volunteer_assigned'));

create index if not exists coordination_logs_request_id_idx
on public.coordination_logs(request_id);

create index if not exists coordination_logs_created_at_idx
on public.coordination_logs(created_at desc);

drop policy if exists "coordinators can view coordination logs" on public.coordination_logs;
create policy "coordinators can view coordination logs"
on public.coordination_logs
for select
to authenticated
using (public.current_app_role() in ('coordinator', 'admin'));

drop policy if exists "coordinators can insert coordination logs" on public.coordination_logs;
create policy "coordinators can insert coordination logs"
on public.coordination_logs
for insert
to authenticated
with check (
    coordinator_id = auth.uid()
    and public.current_app_role() in ('coordinator', 'admin')
    and action_type in ('priority_updated', 'status_updated', 'volunteer_assigned')
);

-- Coordinators can update assignment rows when they move request status.
drop policy if exists "coordinators can update volunteer assignments" on public.help_request_volunteers;
create policy "coordinators can update volunteer assignments"
on public.help_request_volunteers
for update
to authenticated
using (public.current_app_role() in ('coordinator', 'admin'))
with check (
    public.current_app_role() in ('coordinator', 'admin')
    and status in ('confirmed', 'in_progress', 'completed', 'cancelled')
);

-- Expand profile update guard: coordinator can mark an assigned volunteer busy,
-- and can release the same volunteer back to available after completion/cancel.
create or replace function public.prevent_invalid_profile_role_change()
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

-- Expand request update guard: coordinator can update priority, assign a
-- volunteer, or make controlled status transitions.
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
            raise exception 'Coordinators can only update priority, status, or assignment fields.';
        end if;

        if new.status not in ('open', 'confirmed', 'in_progress', 'completed', 'cancelled') then
            raise exception 'Invalid request status.';
        end if;

        if new.priority_level not in ('low', 'medium', 'high', 'critical') then
            raise exception 'Invalid priority level.';
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
