-- Phase 3: Coordinator Dashboard + Priority
-- Run this in Supabase SQL Editor after the Phase 2 help_requests table exists.

alter table public.help_requests
add column if not exists priority_level text not null default 'medium';

alter table public.help_requests
drop constraint if exists help_requests_priority_level_check;

alter table public.help_requests
add constraint help_requests_priority_level_check
check (priority_level in ('low', 'medium', 'high', 'critical'));

-- Existing request rows keep the default medium priority. If you want initial
-- coordinator priority to mirror citizen urgency, run this once:
update public.help_requests
set priority_level = urgency_level
where priority_level = 'medium'
  and urgency_level in ('low', 'medium', 'high', 'critical');

-- Coordinators and admins can view all help requests for operational oversight.
drop policy if exists "coordinators can view all help requests" on public.help_requests;
create policy "coordinators can view all help requests"
on public.help_requests
for select
to authenticated
using (
    exists (
        select 1
        from public.profiles
        where profiles.id = auth.uid()
          and profiles.role in ('coordinator', 'admin')
    )
);

-- Coordinators and admins can update request priority only. The trigger below
-- prevents this policy from being used to alter status, location, owner, etc.
drop policy if exists "coordinators can update request priority" on public.help_requests;
create policy "coordinators can update request priority"
on public.help_requests
for update
to authenticated
using (
    exists (
        select 1
        from public.profiles
        where profiles.id = auth.uid()
          and profiles.role in ('coordinator', 'admin')
    )
)
with check (
    exists (
        select 1
        from public.profiles
        where profiles.id = auth.uid()
          and profiles.role in ('coordinator', 'admin')
    )
    and priority_level in ('low', 'medium', 'high', 'critical')
);

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
           or new.volunteer_id is distinct from old.volunteer_id
           or new.request_type is distinct from old.request_type
           or new.description is distinct from old.description
           or new.urgency_level is distinct from old.urgency_level
           or new.status is distinct from old.status
           or new.latitude is distinct from old.latitude
           or new.longitude is distinct from old.longitude
           or new.created_at is distinct from old.created_at
           or new.confirmed_at is distinct from old.confirmed_at
           or new.completed_at is distinct from old.completed_at then
            raise exception 'Coordinators can only update request priority.';
        end if;
    end if;

    return new;
end;
$$;

drop trigger if exists prevent_coordinator_non_priority_updates_trigger on public.help_requests;
create trigger prevent_coordinator_non_priority_updates_trigger
before update on public.help_requests
for each row
execute function public.prevent_coordinator_non_priority_updates();
