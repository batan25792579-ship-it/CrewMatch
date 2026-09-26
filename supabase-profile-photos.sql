begin;

create table if not exists public.profile_photos (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  storage_path text not null unique,
  position smallint not null check (position between 0 and 5),
  created_at timestamptz not null default now(),
  unique (profile_id, position),
  constraint profile_photos_owner_path check (storage_path like profile_id::text || '/%.jpg')
);

alter table public.profile_photos enable row level security;
revoke all on public.profile_photos from anon;
grant select, insert, delete on public.profile_photos to authenticated;

drop policy if exists "read visible profile photos" on public.profile_photos;
create policy "read visible profile photos" on public.profile_photos
for select to authenticated using (
  profile_id = (select auth.uid())
  or (
    public.has_adult_profile((select auth.uid()))
    and public.has_adult_profile(profile_id)
    and public.not_blocked((select auth.uid()), profile_id)
  )
);

drop policy if exists "add own profile photos" on public.profile_photos;
create policy "add own profile photos" on public.profile_photos
for insert to authenticated with check (
  profile_id = (select auth.uid()) and public.has_adult_profile((select auth.uid()))
);

drop policy if exists "remove own profile photos" on public.profile_photos;
create policy "remove own profile photos" on public.profile_photos
for delete to authenticated using (profile_id = (select auth.uid()));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('crew-photos','crew-photos',false,2097152,array['image/jpeg'])
on conflict (id) do nothing;

drop policy if exists "read permitted crew photos" on storage.objects;
create policy "read permitted crew photos" on storage.objects
for select to authenticated using (
  bucket_id = 'crew-photos'
  and public.has_adult_profile((select auth.uid()))
  and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or exists (
      select 1 from public.profile_photos p where p.storage_path = storage.objects.name
    )
  )
);

drop policy if exists "upload own crew photos" on storage.objects;
create policy "upload own crew photos" on storage.objects
for insert to authenticated with check (
  bucket_id = 'crew-photos'
  and public.has_adult_profile((select auth.uid()))
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists "delete own crew photos" on storage.objects;
create policy "delete own crew photos" on storage.objects
for delete to authenticated using (
  bucket_id = 'crew-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

notify pgrst, 'reload schema';
commit;
