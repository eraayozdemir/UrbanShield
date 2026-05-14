create table if not exists public.help_request_volunteers (
    id uuid primary key default gen_random_uuid(),
    request_id uuid not null references public.help_requests(id) on delete cascade,
    volunteer_id uuid not null references public.profiles(id) on delete cascade,
    status text not null check (status in ('confirmed', 'in_progress', 'completed', 'cancelled')),
    accepted_at timestamptz not null default now(),
    started_at timestamptz,
    completed_at timestamptz,
    updated_at timestamptz not null default now(),
    unique (request_id, volunteer_id)
);

alter table public.help_requests
drop constraint if exists help_requests_status_check;

alter table public.help_requests
add constraint help_requests_status_check
check (status in ('open', 'confirmed', 'in_progress', 'completed', 'cancelled'));

alter table public.help_request_volunteers enable row level security;

create or replace function public.is_help_request_owner(p_request_id uuid, p_user_id uuid)
returns boolean
as $function$
    select exists (
        select 1
        from public.help_requests hr
        where hr.id = p_request_id
          and hr.citizen_id = p_user_id
    );
$function$
language sql
security definer
set search_path = public;

create or replace function public.is_help_request_assigned_volunteer(p_request_id uuid, p_user_id uuid)
returns boolean
as $function$
    select exists (
        select 1
        from public.help_request_volunteers hrv
        where hrv.request_id = p_request_id
          and hrv.volunteer_id = p_user_id
    );
$function$
language sql
security definer
set search_path = public;

drop policy if exists "Authenticated users can view open help requests"
    on public.help_requests;
drop policy if exists "Authenticated users can view open or confirmed help requests"
    on public.help_requests;
create policy "Authenticated users can view open or confirmed help requests"
on public.help_requests
for select
to authenticated
using (status in ('open', 'confirmed'));

drop policy if exists "Assigned volunteers can view assigned help requests"
    on public.help_requests;
create policy "Assigned volunteers can view assigned help requests"
on public.help_requests
for select
to authenticated
using (public.is_help_request_assigned_volunteer(help_requests.id, auth.uid()));

drop policy if exists "Request owners can view own help requests"
    on public.help_requests;
create policy "Request owners can view own help requests"
on public.help_requests
for select
to authenticated
using (citizen_id = auth.uid());

drop policy if exists "request volunteers are visible to participants and nearby volunteers" on public.help_request_volunteers;
drop policy if exists "request volunteers are visible to assigned volunteers and owners" on public.help_request_volunteers;
create policy "request volunteers are visible to assigned volunteers"
on public.help_request_volunteers
for select
to authenticated
using (volunteer_id = auth.uid());

drop policy if exists "users can accept eligible requests as themselves" on public.help_request_volunteers;
create policy "users can accept eligible requests as themselves"
on public.help_request_volunteers
for insert
with check (
    volunteer_id = auth.uid()
    and exists (
        select 1
        from public.help_requests hr
        where hr.id = request_id
          and hr.status in ('open', 'confirmed')
          and hr.citizen_id <> auth.uid()
    )
);

drop policy if exists "volunteers and request owners can update assignments" on public.help_request_volunteers;
drop policy if exists "volunteers can update own assignments" on public.help_request_volunteers;
create policy "volunteers can update own assignments"
on public.help_request_volunteers
for update
to authenticated
using (volunteer_id = auth.uid())
with check (volunteer_id = auth.uid());

insert into public.help_request_volunteers (
    request_id,
    volunteer_id,
    status,
    accepted_at,
    started_at,
    completed_at,
    updated_at
)
select
    id,
    volunteer_id,
    status,
    coalesce(confirmed_at, created_at),
    case when status in ('in_progress', 'completed') then updated_at else null end,
    completed_at,
    updated_at
from public.help_requests
where volunteer_id is not null
  and status in ('confirmed', 'in_progress', 'completed')
on conflict (request_id, volunteer_id) do nothing;

