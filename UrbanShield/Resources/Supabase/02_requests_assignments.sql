-- UrbanShield - Help request ve volunteer assignment tabloları
-- Bu dosya Phase 2 ana verisini oluşturur: citizen requestleri ve volunteer task ilişkileri.

-- Citizen tarafından oluşturulan yardım talepleri.
create table if not exists public.help_requests (
    id uuid primary key default gen_random_uuid(),
    citizen_id uuid not null references public.profiles(id) on delete cascade,
    volunteer_id uuid references public.profiles(id) on delete set null,
    request_type text not null,
    description text not null,
    urgency_level text not null,
    status text not null default 'open',
    latitude double precision not null,
    longitude double precision not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    confirmed_at timestamptz,
    completed_at timestamptz
);

alter table public.help_requests
drop constraint if exists help_requests_request_type_check;

alter table public.help_requests
add constraint help_requests_request_type_check
check (request_type in ('earthquake', 'fire', 'flood', 'accident', 'medical', 'other'));

alter table public.help_requests
drop constraint if exists help_requests_urgency_level_check;

alter table public.help_requests
add constraint help_requests_urgency_level_check
check (urgency_level in ('low', 'medium', 'high', 'critical'));

alter table public.help_requests
drop constraint if exists help_requests_status_check;

alter table public.help_requests
add constraint help_requests_status_check
check (status in ('open', 'confirmed', 'in_progress', 'completed', 'cancelled'));

alter table public.help_requests
drop constraint if exists help_requests_latitude_check;

alter table public.help_requests
add constraint help_requests_latitude_check
check (latitude between -90 and 90);

alter table public.help_requests
drop constraint if exists help_requests_longitude_check;

alter table public.help_requests
add constraint help_requests_longitude_check
check (longitude between -180 and 180);

create index if not exists help_requests_citizen_id_idx
on public.help_requests(citizen_id);

create index if not exists help_requests_status_idx
on public.help_requests(status);

create index if not exists help_requests_updated_at_idx
on public.help_requests(updated_at desc);

create index if not exists help_requests_location_idx
on public.help_requests(latitude, longitude);

-- Bir request için volunteer kabul/atama kayıtları.
-- Critical requestlerde birden fazla volunteer olabilir; aynı volunteer aynı requesti bir kere alabilir.
create table if not exists public.help_request_volunteers (
    id uuid primary key default gen_random_uuid(),
    request_id uuid not null references public.help_requests(id) on delete cascade,
    volunteer_id uuid not null references public.profiles(id) on delete cascade,
    status text not null default 'confirmed',
    accepted_at timestamptz not null default now(),
    started_at timestamptz,
    completed_at timestamptz,
    updated_at timestamptz not null default now(),
    unique (request_id, volunteer_id)
);

alter table public.help_request_volunteers
drop constraint if exists help_request_volunteers_status_check;

alter table public.help_request_volunteers
add constraint help_request_volunteers_status_check
check (status in ('confirmed', 'in_progress', 'completed', 'cancelled'));

create index if not exists help_request_volunteers_request_id_idx
on public.help_request_volunteers(request_id);

create index if not exists help_request_volunteers_volunteer_id_idx
on public.help_request_volunteers(volunteer_id);

create index if not exists help_request_volunteers_active_idx
on public.help_request_volunteers(request_id, status)
where status in ('confirmed', 'in_progress');

-- Request görüntüleme helperı.
-- Owner, assigned volunteer, coordinator ve admin daha geniş veri görebilir.
create or replace function public.can_view_help_request(p_request_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
    select exists (
        select 1
        from public.help_requests hr
        where hr.id = p_request_id
          and (
              hr.status in ('open', 'confirmed', 'in_progress')
              or hr.citizen_id = p_user_id
              or hr.volunteer_id = p_user_id
              or public.current_app_role() in ('coordinator', 'admin')
              or exists (
                  select 1
                  from public.help_request_volunteers hrv
                  where hrv.request_id = hr.id
                    and hrv.volunteer_id = p_user_id
              )
          )
    )
$$;

grant execute on function public.can_view_help_request(uuid, uuid)
to authenticated;

alter table public.help_requests enable row level security;
alter table public.help_request_volunteers enable row level security;

drop policy if exists "authenticated users can view accessible help requests" on public.help_requests;
create policy "authenticated users can view accessible help requests"
on public.help_requests
for select
to authenticated
using (public.can_view_help_request(help_requests.id, auth.uid()));

drop policy if exists "citizens can insert own help requests" on public.help_requests;
create policy "citizens can insert own help requests"
on public.help_requests
for insert
to authenticated
with check (
    citizen_id = auth.uid()
    and status = 'open'
    and public.current_app_role() in ('citizen', 'volunteer')
);

drop policy if exists "citizens can update own active help requests" on public.help_requests;
create policy "citizens can update own active help requests"
on public.help_requests
for update
to authenticated
using (
    citizen_id = auth.uid()
    and status not in ('completed', 'cancelled')
)
with check (
    citizen_id = auth.uid()
    and status not in ('completed', 'cancelled')
);

drop policy if exists "coordinators and admins can update help requests" on public.help_requests;
create policy "coordinators and admins can update help requests"
on public.help_requests
for update
to authenticated
using (public.current_app_role() in ('coordinator', 'admin'))
with check (public.current_app_role() in ('coordinator', 'admin'));

drop policy if exists "participants can view request assignments" on public.help_request_volunteers;
create policy "participants can view request assignments"
on public.help_request_volunteers
for select
to authenticated
using (
    volunteer_id = auth.uid()
    or public.current_app_role() in ('coordinator', 'admin')
    or exists (
        select 1
        from public.help_requests hr
        where hr.id = help_request_volunteers.request_id
          and hr.citizen_id = auth.uid()
    )
);

drop policy if exists "volunteers can insert own assignment" on public.help_request_volunteers;
create policy "volunteers can insert own assignment"
on public.help_request_volunteers
for insert
to authenticated
with check (
    volunteer_id = auth.uid()
    and public.current_app_role() in ('citizen', 'volunteer')
);

drop policy if exists "volunteers can update own assignments" on public.help_request_volunteers;
create policy "volunteers can update own assignments"
on public.help_request_volunteers
for update
to authenticated
using (volunteer_id = auth.uid())
with check (volunteer_id = auth.uid());

drop policy if exists "coordinators and admins can update assignments" on public.help_request_volunteers;
create policy "coordinators and admins can update assignments"
on public.help_request_volunteers
for update
to authenticated
using (public.current_app_role() in ('coordinator', 'admin'))
with check (public.current_app_role() in ('coordinator', 'admin'));

