-- Phase 4.2: Citizen request update + evidence upload

create table if not exists public.request_evidence (
    id uuid primary key default gen_random_uuid(),
    request_id uuid not null references public.help_requests(id) on delete cascade,
    uploaded_by uuid not null references public.profiles(id) on delete cascade,
    file_path text not null unique,
    file_name text not null,
    content_type text not null default 'image/jpeg',
    file_size integer not null default 0,
    created_at timestamptz not null default now()
);

alter table public.request_evidence enable row level security;

create index if not exists request_evidence_request_id_idx
on public.request_evidence(request_id);

create index if not exists request_evidence_uploaded_by_idx
on public.request_evidence(uploaded_by);

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

drop policy if exists "request evidence visible to related users" on public.request_evidence;
create policy "request evidence visible to related users"
on public.request_evidence
for select
to authenticated
using (
    exists (
        select 1
        from public.help_requests hr
        where hr.id = request_evidence.request_id
        and (
            hr.citizen_id = auth.uid()
            or public.current_app_role() in ('coordinator', 'admin')
            or exists (
                select 1
                from public.help_request_volunteers hrv
                where hrv.request_id = hr.id
                and hrv.volunteer_id = auth.uid()
            )
        )
    )
);

drop policy if exists "citizens can insert evidence for own active requests" on public.request_evidence;
drop policy if exists "owners and assigned volunteers can insert evidence" on public.request_evidence;
create policy "owners and assigned volunteers can insert evidence"
on public.request_evidence
for insert
to authenticated
with check (
    uploaded_by = auth.uid()
    and exists (
        select 1
        from public.help_requests hr
        where hr.id = request_evidence.request_id
        and hr.status not in ('completed', 'cancelled')
        and (
            hr.citizen_id = auth.uid()
            or exists (
                select 1
                from public.help_request_volunteers hrv
                where hrv.request_id = hr.id
                and hrv.volunteer_id = auth.uid()
                and hrv.status in ('confirmed', 'in_progress')
            )
        )
    )
);

insert into storage.buckets (
    id,
    name,
    public,
    file_size_limit,
    allowed_mime_types
)
values (
    'request-evidence',
    'request-evidence',
    false,
    1048576,
    array['image/jpeg']
)
on conflict (id) do update
set
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.request_evidence_request_id(object_name text)
returns uuid
language plpgsql
stable
as $$
begin
    return split_part(object_name, '/', 1)::uuid;
exception
    when others then
        return null;
end;
$$;

drop policy if exists "citizens can upload request evidence files" on storage.objects;
drop policy if exists "owners and assigned volunteers can upload request evidence files" on storage.objects;
create policy "owners and assigned volunteers can upload request evidence files"
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'request-evidence'
    and split_part(name, '/', 2) = auth.uid()::text
    and exists (
        select 1
        from public.help_requests hr
        where hr.id = public.request_evidence_request_id(name)
        and hr.status not in ('completed', 'cancelled')
        and (
            hr.citizen_id = auth.uid()
            or exists (
                select 1
                from public.help_request_volunteers hrv
                where hrv.request_id = hr.id
                and hrv.volunteer_id = auth.uid()
                and hrv.status in ('confirmed', 'in_progress')
            )
        )
    )
);

drop policy if exists "related users can read request evidence files" on storage.objects;
create policy "related users can read request evidence files"
on storage.objects
for select
to authenticated
using (
    bucket_id = 'request-evidence'
    and exists (
        select 1
        from public.help_requests hr
        where hr.id = public.request_evidence_request_id(name)
        and (
            hr.citizen_id = auth.uid()
            or public.current_app_role() in ('coordinator', 'admin')
            or exists (
                select 1
                from public.help_request_volunteers hrv
                where hrv.request_id = hr.id
                and hrv.volunteer_id = auth.uid()
            )
        )
    )
);

do $$
begin
    if to_regclass('public.activity_logs') is not null then
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
    end if;
end $$;
