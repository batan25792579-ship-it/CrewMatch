-- CrewMatch privacy migration
-- Run once if you already applied the earlier schema that stored birth_date in public.profiles.
-- This moves date of birth into an owner-only table, then removes it from public profile data.

create table if not exists public.profile_private (
  id uuid primary key references public.profiles(id) on delete cascade,
  birth_date date not null check (birth_date <= current_date - interval '18 years'),
  created_at timestamptz not null default now()
);

insert into public.profile_private(id,birth_date)
select id,birth_date from public.profiles
on conflict (id) do nothing;

alter table public.profiles drop column if exists birth_date;
alter table public.profile_private enable row level security;

drop policy if exists "read own private profile data" on public.profile_private;
drop policy if exists "create own private profile data" on public.profile_private;
drop policy if exists "update own private profile data" on public.profile_private;

create policy "read own private profile data" on public.profile_private
for select to authenticated using (auth.uid() = id);
create policy "create own private profile data" on public.profile_private
for insert to authenticated with check (auth.uid() = id);
create policy "update own private profile data" on public.profile_private
for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);
