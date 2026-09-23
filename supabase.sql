-- CrewMatch MVP database schema for Supabase
-- Run this file once in Supabase SQL Editor.

create extension if not exists pgcrypto;

create type public.connection_intent as enum ('dating','friends','both');
create type public.room_kind as enum ('global','ship','dating','shore_leave');
create type public.report_reason as enum ('harassment','fake_profile','underage','inappropriate_content','spam','other');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 2 and 40),
  gender text not null check (char_length(gender) between 1 and 40),
  interested_in text not null check (char_length(interested_in) between 1 and 80),
  intent public.connection_intent not null default 'both',
  cruise_company text check (char_length(cruise_company) <= 80),
  ship_name text check (char_length(ship_name) <= 80),
  department text check (char_length(department) <= 80),
  bio text check (char_length(bio) <= 500),
  avatar_url text,
  is_verified boolean not null default false,
  show_ship boolean not null default true,
  show_department boolean not null default true,
  allow_unmatched_messages boolean not null default false,
  last_seen_at timestamptz default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profile_private (
  id uuid primary key references public.profiles(id) on delete cascade,
  birth_date date not null check (birth_date <= current_date - interval '18 years'),
  created_at timestamptz not null default now()
);

create table public.likes (
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (sender_id, receiver_id),
  check (sender_id <> receiver_id)
);

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 80),
  kind public.room_kind not null,
  ship_name text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.room_messages (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.rooms(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now()
);

create table public.direct_messages (
  id bigint generated always as identity primary key,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now(),
  check (sender_id <> receiver_id)
);

create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table public.reports (
  id bigint generated always as identity primary key,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_id uuid not null references public.profiles(id) on delete cascade,
  reason public.report_reason not null,
  details text check (char_length(details) <= 1000),
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now(),
  check (reporter_id <> reported_id)
);

create index profiles_ship_idx on public.profiles(ship_name);
create index room_messages_room_created_idx on public.room_messages(room_id, created_at desc);
create index direct_messages_pair_idx on public.direct_messages(sender_id, receiver_id, created_at desc);
create index likes_receiver_idx on public.likes(receiver_id);

create or replace function public.is_match(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists(
    select 1 from public.likes x
    join public.likes y on y.sender_id=x.receiver_id and y.receiver_id=x.sender_id
    where x.sender_id=a and x.receiver_id=b
  );
$$;

create or replace function public.not_blocked(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select not exists(
    select 1 from public.blocks
    where (blocker_id=a and blocked_id=b) or (blocker_id=b and blocked_id=a)
  );
$$;

alter table public.profiles enable row level security;
alter table public.profile_private enable row level security;
alter table public.likes enable row level security;
alter table public.rooms enable row level security;
alter table public.room_messages enable row level security;
alter table public.direct_messages enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;

create policy "read own private profile data" on public.profile_private for select to authenticated using (auth.uid() = id);
create policy "create own private profile data" on public.profile_private for insert to authenticated with check (auth.uid() = id);
create policy "update own private profile data" on public.profile_private for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

create policy "authenticated profiles visible when not blocked" on public.profiles
for select to authenticated using (
  auth.uid() = id or public.not_blocked(auth.uid(), id)
);
create policy "create own profile" on public.profiles
for insert to authenticated with check (auth.uid() = id);
create policy "update own profile" on public.profiles
for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);
create policy "delete own profile" on public.profiles
for delete to authenticated using (auth.uid() = id);

create policy "read own likes" on public.likes for select to authenticated
using (auth.uid() in (sender_id, receiver_id));
create policy "send own likes" on public.likes for insert to authenticated
with check (auth.uid() = sender_id and public.not_blocked(sender_id, receiver_id));
create policy "remove own likes" on public.likes for delete to authenticated
using (auth.uid() = sender_id);

create policy "authenticated rooms visible" on public.rooms for select to authenticated using (is_active);
create policy "authenticated room messages visible" on public.room_messages for select to authenticated
using (public.not_blocked(auth.uid(), sender_id));
create policy "send own room messages" on public.room_messages for insert to authenticated
with check (auth.uid() = sender_id and char_length(trim(body)) > 0);

create policy "matched direct messages visible" on public.direct_messages for select to authenticated
using (
  auth.uid() in (sender_id, receiver_id)
  and public.is_match(sender_id, receiver_id)
  and public.not_blocked(sender_id, receiver_id)
);
create policy "matched users can message" on public.direct_messages for insert to authenticated
with check (
  auth.uid() = sender_id
  and public.is_match(sender_id, receiver_id)
  and public.not_blocked(sender_id, receiver_id)
);

create policy "own blocks visible" on public.blocks for select to authenticated using (auth.uid() = blocker_id);
create policy "create own blocks" on public.blocks for insert to authenticated with check (auth.uid() = blocker_id);
create policy "remove own blocks" on public.blocks for delete to authenticated using (auth.uid() = blocker_id);

create policy "create reports" on public.reports for insert to authenticated with check (auth.uid() = reporter_id);
create policy "read own reports" on public.reports for select to authenticated using (auth.uid() = reporter_id);

insert into public.rooms(name,kind) values
('Global Crew Chat','global'),
('Dating','dating'),
('Shore Leave','shore_leave')
on conflict do nothing;

alter publication supabase_realtime add table public.room_messages;
alter publication supabase_realtime add table public.direct_messages;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('avatars','avatars',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "public avatar viewing" on storage.objects for select using (bucket_id='avatars');
create policy "upload own avatar" on storage.objects for insert to authenticated
with check (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "update own avatar" on storage.objects for update to authenticated
using (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
create policy "delete own avatar" on storage.objects for delete to authenticated
using (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
