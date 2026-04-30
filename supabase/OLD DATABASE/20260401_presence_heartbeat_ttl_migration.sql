alter table if exists public.profiles
  add column if not exists presence_heartbeat_at timestamptz,
  add column if not exists presence_expires_at timestamptz;

update public.profiles
set presence_heartbeat_at = coalesce(
      presence_heartbeat_at,
      last_seen,
      last_seen_at,
      updated_at,
      created_at,
      now()
    ),
    presence_expires_at = coalesce(
      presence_expires_at,
      case
        when coalesce(is_online, false) then
          coalesce(
            presence_heartbeat_at,
            last_seen,
            last_seen_at,
            updated_at,
            created_at,
            now()
          ) + interval '2 minutes'
        else
          coalesce(
            presence_heartbeat_at,
            last_seen,
            last_seen_at,
            updated_at,
            created_at,
            now()
          )
      end
    )
where presence_heartbeat_at is null
   or presence_expires_at is null;

alter table if exists public.profiles
  alter column presence_heartbeat_at set default now(),
  alter column presence_expires_at set default (now() + interval '2 minutes');

alter table if exists public.profiles
  alter column presence_heartbeat_at set not null,
  alter column presence_expires_at set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_presence_expiry_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_presence_expiry_check
      check (presence_expires_at >= presence_heartbeat_at);
  end if;
end
$$;

create or replace function public.sync_profile_presence_columns()
returns trigger
language plpgsql
as $$
declare
  effective_last_seen timestamptz;
  heartbeat_at timestamptz;
begin
  if new.last_seen is null and new.last_seen_at is not null then
    new.last_seen = new.last_seen_at;
  elsif new.last_seen is not null and new.last_seen_at is null then
    new.last_seen_at = new.last_seen;
  elsif tg_op = 'UPDATE' and new.last_seen is distinct from old.last_seen then
    new.last_seen_at = new.last_seen;
  elsif tg_op = 'UPDATE' and new.last_seen_at is distinct from old.last_seen_at then
    new.last_seen = new.last_seen_at;
  end if;

  effective_last_seen := coalesce(new.last_seen_at, new.last_seen, now());
  heartbeat_at := coalesce(new.presence_heartbeat_at, effective_last_seen, now());
  new.presence_heartbeat_at = heartbeat_at;

  if coalesce(new.is_online, false) then
    new.presence_expires_at = greatest(
      coalesce(new.presence_expires_at, heartbeat_at + interval '2 minutes'),
      heartbeat_at + interval '2 minutes'
    );
  else
    new.presence_expires_at = effective_last_seen;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_profiles_sync_presence on public.profiles;
create trigger trg_profiles_sync_presence
before insert or update on public.profiles
for each row
execute function public.sync_profile_presence_columns();

create or replace function public.heartbeat_profile_presence()
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_row public.profiles;
  heartbeat_at timestamptz := now();
begin
  update public.profiles
  set is_online = true,
      last_seen = heartbeat_at,
      last_seen_at = heartbeat_at,
      presence_heartbeat_at = heartbeat_at,
      presence_expires_at = heartbeat_at + interval '2 minutes'
  where id = auth.uid()
  returning * into updated_row;

  if updated_row.id is null then
    raise exception 'Profile not found for current user.';
  end if;

  return updated_row;
end;
$$;

create or replace function public.set_profile_presence_offline()
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  updated_row public.profiles;
  heartbeat_at timestamptz := now();
begin
  update public.profiles
  set is_online = false,
      last_seen = heartbeat_at,
      last_seen_at = heartbeat_at,
      presence_heartbeat_at = heartbeat_at,
      presence_expires_at = heartbeat_at
  where id = auth.uid()
  returning * into updated_row;

  if updated_row.id is null then
    raise exception 'Profile not found for current user.';
  end if;

  return updated_row;
end;
$$;

grant execute on function public.heartbeat_profile_presence() to authenticated;
grant execute on function public.set_profile_presence_offline() to authenticated;
