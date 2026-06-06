-- UrbanShield - Genel izinler
-- Supabase API, authenticated rolü üzerinden public schema tablolarına erişir.
-- Bu grantler tablo erişimini açar; gerçek veri sınırını RLS policy kuralları belirler.

grant usage on schema public to authenticated;

grant select, insert, update on public.profiles to authenticated;
grant select, insert, update on public.help_requests to authenticated;
grant select, insert, update on public.help_request_volunteers to authenticated;
grant select, insert on public.request_evidence to authenticated;
grant select, insert, update on public.coordination_logs to authenticated;
grant select, insert, update on public.supply_support_actions to authenticated;
grant select, insert, update on public.emergency_announcements to authenticated;
grant select, insert, update on public.suspicious_activity_reports to authenticated;
grant select, insert on public.moderation_actions to authenticated;
grant select, insert on public.activity_logs to authenticated;
grant select, insert, update on public.notifications to authenticated;

-- RPC fonksiyonlarının uygulama tarafından çağrılabilmesi için execute izni.
grant execute on all functions in schema public to authenticated;

