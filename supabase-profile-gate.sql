-- Run AFTER supabase.sql. For older installs, run supabase-privacy-migration.sql first.
-- The birth date and public profile are saved together, or neither is saved.
begin;

create or replace function public.has_adult_profile(target_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profile_private where id = target_id
  );
$$;

revoke all on function public.has_adult_profile(uuid) from public, anon;
grant execute on function public.has_adult_profile(uuid) to authenticated;

create or replace function public.save_crew_profile(
  p_display_name text,
  p_birth_date date,
  p_gender text,
  p_interested_in text,
  p_intent public.connection_intent,
  p_ship_name text,
  p_department text
)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  viewer_id uuid := auth.uid();
begin
  if viewer_id is null then
    raise exception 'Sign in before saving a profile';
  end if;
  if p_birth_date is null or p_birth_date > (current_date - interval '18 years')::date then
    raise exception 'CrewMatch is for adults aged 18 or older';
  end if;
  if char_length(trim(coalesce(p_display_name, ''))) < 2
     or char_length(trim(coalesce(p_gender, ''))) < 1
     or char_length(trim(coalesce(p_interested_in, ''))) < 1 then
    raise exception 'Complete name, gender and interested in';
  end if;

  insert into public.profiles
    (id, display_name, gender, interested_in, intent, ship_name, department)
  values
    (viewer_id, trim(p_display_name), trim(p_gender), trim(p_interested_in),
     p_intent, nullif(trim(p_ship_name), ''), nullif(trim(p_department), ''))
  on conflict (id) do update set
    display_name = excluded.display_name,
    gender = excluded.gender,
    interested_in = excluded.interested_in,
    intent = excluded.intent,
    ship_name = excluded.ship_name,
    department = excluded.department,
    updated_at = now();

  insert into public.profile_private (id, birth_date)
  values (viewer_id, p_birth_date)
  on conflict (id) do update set birth_date = excluded.birth_date;
end;
$$;

revoke all on function public.save_crew_profile(text,date,text,text,public.connection_intent,text,text) from public, anon;
grant execute on function public.save_crew_profile(text,date,text,text,public.connection_intent,text,text) to authenticated;

-- The RPC above is the only public-client path to create or edit a crew profile.
-- It cannot set is_verified; only an administrator with database privileges can.
drop policy if exists "create own profile" on public.profiles;
drop policy if exists "update own profile" on public.profiles;
drop policy if exists "create own private profile data" on public.profile_private;
drop policy if exists "update own private profile data" on public.profile_private;

drop policy if exists "authenticated profiles visible when not blocked" on public.profiles;
create policy "authenticated profiles visible when not blocked" on public.profiles
for select to authenticated using (
  auth.uid() = id or (
    public.has_adult_profile(auth.uid()) and public.has_adult_profile(id)
    and public.not_blocked(auth.uid(), id)
  )
);

drop policy if exists "read own likes" on public.likes;
create policy "read own likes" on public.likes for select to authenticated
using (auth.uid() in (sender_id, receiver_id) and public.has_adult_profile(auth.uid()));
drop policy if exists "send own likes" on public.likes;
create policy "send own likes" on public.likes for insert to authenticated
with check (
  auth.uid() = sender_id
  and public.has_adult_profile(auth.uid()) and public.has_adult_profile(receiver_id)
  and public.not_blocked(sender_id, receiver_id)
);

-- Only Global Chat exists in the current client. Other room kinds need membership rules first.
drop policy if exists "authenticated room messages visible" on public.room_messages;
create policy "authenticated room messages visible" on public.room_messages
for select to authenticated using (
  public.has_adult_profile(auth.uid())
  and public.not_blocked(auth.uid(), sender_id)
  and exists (select 1 from public.rooms r where r.id = room_id and r.kind = 'global' and r.is_active)
);
drop policy if exists "send own room messages" on public.room_messages;
create policy "send own room messages" on public.room_messages
for insert to authenticated with check (
  auth.uid() = sender_id and public.has_adult_profile(auth.uid())
  and char_length(trim(body)) > 0
  and exists (select 1 from public.rooms r where r.id = room_id and r.kind = 'global' and r.is_active)
);

drop policy if exists "matched direct messages visible" on public.direct_messages;
create policy "matched direct messages visible" on public.direct_messages
for select to authenticated using (
  auth.uid() in (sender_id, receiver_id)
  and public.has_adult_profile(sender_id) and public.has_adult_profile(receiver_id)
  and public.is_match(sender_id, receiver_id)
  and public.not_blocked(sender_id, receiver_id)
);
drop policy if exists "matched users can message" on public.direct_messages;
create policy "matched users can message" on public.direct_messages
for insert to authenticated with check (
  auth.uid() = sender_id
  and public.has_adult_profile(sender_id) and public.has_adult_profile(receiver_id)
  and public.is_match(sender_id, receiver_id)
  and public.not_blocked(sender_id, receiver_id)
);

notify pgrst, 'reload schema';
commit;
