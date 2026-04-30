alter table public.profiles
  add column if not exists gender text;

update public.profiles
set gender = case
  when avatar_id in ('avatar_4', 'avatar_5', 'avatar_6') then 'female'
  else 'male'
end
where gender is null
   or btrim(gender) = '';

alter table public.profiles
  alter column gender set default 'male';

alter table public.profiles
  alter column gender set not null;

update public.profiles
set avatar_id = case
  when gender = 'female' and avatar_id not in ('avatar_4', 'avatar_5', 'avatar_6') then 'avatar_4'
  when gender = 'male' and avatar_id not in ('avatar_1', 'avatar_2', 'avatar_3') then 'avatar_1'
  else avatar_id
end;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_gender_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_gender_check
      check (gender in ('male', 'female'));
  end if;
end
$$;

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'profiles_avatar_id_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles drop constraint profiles_avatar_id_check;
  end if;

  alter table public.profiles
    add constraint profiles_avatar_id_check
    check (
      (gender = 'male' and avatar_id in ('avatar_1', 'avatar_2', 'avatar_3'))
      or (gender = 'female' and avatar_id in ('avatar_4', 'avatar_5', 'avatar_6'))
    );
end
$$;
