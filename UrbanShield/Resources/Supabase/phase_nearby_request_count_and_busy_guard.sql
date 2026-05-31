-- Fix Nearby Requests volunteer count display and busy volunteer acceptance guard.
--
-- Why this is needed:
-- - RLS can hide other volunteers' help_request_volunteers rows from the client.
--   The app should not read those rows directly just to show "1/1 volunteers".
-- - The app can have a stale local profile after role/availability automation.
--   Acceptance should check the current database state immediately before the RPC.

create or replace function public.get_help_request_active_volunteer_counts(
    p_request_ids uuid[]
)
returns table (
    request_id uuid,
    active_volunteer_count integer
)
language sql
security definer
set search_path = public
stable
as $$
    select
        hr.id as request_id,
        count(hrv.id)::integer as active_volunteer_count
    from public.help_requests hr
    left join public.help_request_volunteers hrv
        on hrv.request_id = hr.id
       and hrv.status in ('confirmed', 'in_progress')
    where auth.uid() is not null
      and hr.id = any(coalesce(p_request_ids, array[]::uuid[]))
    group by hr.id;
$$;

revoke all on function public.get_help_request_active_volunteer_counts(uuid[]) from public;
grant execute on function public.get_help_request_active_volunteer_counts(uuid[]) to authenticated;

create or replace function public.get_my_volunteer_acceptance_state()
returns table (
    availability_status text,
    active_assignment_count integer
)
language sql
security definer
set search_path = public
stable
as $$
    select
        coalesce(p.availability_status, 'available') as availability_status,
        count(hrv.id)::integer as active_assignment_count
    from public.profiles p
    left join public.help_request_volunteers hrv
        on hrv.volunteer_id = p.id
       and hrv.status in ('confirmed', 'in_progress')
    where p.id = auth.uid()
    group by p.availability_status;
$$;

revoke all on function public.get_my_volunteer_acceptance_state() from public;
grant execute on function public.get_my_volunteer_acceptance_state() to authenticated;
