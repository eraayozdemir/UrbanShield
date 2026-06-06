-- UrbanShield - Activity logs, in-app notifications ve realtime yayınları
-- Bu dosya admin activity ekranı ve uygulama içi notification center için gerekli tabloları kurar.

-- Tüm önemli işlemler için denetim logu.
create table if not exists public.activity_logs (
    id uuid primary key default gen_random_uuid(),
    actor_id uuid not null references public.profiles(id) on delete cascade,
    actor_role text not null,
    action_type text not null,
    target_type text not null,
    target_id uuid,
    request_id uuid references public.help_requests(id) on delete set null,
    report_id uuid references public.suspicious_activity_reports(id) on delete set null,
    target_user_id uuid references public.profiles(id) on delete set null,
    message text not null,
    metadata jsonb,
    created_at timestamptz not null default now()
);

alter table public.activity_logs
drop constraint if exists activity_logs_action_type_check;

alter table public.activity_logs
add constraint activity_logs_action_type_check
check (
    action_type in (
        'request_created',
        'request_updated',
        'request_cancelled',
        'request_confirmed',
        'request_started',
        'request_completed',
        'request_status_updated',
        'request_priority_updated',
        'volunteer_assigned',
        'supply_support_logged',
        'announcement_published',
        'suspicious_report_submitted',
        'suspicious_report_reviewed',
        'role_updated',
        'evidence_uploaded'
    )
);

alter table public.activity_logs
drop constraint if exists activity_logs_target_type_check;

alter table public.activity_logs
add constraint activity_logs_target_type_check
check (target_type in ('request', 'report', 'user', 'announcement', 'supply_action'));

create index if not exists activity_logs_created_at_idx
on public.activity_logs(created_at desc);

create index if not exists activity_logs_actor_id_idx
on public.activity_logs(actor_id);

create index if not exists activity_logs_request_id_idx
on public.activity_logs(request_id);

-- Uygulama içi notification kayıtları.
-- APNs push değildir; uygulama açıldığında veya refresh/realtime geldiğinde bu tablo okunur.
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

alter table public.activity_logs enable row level security;
alter table public.notifications enable row level security;

drop policy if exists "users can insert own activity logs" on public.activity_logs;
create policy "users can insert own activity logs"
on public.activity_logs
for insert
to authenticated
with check (
    actor_id = auth.uid()
);

drop policy if exists "admins can view all activity logs" on public.activity_logs;
create policy "admins can view all activity logs"
on public.activity_logs
for select
to authenticated
using (public.current_app_role() = 'admin');

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

drop policy if exists "users can insert own notifications" on public.notifications;
create policy "users can insert own notifications"
on public.notifications
for insert
to authenticated
with check (
    user_id = auth.uid()
    and (actor_id is null or actor_id = auth.uid())
);

-- Birden fazla kullanıcıya notification oluşturur.
-- Cross-user notification insert işlemleri RLS yerine bu RPC üzerinden yapılır.
create or replace function public.create_in_app_notifications(
    p_user_ids uuid[],
    p_actor_id uuid default null,
    p_title text default '',
    p_message text default '',
    p_category text default 'request',
    p_link_type text default null,
    p_link_id uuid default null,
    p_request_id uuid default null,
    p_report_id uuid default null,
    p_announcement_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to create notifications.';
    end if;

    if p_actor_id is not null
       and p_actor_id <> auth.uid()
       and public.current_app_role() not in ('coordinator', 'admin') then
        raise exception 'Notification actor must match the signed-in user.';
    end if;

    if nullif(trim(p_title), '') is null
       or nullif(trim(p_message), '') is null then
        raise exception 'Notification title and message are required.';
    end if;

    if p_category not in ('request', 'assignment', 'announcement', 'report', 'moderation', 'coordinator') then
        raise exception 'Invalid notification category.';
    end if;

    if p_link_type is not null
       and p_link_type not in ('request', 'report', 'announcement') then
        raise exception 'Invalid notification link type.';
    end if;

    if p_user_ids is null or array_length(p_user_ids, 1) is null then
        return;
    end if;

    insert into public.notifications (
        user_id,
        actor_id,
        title,
        message,
        category,
        link_type,
        link_id,
        request_id,
        report_id,
        announcement_id
    )
    select distinct
        recipient.id,
        p_actor_id,
        trim(p_title),
        trim(p_message),
        p_category,
        p_link_type,
        p_link_id,
        p_request_id,
        p_report_id,
        p_announcement_id
    from unnest(p_user_ids) as recipient(id)
    join public.profiles p on p.id = recipient.id
    where not coalesce(p.is_suspended, false);
end;
$$;

grant execute on function public.create_in_app_notifications(
    uuid[],
    uuid,
    text,
    text,
    text,
    text,
    uuid,
    uuid,
    uuid,
    uuid
) to authenticated;

-- Role göre notification alıcılarını bulur.
create or replace function public.notification_recipient_ids_for_roles(
    p_roles text[],
    p_excluding_user_id uuid default null
)
returns table(id uuid)
language sql
security definer
set search_path = public
stable
as $$
    select p.id
    from public.profiles p
    where p.role = any(p_roles)
      and not coalesce(p.is_suspended, false)
      and (
          p_excluding_user_id is null
          or p.id <> p_excluding_user_id
      )
$$;

grant execute on function public.notification_recipient_ids_for_roles(text[], uuid)
to authenticated;

-- Supabase Realtime yayınlarına kullanılan tabloları ekler.
-- Supabase projesinde publication yoksa bu blok hata vermeden devam eder.
do $$
begin
    if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
        if not exists (
            select 1 from pg_publication_tables
            where pubname = 'supabase_realtime'
              and schemaname = 'public'
              and tablename = 'help_requests'
        ) then
            alter publication supabase_realtime add table public.help_requests;
        end if;

        if not exists (
            select 1 from pg_publication_tables
            where pubname = 'supabase_realtime'
              and schemaname = 'public'
              and tablename = 'help_request_volunteers'
        ) then
            alter publication supabase_realtime add table public.help_request_volunteers;
        end if;

        if not exists (
            select 1 from pg_publication_tables
            where pubname = 'supabase_realtime'
              and schemaname = 'public'
              and tablename = 'request_evidence'
        ) then
            alter publication supabase_realtime add table public.request_evidence;
        end if;

        if not exists (
            select 1 from pg_publication_tables
            where pubname = 'supabase_realtime'
              and schemaname = 'public'
              and tablename = 'notifications'
        ) then
            alter publication supabase_realtime add table public.notifications;
        end if;

        if not exists (
            select 1 from pg_publication_tables
            where pubname = 'supabase_realtime'
              and schemaname = 'public'
              and tablename = 'emergency_announcements'
        ) then
            alter publication supabase_realtime add table public.emergency_announcements;
        end if;
    end if;
end $$;
