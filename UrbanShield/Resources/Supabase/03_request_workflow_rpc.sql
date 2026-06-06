-- UrbanShield - Request lifecycle ve volunteer workflow RPC fonksiyonları
-- Bu dosya çoklu tablo etkileyen işlemleri backend tarafında güvenli şekilde yapar.
-- Client doğrudan kritik update yapmak yerine bu RPC fonksiyonlarını çağırır.

-- Critical requestler 3 volunteer alabilir; diğer urgency seviyeleri 1 volunteer alır.
create or replace function public.help_request_volunteer_capacity(p_urgency text)
returns integer
language sql
immutable
as $$
    select case
        when coalesce(p_urgency, 'medium') = 'critical' then 3
        else 1
    end
$$;

grant execute on function public.help_request_volunteer_capacity(text)
to authenticated;

-- Volunteer skill değerinin request type için uygun olup olmadığını kontrol eder.
create or replace function public.volunteer_skill_supports_request(p_skill text, p_request_type text)
returns boolean
language sql
immutable
as $$
    select case p_request_type
        when 'earthquake' then p_skill in ('search_rescue', 'medical', 'logistics', 'shelter')
        when 'fire' then p_skill in ('fire_response', 'medical', 'search_rescue')
        when 'flood' then p_skill in ('flood_rescue', 'transport', 'search_rescue', 'medical')
        when 'accident' then p_skill in ('medical', 'transport', 'search_rescue')
        when 'medical' then p_skill in ('medical', 'transport')
        when 'other' then true
        else false
    end
$$;

grant execute on function public.volunteer_skill_supports_request(text, text)
to authenticated;

-- Assignment insert/update öncesi kapasite, duplicate ve request uygunluğu kontrolü.
create or replace function public.enforce_help_request_volunteer_capacity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    request_record public.help_requests%rowtype;
    active_count integer;
    capacity integer;
begin
    if new.status not in ('confirmed', 'in_progress') then
        return new;
    end if;

    select *
    into request_record
    from public.help_requests
    where id = new.request_id
    for update;

    if request_record.id is null then
        raise exception 'Request could not be found.';
    end if;

    if request_record.status not in ('open', 'confirmed', 'in_progress') then
        raise exception 'This request is no longer accepting volunteers.';
    end if;

    if exists (
        select 1
        from public.help_request_volunteers hrv
        where hrv.request_id = new.request_id
          and hrv.volunteer_id = new.volunteer_id
          and hrv.status in ('confirmed', 'in_progress', 'completed')
          and (tg_op = 'INSERT' or hrv.id <> old.id)
    ) then
        raise exception 'This volunteer has already accepted this request.';
    end if;

    select count(*)
    into active_count
    from public.help_request_volunteers hrv
    where hrv.request_id = new.request_id
      and hrv.status in ('confirmed', 'in_progress')
      and (tg_op = 'INSERT' or hrv.id <> old.id);

    capacity := public.help_request_volunteer_capacity(request_record.urgency_level);

    if active_count >= capacity then
        raise exception 'This request already has the maximum number of active volunteers for its urgency.';
    end if;

    new.updated_at = now();
    new.accepted_at = coalesce(new.accepted_at, now());
    return new;
end;
$$;

drop trigger if exists enforce_help_request_volunteer_capacity_trigger on public.help_request_volunteers;
create trigger enforce_help_request_volunteer_capacity_trigger
before insert or update of status, request_id, volunteer_id
on public.help_request_volunteers
for each row
execute function public.enforce_help_request_volunteer_capacity();

-- Assignment status değişince ana help_requests satırını da güncel tutar.
-- Özellikle volunteer "Start Response" yaptığında assignment in_progress olur ve request de in_progress görünmelidir.
create or replace function public.sync_help_request_assignment_state()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    if new.status = 'confirmed' then
        update public.help_requests
        set volunteer_id = coalesce(volunteer_id, new.volunteer_id),
            status = case when status = 'open' then 'confirmed' else status end,
            confirmed_at = coalesce(confirmed_at, new.accepted_at),
            updated_at = now()
        where id = new.request_id
          and status in ('open', 'confirmed');
    elsif new.status = 'in_progress' then
        update public.help_requests
        set volunteer_id = coalesce(volunteer_id, new.volunteer_id),
            status = 'in_progress',
            updated_at = now()
        where id = new.request_id
          and status in ('open', 'confirmed', 'in_progress');
    elsif new.status = 'completed' then
        update public.help_requests
        set status = 'completed',
            completed_at = coalesce(completed_at, now()),
            updated_at = now()
        where id = new.request_id
          and status <> 'completed';

        perform public.release_volunteer_if_no_active_tasks(new.volunteer_id);
    elsif new.status = 'cancelled' then
        perform public.recalculate_help_request_after_assignment_change(new.request_id);
        perform public.release_volunteer_if_no_active_tasks(new.volunteer_id);
    end if;

    return new;
