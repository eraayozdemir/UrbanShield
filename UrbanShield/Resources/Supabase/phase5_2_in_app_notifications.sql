-- Phase 5.2: In-app notification center.
--
-- Run this in Supabase SQL Editor before testing notification inserts.

create table if not exists public.notifications (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(id) on delete cascade,
    actor_id uuid references public.profiles(id) on delete set null,
    title text not null,
    message text not null,
    category text not null,
    link_type text,
    link_id uuid,
    request_id uuid references public.help_requests(id) on delete set null,
    report_id uuid references public.suspicious_activity_reports(id) on delete set null,
    announcement_id uuid references public.emergency_announcements(id) on delete set null,
    is_read boolean not null default false,
    created_at timestamptz not null default now()
);

alter table public.notifications enable row level security;

alter table public.notifications
drop constraint if exists notifications_category_check;

alter table public.notifications
add constraint notifications_category_check
check (category in ('request', 'assignment', 'announcement', 'report', 'moderation', 'coordinator'));

alter table public.notifications
drop constraint if exists notifications_link_type_check;

alter table public.notifications
add constraint notifications_link_type_check
check (link_type is null or link_type in ('request', 'report', 'announcement'));

create index if not exists notifications_user_created_idx
on public.notifications(user_id, created_at desc);

create index if not exists notifications_user_unread_idx
on public.notifications(user_id, is_read)
where is_read = false;

drop policy if exists "users can view own notifications" on public.notifications;
create policy "users can view own notifications"
on public.notifications
for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "users can update own notifications" on public.notifications;
create policy "users can update own notifications"
on public.notifications
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

-- The app writes notifications for other users after a request/report/action.
-- This is intentionally broader than ownership because the client creates
-- recipient notifications during user-facing flows.
drop policy if exists "authenticated users can insert notifications" on public.notifications;
create policy "authenticated users can insert notifications"
on public.notifications
for insert
to authenticated
with check (auth.uid() is not null);

do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
          and schemaname = 'public'
          and tablename = 'notifications'
    ) then
        alter publication supabase_realtime add table public.notifications;
    end if;
end $$;
