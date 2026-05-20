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

alter table public.request_evidence
drop constraint if exists request_evidence_content_type_check;

alter table public.request_evidence
add constraint request_evidence_content_type_check
check (content_type = 'image/jpeg');

alter table public.request_evidence
drop constraint if exists request_evidence_file_size_check;

alter table public.request_evidence
add constraint request_evidence_file_size_check
check (file_size > 0 and file_size <= 5242880);

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
create or replace function public.can_view_request_evidence(p_request_id uuid, p_user_id uuid)
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
              hr.citizen_id = p_user_id
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

grant execute on function public.can_view_request_evidence(uuid, uuid)
to authenticated;

create or replace function public.can_upload_request_evidence(p_request_id uuid, p_user_id uuid)
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
          and hr.status not in ('completed', 'cancelled')
          and (
              hr.citizen_id = p_user_id
              or hr.volunteer_id = p_user_id
              or exists (
                  select 1
                  from public.help_request_volunteers hrv
                  where hrv.request_id = hr.id
                    and hrv.volunteer_id = p_user_id
                    and hrv.status in ('confirmed', 'in_progress')
              )
          )
    )
$$;

grant execute on function public.can_upload_request_evidence(uuid, uuid)
to authenticated;

create or replace function public.create_request_evidence_record(
    p_request_id uuid,
    p_file_path text,
    p_file_name text,
    p_content_type text,
    p_file_size integer
)
returns setof public.request_evidence
language plpgsql
security definer
set search_path = public
as $$
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to upload evidence.';
    end if;

    if p_content_type <> 'image/jpeg' then
        raise exception 'Only JPEG evidence photos are supported.';
    end if;

    if p_file_size <= 0 or p_file_size > 5242880 then
        raise exception 'Evidence photo must be 5 MB or smaller.';
    end if;

    if split_part(p_file_path, '/', 1)::uuid is distinct from p_request_id
       or lower(split_part(p_file_path, '/', 2)) is distinct from auth.uid()::text then
        raise exception 'Invalid evidence file path.';
    end if;

    if not public.can_upload_request_evidence(p_request_id, auth.uid()) then
        raise exception 'You do not have permission to upload evidence for this request.';
    end if;

    return query
    insert into public.request_evidence (
        request_id,
        uploaded_by,
        file_path,
        file_name,
        content_type,
        file_size
    )
    values (
        p_request_id,
        auth.uid(),
        p_file_path,
        p_file_name,
        p_content_type,
        p_file_size
    )
    returning *;
end;
$$;

grant execute on function public.create_request_evidence_record(
    uuid,
    text,
    text,
    text,
    integer
) to authenticated;

create policy "request evidence visible to related users"
on public.request_evidence
for select
to authenticated
using (public.can_view_request_evidence(request_evidence.request_id, auth.uid()));

drop policy if exists "citizens can insert evidence for own active requests" on public.request_evidence;
drop policy if exists "owners and assigned volunteers can insert evidence" on public.request_evidence;
create policy "owners and assigned volunteers can insert evidence"
on public.request_evidence
for insert
to authenticated
with check (
    uploaded_by = auth.uid()
    and public.can_upload_request_evidence(request_evidence.request_id, auth.uid())
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
    5242880,
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
drop policy if exists "authenticated users can upload request evidence files" on storage.objects;
create policy "owners and assigned volunteers can upload request evidence files"
on storage.objects
for insert
to authenticated
with check (
    bucket_id = 'request-evidence'
    and auth.uid() is not null
);

drop policy if exists "related users can read request evidence files" on storage.objects;
create policy "related users can read request evidence files"
on storage.objects
for select
to authenticated
using (
    bucket_id = 'request-evidence'
    and public.can_view_request_evidence(public.request_evidence_request_id(name), auth.uid())
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
