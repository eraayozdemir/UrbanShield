-- Phase 3: Admin user management + coordinator volunteer assignment

-- Helper function avoids recursive RLS checks on public.profiles policies.
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

-- Keep normal login/profile routing working for every authenticated user.
drop policy if exists "authenticated users can view own profile" on public.profiles;
create policy "authenticated users can view own profile"
on public.profiles
for select
to authenticated
using (id = auth.uid());

-- Admins can list all profiles in the in-app admin panel.
drop policy if exists "admins can view all profiles" on public.profiles;
create policy "admins can view all profiles"
on public.profiles
for select
to authenticated
using (public.current_app_role() = 'admin');

-- Coordinators need to see available skilled users so they can assign volunteers.
drop policy if exists "coordinators can view available volunteer profiles" on public.profiles;
create policy "coordinators can view available volunteer profiles"
on public.profiles
for select
to authenticated
using (
    public.current_app_role() in ('coordinator', 'admin')
    and (
        availability_status = 'available'
        or id = auth.uid()
    )
);

-- Admin role changes from the app. Self-demotion is blocked in app code and by RLS.
drop policy if exists "admins can update user roles" on public.profiles;
create policy "admins can update user roles"
on public.profiles
for update
to authenticated
using (
    id <> auth.uid()
    and public.current_app_role() = 'admin'
)
with check (
    id <> auth.uid()
    and role in ('citizen', 'volunteer', 'coordinator', 'admin')
    and public.current_app_role() = 'admin'
);

-- Coordinators can only mark a selected assigned volunteer as busy/volunteer.
drop policy if exists "coordinators can mark assigned volunteers busy" on public.profiles;
create policy "coordinators can mark assigned volunteers busy"
on public.profiles
for update
to authenticated
using (public.current_app_role() in ('coordinator', 'admin'))
with check (
    role = 'volunteer'
    and availability_status = 'busy'
    and public.current_app_role() in ('coordinator', 'admin')
);

-- Replace the older role-change guard so admins can manage roles, while normal
-- users still cannot promote themselves.
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

    if requester_role in ('coordinator', 'admin') then
        if new.email is distinct from old.email
           or new.full_name is distinct from old.full_name
           or new.created_at is distinct from old.created_at
           or new.volunteer_skills is distinct from old.volunteer_skills then
            raise exception 'Coordinators can only mark assigned volunteers as busy.';
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

-- Coordinators can create volunteer assignment rows.
drop policy if exists "coordinators can insert volunteer assignments" on public.help_request_volunteers;
create policy "coordinators can insert volunteer assignments"
on public.help_request_volunteers
for insert
to authenticated
with check (
    status = 'confirmed'
    and public.current_app_role() in ('coordinator', 'admin')
);

-- Expand the Phase 3 request update guard: coordinators can update priority,
-- or assign an available volunteer by moving an open/confirmed request to confirmed.
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
           or new.created_at is distinct from old.created_at
           or new.completed_at is distinct from old.completed_at then
            raise exception 'Coordinators can only update priority or assign volunteers.';
        end if;

        if new.status not in ('open', 'confirmed', 'in_progress', 'completed', 'cancelled') then
            raise exception 'Invalid request status.';
        end if;

        if new.priority_level not in ('low', 'medium', 'high', 'critical') then
            raise exception 'Invalid priority level.';
        end if;

        if new.status is distinct from old.status
           and not (old.status in ('open', 'confirmed') and new.status = 'confirmed') then
            raise exception 'Coordinators can only confirm a request while assigning volunteers.';
        end if;
    end if;

    return new;
end;
$$;
