-- UrbanShield - Auth/Profile temel kurulumu
-- Bu dosya kullanıcı profili tablosunu, rol/availability kurallarını ve temel RLS politikalarını oluşturur.
-- Supabase Auth kullanıcıları auth.users tablosunda durur; uygulamanın kullandığı profil bilgisi public.profiles içindedir.

create extension if not exists pgcrypto;

-- Kullanıcı profili tablosu.
-- id değeri Supabase Auth kullanıcısının auth.users.id değeriyle aynıdır.
create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    email text not null unique,
    full_name text not null,
    role text not null default 'citizen',
    availability_status text not null default 'available',
    volunteer_skills text[] not null default '{}',
    is_suspended boolean not null default false,
    created_at timestamptz not null default now()
);

-- Enum yerine check constraint kullanıyoruz; Swift tarafındaki enum rawValue değerleriyle birebir uyumlu olmalı.
alter table public.profiles
drop constraint if exists profiles_role_check;

alter table public.profiles
add constraint profiles_role_check
check (role in ('citizen', 'volunteer', 'coordinator', 'admin'));

alter table public.profiles
drop constraint if exists profiles_availability_status_check;

alter table public.profiles
add constraint profiles_availability_status_check
check (availability_status in ('available', 'busy', 'offline'));

alter table public.profiles
drop constraint if exists profiles_volunteer_skills_check;

alter table public.profiles
add constraint profiles_volunteer_skills_check
check (
    volunteer_skills <@ array[
        'medical',
        'search_rescue',
        'transport',
        'fire_response',
        'flood_rescue',
        'logistics',
        'shelter',
        'communication',
        'other'
    ]::text[]
);

create index if not exists profiles_role_idx
on public.profiles(role);

create index if not exists profiles_availability_status_idx
on public.profiles(availability_status);

create index if not exists profiles_is_suspended_idx
on public.profiles(is_suspended);

-- Giriş yapan kullanıcının uygulama rolünü döndürür.
-- Suspended kullanıcıyı ayrı bir sanal rol gibi ele alıyoruz; böylece RLS/RPC kontrolleri daha okunabilir oluyor.
create or replace function public.current_app_role()
returns text
language sql
security definer
set search_path = public
stable
as $$
    select case
        when coalesce(is_suspended, false) then 'suspended'
        else role
    end
    from public.profiles
    where id = auth.uid()
    limit 1
$$;

grant execute on function public.current_app_role()
to authenticated;

alter table public.profiles enable row level security;

drop policy if exists "profiles are visible to authenticated users" on public.profiles;
create policy "profiles are visible to authenticated users"
on public.profiles
for select
to authenticated
using (true);

drop policy if exists "users can create own citizen profile" on public.profiles;
create policy "users can create own citizen profile"
on public.profiles
for insert
to authenticated
with check (
    id = auth.uid()
    and role = 'citizen'
    and availability_status in ('available', 'offline')
    and not coalesce(is_suspended, false)
);

drop policy if exists "users can update own basic profile" on public.profiles;
create policy "users can update own basic profile"
on public.profiles
for update
to authenticated
using (
    id = auth.uid()
    and public.current_app_role() not in ('suspended')
)
with check (
    id = auth.uid()
    and public.current_app_role() not in ('suspended')
);

drop policy if exists "admins can update all profiles" on public.profiles;
create policy "admins can update all profiles"
on public.profiles
for update
to authenticated
using (public.current_app_role() = 'admin')
with check (public.current_app_role() = 'admin');