create or replace function public.release_volunteer_if_idle(p_volunteer_id uuid)
returns void
as $function$
begin
    if not exists (
        select 1
        from public.help_request_volunteers hrv
        where hrv.volunteer_id = p_volunteer_id
          and hrv.status in ('confirmed', 'in_progress')
    ) then
        update public.profiles
        set role = 'citizen',
            availability_status = 'available'
        where id = p_volunteer_id;
    end if;
end;
$function$
language plpgsql
security definer
set search_path = public;

create or replace function public.validate_help_request_volunteer()
returns trigger
as $function$
begin
    if exists (
        select 1
        from public.help_request_volunteers hrv
        where hrv.volunteer_id = new.volunteer_id
          and hrv.status in ('confirmed', 'in_progress')
    ) then
        raise exception 'volunteer_already_has_active_request';
    end if;

    if not exists (
        select 1
        from public.help_requests hr
        where hr.id = new.request_id
          and hr.status in ('open', 'confirmed')
          and hr.citizen_id <> new.volunteer_id
    ) then
        raise exception 'request_is_not_accepting_volunteers';
    end if;

    new.updated_at = now();
    new.accepted_at = coalesce(new.accepted_at, now());
    return new;
end;
$function$
language plpgsql
security definer
set search_path = public;

drop trigger if exists validate_help_request_volunteer_before_insert on public.help_request_volunteers;
create trigger validate_help_request_volunteer_before_insert
before insert on public.help_request_volunteers
for each row execute function public.validate_help_request_volunteer();

create or replace function public.sync_help_request_assignment_state()
returns trigger
as $function$
begin
    if new.status in ('confirmed', 'in_progress') then
        update public.profiles
        set role = 'volunteer',
            availability_status = 'busy'
        where id = new.volunteer_id;
    else
        perform public.release_volunteer_if_idle(new.volunteer_id);
    end if;

    if new.status = 'confirmed' then
        update public.help_requests
        set status = 'confirmed',
            confirmed_at = coalesce(confirmed_at, now()),
            updated_at = now()
        where id = new.request_id
          and status = 'open';
    elsif new.status = 'in_progress' then
        update public.help_requests
        set status = 'in_progress',
            updated_at = now()
        where id = new.request_id
          and status in ('open', 'confirmed');
    elsif new.status = 'completed' then
        update public.help_requests
        set status = 'completed',
            completed_at = coalesce(completed_at, now()),
            updated_at = now()
        where id = new.request_id
          and status <> 'completed';
    end if;

    return new;
end;
$function$
language plpgsql
security definer
set search_path = public;

drop trigger if exists sync_help_request_assignment_after_insert_update on public.help_request_volunteers;
create trigger sync_help_request_assignment_after_insert_update
after insert or update of status on public.help_request_volunteers
for each row execute function public.sync_help_request_assignment_state();

create or replace function public.close_help_request_assignments()
returns trigger
as $function$
declare
    assignment record;
begin
    if old.status = new.status or new.status not in ('cancelled', 'completed') then
        return new;
    end if;

    update public.help_request_volunteers
    set status = case
            when new.status = 'completed' and status = 'in_progress' then 'completed'
            else 'cancelled'
        end,
        completed_at = case
            when new.status = 'completed' and status = 'in_progress' then coalesce(completed_at, now())
            else completed_at
        end,
        updated_at = now()
    where request_id = new.id
      and status in ('confirmed', 'in_progress');

    for assignment in
        select distinct volunteer_id
        from public.help_request_volunteers
        where request_id = new.id
    loop
        perform public.release_volunteer_if_idle(assignment.volunteer_id);
    end loop;

    return new;
end;
$function$
language plpgsql
security definer
set search_path = public;

drop trigger if exists close_help_request_assignments_after_request_close on public.help_requests;
create trigger close_help_request_assignments_after_request_close
after update of status on public.help_requests
for each row execute function public.close_help_request_assignments();
