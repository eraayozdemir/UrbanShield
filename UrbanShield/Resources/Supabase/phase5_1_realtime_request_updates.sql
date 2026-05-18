-- Phase 5.1: Realtime request updates
-- Keeps the publication narrow so Free plan usage stays controlled.

do $$
begin
    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'help_requests'
    ) then
        alter publication supabase_realtime add table public.help_requests;
    end if;

    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'help_request_volunteers'
    ) then
        alter publication supabase_realtime add table public.help_request_volunteers;
    end if;

    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'request_evidence'
    ) then
        alter publication supabase_realtime add table public.request_evidence;
    end if;

    if not exists (
        select 1
        from pg_publication_tables
        where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'coordination_logs'
    ) then
        alter publication supabase_realtime add table public.coordination_logs;
    end if;
end $$;