end;
$$;

drop trigger if exists sync_help_request_assignment_after_insert_update on public.help_request_volunteers;
create trigger sync_help_request_assignment_after_insert_update
after insert or update of status
on public.help_request_volunteers
for each row
execute function public.sync_help_request_assignment_state();

-- Request üzerindeki aktif assignment değiştiğinde ana request satırını en doğru assignment ile senkronlar.
create or replace function public.recalculate_help_request_after_assignment_change(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    next_assignment public.help_request_volunteers%rowtype;
begin
    select *
    into next_assignment
    from public.help_request_volunteers
    where request_id = p_request_id
      and status in ('in_progress', 'confirmed')
    order by
        case when status = 'in_progress' then 0 else 1 end,
        updated_at desc
    limit 1;

    if next_assignment.id is null then
        update public.help_requests
        set volunteer_id = null,
            status = case
                when status in ('confirmed', 'in_progress') then 'open'
                else status
            end,
            updated_at = now()
        where id = p_request_id
          and status in ('open', 'confirmed', 'in_progress');
    else
        update public.help_requests
        set volunteer_id = next_assignment.volunteer_id,
            status = case
                when status in ('completed', 'cancelled') then status
                else next_assignment.status
            end,
            confirmed_at = coalesce(confirmed_at, next_assignment.accepted_at),
            updated_at = now()
        where id = p_request_id;
    end if;
end;
$$;

-- Volunteer kullanıcının aktif taskı kalmadıysa tekrar available citizen durumuna döndürür.
create or replace function public.release_volunteer_if_no_active_tasks(p_volunteer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if p_volunteer_id is null then
        return;
    end if;

    if exists (
        select 1
        from public.help_request_volunteers
        where volunteer_id = p_volunteer_id
          and status in ('confirmed', 'in_progress')
    ) then
        return;
    end if;

    perform set_config('app.profile_automation', 'volunteer_release', true);

    update public.profiles
    set role = case
            when role = 'volunteer' then 'citizen'
            else role
        end,
        availability_status = case
            when coalesce(is_suspended, false) then 'offline'
            else 'available'
        end
    where id = p_volunteer_id;
end;
$$;

-- Profile update guard.
-- Normal client akışında kullanıcı kendi rolünü admin/coordinator yapamaz.
-- Volunteer rol değişimi yalnızca assignment/RPC otomasyonu sırasında izinlidir.
create or replace function public.prevent_invalid_profile_role_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    requester_role text;
    requester_is_suspended boolean;
begin
    if current_setting('app.profile_automation', true) in ('volunteer_acceptance', 'volunteer_release') then
        return new;
    end if;

    select role, coalesce(is_suspended, false)
    into requester_role, requester_is_suspended
    from public.profiles
    where id = auth.uid();

    if requester_is_suspended then
        raise exception 'This account is suspended.';
    end if;

    if requester_role = 'admin' then
        return new;
    end if;

    if new.is_suspended is distinct from old.is_suspended then
        raise exception 'Only admins can suspend or reactivate accounts.';
    end if;

    if new.role is distinct from old.role then
        raise exception 'Role changes are not allowed from this client flow.';
    end if;

    return new;
end;
$$;

drop trigger if exists prevent_invalid_profile_role_change_trigger on public.profiles;
create trigger prevent_invalid_profile_role_change_trigger
before update
on public.profiles
for each row
execute function public.prevent_invalid_profile_role_change();

-- Help request update guard.
-- Coordinator/admin doğrudan update yaparsa yalnızca status/assignment benzeri güvenli alanlara izin verilir.
create or replace function public.prevent_invalid_help_request_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
    requester_role text;
begin
    select public.current_app_role()
    into requester_role;

    if requester_role in ('coordinator', 'admin') then
        if new.id is distinct from old.id
           or new.citizen_id is distinct from old.citizen_id
           or new.request_type is distinct from old.request_type
           or new.description is distinct from old.description
           or new.urgency_level is distinct from old.urgency_level
           or new.latitude is distinct from old.latitude
           or new.longitude is distinct from old.longitude
           or new.created_at is distinct from old.created_at then
            raise exception 'Coordinators can only update status or assignment fields.';
        end if;

        if new.status is distinct from old.status
           and not (
               (old.status = 'open' and new.status = 'cancelled')
               or (old.status = 'confirmed' and new.status in ('in_progress', 'cancelled'))
               or (old.status = 'in_progress' and new.status in ('completed', 'cancelled'))
               or (old.status = new.status)
           ) then
            raise exception 'Invalid coordinator status transition.';
        end if;
    end if;

    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists prevent_invalid_help_request_update_trigger on public.help_requests;
create trigger prevent_invalid_help_request_update_trigger
before update
on public.help_requests
for each row
execute function public.prevent_invalid_help_request_update();

-- Nearby ekranında request kartlarında gösterilen aktif volunteer sayıları.
create or replace function public.get_help_request_active_volunteer_counts(p_request_ids uuid[])
returns table(request_id uuid, active_volunteer_count integer)
language sql
security definer
set search_path = public
stable
as $$
    select hrv.request_id, count(*)::integer as active_volunteer_count
    from public.help_request_volunteers hrv
    where hrv.request_id = any(p_request_ids)
      and hrv.status in ('confirmed', 'in_progress')
    group by hrv.request_id
$$;

grant execute on function public.get_help_request_active_volunteer_counts(uuid[])
to authenticated;

-- Mevcut kullanıcının request kabul etmeye uygun olup olmadığını döndürür.
create or replace function public.get_my_volunteer_acceptance_state()
returns table(availability_status text, active_assignment_count integer)
language sql
security definer
set search_path = public
stable
as $$
    select
        p.availability_status,
        (
            select count(*)::integer
            from public.help_request_volunteers hrv
            where hrv.volunteer_id = auth.uid()
              and hrv.status in ('confirmed', 'in_progress')
        ) as active_assignment_count
    from public.profiles p
    where p.id = auth.uid()
$$;

grant execute on function public.get_my_volunteer_acceptance_state()
to authenticated;

-- Citizen kullanıcının request kabul ederek active volunteer olmasını sağlar.
create or replace function public.accept_help_request_as_volunteer(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    request_record public.help_requests%rowtype;
    requester_profile public.profiles%rowtype;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to accept a request.';
    end if;

    select *
    into requester_profile
    from public.profiles
    where id = auth.uid()
    for update;

    if requester_profile.id is null then
        raise exception 'Profile could not be found.';
    end if;

    if coalesce(requester_profile.is_suspended, false) then
        raise exception 'This account is suspended.';
    end if;

    select *
    into request_record
    from public.help_requests
    where id = p_request_id
    for update;

    if request_record.id is null then
        raise exception 'Request could not be found.';
    end if;

    if request_record.citizen_id = auth.uid() then
        raise exception 'You cannot volunteer for your own request.';
    end if;

    if request_record.status not in ('open', 'confirmed') then
        raise exception 'This request is no longer accepting volunteers.';
    end if;

    if requester_profile.availability_status is distinct from 'available' then
        raise exception 'You must be available before accepting a request.';
    end if;

    if not exists (
        select 1
        from unnest(requester_profile.volunteer_skills) as skill(value)
        where public.volunteer_skill_supports_request(skill.value, request_record.request_type)
    ) then
        raise exception 'Your volunteer skills do not match this request type.';
    end if;

    if exists (
        select 1
        from public.help_request_volunteers
        where volunteer_id = auth.uid()
          and status in ('confirmed', 'in_progress')
    ) then
        raise exception 'Complete your active volunteer task before accepting another request.';
    end if;

    insert into public.help_request_volunteers (
        request_id,
        volunteer_id,
        status,
        accepted_at,
        updated_at
    )
    values (
        p_request_id,
        auth.uid(),
        'confirmed',
        now(),
        now()
    );

    update public.help_requests
    set volunteer_id = coalesce(volunteer_id, auth.uid()),
        status = case when status = 'open' then 'confirmed' else status end,
        confirmed_at = coalesce(confirmed_at, now()),
        updated_at = now()
    where id = p_request_id
      and status in ('open', 'confirmed');

    perform set_config('app.profile_automation', 'volunteer_acceptance', true);

    update public.profiles
    set role = 'volunteer',
        availability_status = 'busy'
    where id = auth.uid();
end;
$$;

grant execute on function public.accept_help_request_as_volunteer(uuid)
to authenticated;

-- Confirmed volunteer taskını response başlamadan iptal eder.
create or replace function public.cancel_my_confirmed_volunteer_task(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    active_assignment_id uuid;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to cancel this task.';
    end if;

    select id
    into active_assignment_id
    from public.help_request_volunteers
    where request_id = p_request_id
      and volunteer_id = auth.uid()
      and status = 'confirmed'
    order by updated_at desc
    limit 1
    for update;

    if active_assignment_id is null then
        raise exception 'Only confirmed volunteer tasks can be cancelled before response starts.';
    end if;

    update public.help_request_volunteers
    set status = 'cancelled',
        updated_at = now()
    where id = active_assignment_id;

    perform public.recalculate_help_request_after_assignment_change(p_request_id);
    perform public.release_volunteer_if_no_active_tasks(auth.uid());
end;
$$;

grant execute on function public.cancel_my_confirmed_volunteer_task(uuid)
to authenticated;

-- In-progress volunteer taskını tamamlar.
create or replace function public.complete_my_volunteer_task(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    active_assignment_id uuid;
begin
    if auth.uid() is null then
        raise exception 'You must be signed in to complete this task.';
    end if;

    select id
    into active_assignment_id
    from public.help_request_volunteers
    where request_id = p_request_id
      and volunteer_id = auth.uid()
      and status = 'in_progress'
    order by updated_at desc
    limit 1
    for update;

    if active_assignment_id is null then
        raise exception 'Only your in-progress volunteer task can be completed.';
    end if;

    update public.help_request_volunteers
    set status = 'completed',
        completed_at = now(),
        updated_at = now()
    where id = active_assignment_id;

    update public.help_requests
    set status = 'completed',
        completed_at = now(),
        updated_at = now()
    where id = p_request_id
      and status = 'in_progress';

    perform public.release_volunteer_if_no_active_tasks(auth.uid());
end;
$$;

grant execute on function public.complete_my_volunteer_task(uuid)
to authenticated;

-- Coordinator/admin request status değiştirir.
create or replace function public.coordinator_update_help_request_status(
    p_request_id uuid,
    p_status text
)
returns setof public.help_requests
language plpgsql
security definer
set search_path = public
as $$
declare
    requester_role text;
    request_record public.help_requests%rowtype;
    assignment_record record;
begin
    requester_role := public.current_app_role();

    if requester_role not in ('coordinator', 'admin') then
        raise exception 'Only coordinators can update request status.';
    end if;

    if p_status not in ('in_progress', 'completed', 'cancelled') then
        raise exception 'Invalid coordinator status target.';
    end if;

    select *
    into request_record
    from public.help_requests
    where id = p_request_id
    for update;

    if request_record.id is null then
        raise exception 'Request could not be found.';
    end if;

    if not (
        (request_record.status = 'open' and p_status = 'cancelled')
        or (request_record.status = 'confirmed' and p_status in ('in_progress', 'cancelled'))
        or (request_record.status = 'in_progress' and p_status in ('completed', 'cancelled'))
    ) then
        raise exception 'This status change is not available for the selected request.';
    end if;

    if p_status = 'in_progress' then
        update public.help_request_volunteers
        set status = 'in_progress',
            started_at = coalesce(started_at, now()),
            updated_at = now()
        where request_id = p_request_id
          and status = 'confirmed';
    elsif p_status in ('completed', 'cancelled') then
        for assignment_record in
            select volunteer_id
            from public.help_request_volunteers
            where request_id = p_request_id
              and status in ('confirmed', 'in_progress')
        loop
            update public.help_request_volunteers
            set status = p_status,
                completed_at = case when p_status = 'completed' then coalesce(completed_at, now()) else completed_at end,
                updated_at = now()
            where request_id = p_request_id
              and volunteer_id = assignment_record.volunteer_id
              and status in ('confirmed', 'in_progress');

            perform public.release_volunteer_if_no_active_tasks(assignment_record.volunteer_id);
        end loop;
    end if;

    update public.help_requests
    set status = p_status,
        completed_at = case when p_status = 'completed' then coalesce(completed_at, now()) else completed_at end,
        updated_at = now()
    where id = p_request_id;

    return query
    select *
    from public.help_requests
    where id = p_request_id;
end;
$$;

grant execute on function public.coordinator_update_help_request_status(uuid, text)
to authenticated;

-- Coordinator/admin uygun volunteer kullanıcıyı requeste atar.
create or replace function public.coordinator_assign_volunteer_to_request(
    p_request_id uuid,
    p_volunteer_id uuid
)
returns setof public.help_requests
language plpgsql
security definer
set search_path = public
as $$
declare
    requester_role text;
    request_record public.help_requests%rowtype;
    volunteer_profile public.profiles%rowtype;
begin
    requester_role := public.current_app_role();

    if requester_role not in ('coordinator', 'admin') then
        raise exception 'Only coordinators can assign volunteers.';
    end if;

    select *
    into request_record
    from public.help_requests
    where id = p_request_id
    for update;

    if request_record.id is null then
        raise exception 'Request could not be found.';
    end if;

    if request_record.status not in ('open', 'confirmed', 'in_progress') then
        raise exception 'This request is no longer accepting volunteers.';
    end if;

    select *
    into volunteer_profile
    from public.profiles
    where id = p_volunteer_id
    for update;

    if volunteer_profile.id is null then
        raise exception 'Volunteer profile could not be found.';
    end if;

    if coalesce(volunteer_profile.is_suspended, false)
       or volunteer_profile.availability_status is distinct from 'available' then
        raise exception 'This volunteer is not available.';
    end if;

    if not exists (
        select 1
        from unnest(volunteer_profile.volunteer_skills) as skill(value)
        where public.volunteer_skill_supports_request(skill.value, request_record.request_type)
    ) then
        raise exception 'This volunteer does not match the request type.';
    end if;

    if exists (
        select 1
        from public.help_request_volunteers
        where volunteer_id = p_volunteer_id
          and status in ('confirmed', 'in_progress')
    ) then
        raise exception 'This volunteer already has an active task.';
    end if;

    insert into public.help_request_volunteers (
        request_id,
        volunteer_id,
        status,
        accepted_at,
        updated_at
    )
    values (
        p_request_id,
        p_volunteer_id,
        'confirmed',
        now(),
        now()
    );

    update public.help_requests
    set volunteer_id = coalesce(volunteer_id, p_volunteer_id),
        status = case when status = 'open' then 'confirmed' else status end,
        confirmed_at = coalesce(confirmed_at, now()),
        updated_at = now()
    where id = p_request_id;

    perform set_config('app.profile_automation', 'volunteer_acceptance', true);

    update public.profiles
    set role = 'volunteer',
        availability_status = 'busy'
    where id = p_volunteer_id;

    return query
    select *
    from public.help_requests
    where id = p_request_id;
end;
$$;

grant execute on function public.coordinator_assign_volunteer_to_request(uuid, uuid)
to authenticated;

-- Admin kullanıcıyı suspend/reactivate eder.
-- Kullanıcı active volunteer ise assignmentları iptal edilir ve request kapasitesi yeniden hesaplanır.
create or replace function public.set_profile_suspension(
    p_user_id uuid,
    p_is_suspended boolean
)
returns setof public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
    affected_request_ids uuid[];
    affected_request_id uuid;
begin
    if public.current_app_role() is distinct from 'admin' then
        raise exception 'Only admins can suspend or reactivate accounts.';
    end if;

    if p_user_id = auth.uid() then
        raise exception 'You cannot suspend your own admin account from the app.';
    end if;

    if p_is_suspended then
        select coalesce(array_agg(distinct request_id), array[]::uuid[])
        into affected_request_ids
        from public.help_request_volunteers
        where volunteer_id = p_user_id
          and status in ('confirmed', 'in_progress');

        update public.help_request_volunteers
        set status = 'cancelled',
            updated_at = now()
        where volunteer_id = p_user_id
          and status in ('confirmed', 'in_progress');

        foreach affected_request_id in array affected_request_ids loop
            perform public.recalculate_help_request_after_assignment_change(affected_request_id);
        end loop;

        perform set_config('app.profile_automation', 'volunteer_release', true);

        update public.profiles
        set is_suspended = true,
            role = case when role = 'volunteer' then 'citizen' else role end,
            availability_status = 'offline'
        where id = p_user_id;
    else
        update public.profiles
        set is_suspended = false,
            availability_status = case when availability_status = 'offline' then 'available' else availability_status end
        where id = p_user_id;
    end if;

    return query
    select *
    from public.profiles
    where id = p_user_id;
end;
$$;

grant execute on function public.set_profile_suspension(uuid, boolean)
to authenticated;
