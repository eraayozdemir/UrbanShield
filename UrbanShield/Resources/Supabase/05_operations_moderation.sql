-- UrbanShield - Coordinator operations, suspicious reports ve admin moderation
-- Bu dosya coordinator dashboard/tools ve admin moderation ekranlarının kullandığı tabloları kurar.

-- Coordinator status/assignment işlemleri için log tablosu.
create table if not exists public.coordination_logs (
    id uuid primary key default gen_random_uuid(),
    request_id uuid not null references public.help_requests(id) on delete cascade,
    coordinator_id uuid not null references public.profiles(id) on delete cascade,
    action_type text not null,
    old_value text,
    new_value text,
    message text not null,
    created_at timestamptz not null default now()
);

alter table public.coordination_logs
drop constraint if exists coordination_logs_action_type_check;

alter table public.coordination_logs
add constraint coordination_logs_action_type_check
check (action_type in ('priority_updated', 'status_updated', 'volunteer_assigned'));

create index if not exists coordination_logs_request_id_idx
on public.coordination_logs(request_id);

create index if not exists coordination_logs_created_at_idx
on public.coordination_logs(created_at desc);

-- Supply/resource support action kayıtları.
create table if not exists public.supply_support_actions (
    id uuid primary key default gen_random_uuid(),
    request_id uuid not null references public.help_requests(id) on delete cascade,
    coordinator_id uuid not null references public.profiles(id) on delete cascade,
    support_type text not null,
    status text not null default 'planned',
    quantity text,
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.supply_support_actions
drop constraint if exists supply_support_actions_support_type_check;

alter table public.supply_support_actions
add constraint supply_support_actions_support_type_check
check (support_type in ('food', 'water', 'medical', 'shelter', 'transport', 'rescue_equipment', 'communication', 'other'));

alter table public.supply_support_actions
drop constraint if exists supply_support_actions_status_check;

alter table public.supply_support_actions
add constraint supply_support_actions_status_check
check (status in ('planned', 'dispatched', 'delivered', 'cancelled'));

create index if not exists supply_support_actions_request_id_idx
on public.supply_support_actions(request_id);

create index if not exists supply_support_actions_created_at_idx
on public.supply_support_actions(created_at desc);

-- Emergency announcement kayıtları.
create table if not exists public.emergency_announcements (
    id uuid primary key default gen_random_uuid(),
    coordinator_id uuid not null references public.profiles(id) on delete cascade,
    title text not null,
    message text not null,
    severity text not null default 'info',
    audience text not null default 'all',
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

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

create index if not exists emergency_announcements_active_idx
on public.emergency_announcements(is_active);

-- Citizen/volunteer/coordinator tarafından admin incelemesi için gönderilen report kayıtları.
create table if not exists public.suspicious_activity_reports (
    id uuid primary key default gen_random_uuid(),
    reporter_id uuid not null references public.profiles(id) on delete cascade,
    request_id uuid references public.help_requests(id) on delete set null,
    category text not null,
    details text not null,
    status text not null default 'open',
    reviewed_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.suspicious_activity_reports
drop constraint if exists suspicious_activity_reports_category_check;

alter table public.suspicious_activity_reports
add constraint suspicious_activity_reports_category_check
check (category in ('fake_request', 'abuse', 'spam', 'unsafe_behavior', 'other'));

alter table public.suspicious_activity_reports
drop constraint if exists suspicious_activity_reports_status_check;

alter table public.suspicious_activity_reports
add constraint suspicious_activity_reports_status_check
check (status in ('open', 'reviewing', 'resolved', 'dismissed'));

create index if not exists suspicious_activity_reports_reporter_id_idx
on public.suspicious_activity_reports(reporter_id);

create index if not exists suspicious_activity_reports_status_idx
on public.suspicious_activity_reports(status);

create index if not exists suspicious_activity_reports_created_at_idx
on public.suspicious_activity_reports(created_at desc);

-- Adminin report üzerinde aldığı moderation kararları.
create table if not exists public.moderation_actions (
    id uuid primary key default gen_random_uuid(),
    admin_id uuid not null references public.profiles(id) on delete cascade,
    report_id uuid references public.suspicious_activity_reports(id) on delete set null,
    request_id uuid references public.help_requests(id) on delete set null,
    target_user_id uuid references public.profiles(id) on delete set null,
    action_type text not null,
    notes text,
    created_at timestamptz not null default now()
);

alter table public.moderation_actions
drop constraint if exists moderation_actions_action_type_check;

alter table public.moderation_actions
add constraint moderation_actions_action_type_check
check (action_type in ('status_updated', 'request_cancelled', 'report_resolved', 'report_dismissed', 'note_added'));

create index if not exists moderation_actions_created_at_idx
on public.moderation_actions(created_at desc);

alter table public.coordination_logs enable row level security;
alter table public.supply_support_actions enable row level security;
alter table public.emergency_announcements enable row level security;
alter table public.suspicious_activity_reports enable row level security;
alter table public.moderation_actions enable row level security;

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
);

drop policy if exists "coordinators can manage supply support" on public.supply_support_actions;
create policy "coordinators can manage supply support"
on public.supply_support_actions
for all
to authenticated
using (public.current_app_role() in ('coordinator', 'admin'))
with check (
    coordinator_id = auth.uid()
    and public.current_app_role() in ('coordinator', 'admin')
);

drop policy if exists "coordinators can view all announcements" on public.emergency_announcements;
create policy "coordinators can view all announcements"
on public.emergency_announcements
for select
to authenticated
using (
    public.current_app_role() in ('coordinator', 'admin')
    or (
        is_active
        and (
            audience = 'all'
            or (audience = 'citizens' and public.current_app_role() in ('citizen', 'volunteer'))
            or (audience = 'volunteers' and public.current_app_role() = 'volunteer')
        )
    )
);

drop policy if exists "coordinators can insert announcements" on public.emergency_announcements;
create policy "coordinators can insert announcements"
on public.emergency_announcements
for insert
to authenticated
with check (
    coordinator_id = auth.uid()
    and public.current_app_role() in ('coordinator', 'admin')
);

drop policy if exists "coordinators can update announcements" on public.emergency_announcements;
create policy "coordinators can update announcements"
on public.emergency_announcements
for update
to authenticated
using (public.current_app_role() in ('coordinator', 'admin'))
with check (public.current_app_role() in ('coordinator', 'admin'));

drop policy if exists "users can view own suspicious reports" on public.suspicious_activity_reports;
create policy "users can view own suspicious reports"
on public.suspicious_activity_reports
for select
to authenticated
using (
    reporter_id = auth.uid()
    or public.current_app_role() = 'admin'
);

drop policy if exists "non-admin users can insert suspicious reports" on public.suspicious_activity_reports;
create policy "non-admin users can insert suspicious reports"
on public.suspicious_activity_reports
for insert
to authenticated
with check (
    reporter_id = auth.uid()
    and public.current_app_role() in ('citizen', 'volunteer', 'coordinator')
    and status = 'open'
);

drop policy if exists "admins can update suspicious reports" on public.suspicious_activity_reports;
create policy "admins can update suspicious reports"
on public.suspicious_activity_reports
for update
to authenticated
using (public.current_app_role() = 'admin')
with check (public.current_app_role() = 'admin');

drop policy if exists "admins can view moderation actions" on public.moderation_actions;
create policy "admins can view moderation actions"
on public.moderation_actions
for select
to authenticated
using (public.current_app_role() = 'admin');

drop policy if exists "admins can insert moderation actions" on public.moderation_actions;
create policy "admins can insert moderation actions"
on public.moderation_actions
for insert
to authenticated
with check (
    admin_id = auth.uid()
    and public.current_app_role() = 'admin'
);

