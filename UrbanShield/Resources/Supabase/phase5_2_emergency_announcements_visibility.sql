-- Phase 5.2: Emergency announcements visibility


create table if not exists public.emergency_announcements (
    id uuid primary key default gen_random_uuid(),
    coordinator_id uuid not null references public.profiles(id),
    title text not null,
    message text not null,
    severity text not null default 'info',
    audience text not null default 'all',
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.emergency_announcements enable row level security;

alter table public.emergency_announcements
drop constraint if exists emergency_announcements_severity_check;

alter table public.emergency_announcements
add constraint emergency_announcements_severity_check
check (severity in ('info', 'warning', 'critical'));

alter table public.emergency_announcements
drop constraint if exists emergency_announcements_audience_check;

alter table public.emergency_announcements
add constraint emergency_announcements_audience_check
check (audience in ('all', 'citizens', 'volunteers'));

create index if not exists emergency_announcements_created_at_idx
on public.emergency_announcements(created_at desc);

create index if not exists emergency_announcements_audience_idx
on public.emergency_announcements(audience);

drop policy if exists "coordinators can insert emergency announcements" on public.emergency_announcements;
create policy "coordinators can insert emergency announcements"
on public.emergency_announcements
for insert
to authenticated
with check (
    coordinator_id = auth.uid()
    and public.current_app_role() in ('coordinator', 'admin')
    and severity in ('info', 'warning', 'critical')
    and audience in ('all', 'citizens', 'volunteers')
);

drop policy if exists "users can view active emergency announcements for audience" on public.emergency_announcements;
create policy "users can view active emergency announcements for audience"
on public.emergency_announcements
for select
to authenticated
using (
    is_active = true
    and (
        audience = 'all'
        or (audience = 'citizens' and public.current_app_role() = 'citizen')
        or (audience = 'volunteers' and public.current_app_role() = 'volunteer')
        or public.current_app_role() in ('coordinator', 'admin')
    )
);
