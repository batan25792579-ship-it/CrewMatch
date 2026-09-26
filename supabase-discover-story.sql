begin;

create table if not exists public.profile_prompts (
  profile_id uuid not null references public.profiles(id) on delete cascade,
  position smallint not null check (position between 0 and 2),
  prompt text not null check (prompt in ('best_port','off_duty','meet_crew','sea_story','shore_leave','fun_fact')),
  answer text not null check (char_length(btrim(answer)) between 1 and 240),
  primary key (profile_id, position),
  unique (profile_id, prompt)
);

alter table public.profile_prompts enable row level security;
revoke all on public.profile_prompts from anon, authenticated;
grant select on public.profile_prompts to authenticated;

drop policy if exists "view permitted crew prompts" on public.profile_prompts;
create policy "view permitted crew prompts" on public.profile_prompts
for select to authenticated using (
  profile_id = (select auth.uid())
  or (
    public.has_adult_profile((select auth.uid()))
    and public.has_adult_profile(profile_id)
    and public.not_blocked((select auth.uid()), profile_id)
  )
);

create or replace function public.save_crew_story(p_bio text, p_prompts jsonb)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  viewer_id uuid := auth.uid();
  item jsonb;
  prompt_key text;
  prompt_answer text;
  place smallint := 0;
begin
  if viewer_id is null or not public.has_adult_profile(viewer_id) then
    raise exception 'Complete your adult crew profile first';
  end if;
  if char_length(btrim(coalesce(p_bio,''))) > 500 then
    raise exception 'Bio must be 500 characters or fewer';
  end if;
  if p_prompts is null or jsonb_typeof(p_prompts) <> 'array' then
    raise exception 'Choose up to three profile questions';
  end if;
  if jsonb_array_length(p_prompts) > 3 then
    raise exception 'Choose up to three profile questions';
  end if;
  for item in select value from jsonb_array_elements(p_prompts)
  loop
    prompt_key := item->>'prompt';
    prompt_answer := btrim(coalesce(item->>'answer',''));
    if prompt_key not in ('best_port','off_duty','meet_crew','sea_story','shore_leave','fun_fact')
       or char_length(prompt_answer) not between 1 and 240 then
      raise exception 'Each question needs an answer of 1 to 240 characters';
    end if;
    place := place + 1;
  end loop;

  update public.profiles
  set bio = nullif(btrim(coalesce(p_bio,'')),''), updated_at = now()
  where id = viewer_id;

  delete from public.profile_prompts where profile_id = viewer_id;
  place := 0;
  for item in select value from jsonb_array_elements(p_prompts)
  loop
    insert into public.profile_prompts(profile_id,position,prompt,answer)
    values(viewer_id,place,item->>'prompt',btrim(item->>'answer'));
    place := place + 1;
  end loop;
end;
$$;

revoke all on function public.save_crew_story(text,jsonb) from public, anon;
grant execute on function public.save_crew_story(text,jsonb) to authenticated;

create index if not exists profiles_intent_id_idx on public.profiles(intent,id);

create or replace function public.discover_crew(
  p_after uuid,
  p_limit integer,
  p_goal text
)
returns table (
  id uuid,
  display_name text,
  intent public.connection_intent,
  ship_name text,
  department text,
  bio text,
  avatar_url text,
  is_verified boolean,
  show_ship boolean,
  show_department boolean
)
language sql stable security invoker set search_path = ''
as $$
  select p.id,p.display_name,p.intent,
         case when p.show_ship then p.ship_name else null end,
         case when p.show_department then p.department else null end,
         p.bio,p.avatar_url,p.is_verified,p.show_ship,p.show_department
  from public.profiles p
  where auth.uid() is not null
    and p.id <> auth.uid()
    and (p_after is null or p.id > p_after)
    and p_goal in ('all','friends','dating')
    and (p_goal = 'all' or p.intent::text = p_goal or p.intent = 'both'::public.connection_intent)
    and not exists (
      select 1 from public.likes l
      where l.sender_id = auth.uid() and l.receiver_id = p.id
    )
  order by p.id
  limit greatest(1, least(coalesce(p_limit,31),31));
$$;

revoke all on function public.discover_crew(uuid,integer,text) from public, anon;
grant execute on function public.discover_crew(uuid,integer,text) to authenticated;

notify pgrst, 'reload schema';
commit;
