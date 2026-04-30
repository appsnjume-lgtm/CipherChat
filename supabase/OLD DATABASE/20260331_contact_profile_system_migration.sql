-- Contact profile system migration.
-- This migration is additive and backward-compatible with the existing
-- CipherChat chat/message schema and prior settings/privacy migrations.

create extension if not exists pgcrypto;

alter table if exists public.profiles
  add column if not exists profile_image_url text,
  add column if not exists bio text,
  add column if not exists gender text,
  add column if not exists gender_visibility text,
  add column if not exists profile_photo_visibility text,
  add column if not exists last_seen_visibility text,
  add column if not exists about_visibility text,
  add column if not exists account_privacy text,
  add column if not exists last_seen timestamptz,
  add column if not exists is_online boolean;

update public.profiles
set bio = coalesce(nullif(btrim(bio), ''), ''),
    gender = coalesce(nullif(btrim(gender), ''), 'male'),
    gender_visibility = coalesce(nullif(btrim(gender_visibility), ''), 'everyone'),
    profile_photo_visibility = coalesce(nullif(btrim(profile_photo_visibility), ''), 'everyone'),
    last_seen_visibility = coalesce(nullif(btrim(last_seen_visibility), ''), 'everyone'),
    about_visibility = coalesce(nullif(btrim(about_visibility), ''), 'everyone'),
    account_privacy = coalesce(nullif(btrim(account_privacy), ''), 'public'),
    last_seen = coalesce(last_seen, last_seen_at, updated_at, created_at, now()),
    is_online = coalesce(is_online, false)
where bio is null
   or gender is null
   or gender_visibility is null
   or profile_photo_visibility is null
   or last_seen_visibility is null
   or about_visibility is null
   or account_privacy is null
   or last_seen is null
   or is_online is null;

alter table if exists public.profiles
  alter column bio set default '',
  alter column gender set default 'male',
  alter column gender_visibility set default 'everyone',
  alter column profile_photo_visibility set default 'everyone',
  alter column last_seen_visibility set default 'everyone',
  alter column about_visibility set default 'everyone',
  alter column account_privacy set default 'public',
  alter column last_seen set default now(),
  alter column is_online set default false;

alter table if exists public.profiles
  alter column bio set not null,
  alter column gender set not null,
  alter column gender_visibility set not null,
  alter column profile_photo_visibility set not null,
  alter column last_seen_visibility set not null,
  alter column about_visibility set not null,
  alter column account_privacy set not null,
  alter column last_seen set not null,
  alter column is_online set not null;

do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'profiles_gender_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles drop constraint profiles_gender_check;
  end if;

  alter table public.profiles
    add constraint profiles_gender_check
    check (gender in ('male', 'female', 'other', 'prefer_not_to_say'));
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_gender_visibility_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_gender_visibility_check
      check (gender_visibility in ('everyone', 'contacts', 'nobody'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_photo_visibility_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_photo_visibility_check
      check (profile_photo_visibility in ('everyone', 'contacts', 'nobody'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_last_seen_visibility_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_last_seen_visibility_check
      check (last_seen_visibility in ('everyone', 'contacts', 'nobody'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_about_visibility_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_about_visibility_check
      check (about_visibility in ('everyone', 'contacts', 'nobody'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_account_privacy_check'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_account_privacy_check
      check (account_privacy in ('public', 'private'));
  end if;
end
$$;

create or replace function public.sync_profile_presence_columns()
returns trigger
language plpgsql
as $$
begin
  if new.last_seen is null and new.last_seen_at is not null then
    new.last_seen = new.last_seen_at;
  elsif new.last_seen is not null and new.last_seen_at is null then
    new.last_seen_at = new.last_seen;
  elsif new.last_seen is distinct from old.last_seen then
    new.last_seen_at = new.last_seen;
  elsif new.last_seen_at is distinct from old.last_seen_at then
    new.last_seen = new.last_seen_at;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_profiles_sync_presence on public.profiles;
create trigger trg_profiles_sync_presence
before update on public.profiles
for each row
execute function public.sync_profile_presence_columns();

alter table if exists public.chat_requests
  add column if not exists sender_id uuid,
  add column if not exists receiver_id uuid;

update public.chat_requests
set sender_id = coalesce(sender_id, requested_by),
    receiver_id = coalesce(receiver_id, user_id)
where sender_id is null
   or receiver_id is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'chat_requests_sender_id_fkey'
      and conrelid = 'public.chat_requests'::regclass
  ) then
    alter table public.chat_requests
      add constraint chat_requests_sender_id_fkey
      foreign key (sender_id) references public.profiles (id) on delete cascade;
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'chat_requests_receiver_id_fkey'
      and conrelid = 'public.chat_requests'::regclass
  ) then
    alter table public.chat_requests
      add constraint chat_requests_receiver_id_fkey
      foreign key (receiver_id) references public.profiles (id) on delete cascade;
  end if;
end
$$;

alter table if exists public.chat_requests
  alter column sender_id set not null,
  alter column receiver_id set not null,
  alter column status set default 'pending',
  alter column status set not null;

create index if not exists idx_chat_requests_sender_status
  on public.chat_requests (sender_id, status, created_at desc);

create index if not exists idx_chat_requests_receiver_status
  on public.chat_requests (receiver_id, status, created_at desc);

create or replace function public.sync_chat_request_parties()
returns trigger
language plpgsql
as $$
begin
  new.sender_id = coalesce(new.sender_id, new.requested_by);
  new.receiver_id = coalesce(new.receiver_id, new.user_id);
  return new;
end;
$$;

drop trigger if exists trg_chat_requests_sync_parties on public.chat_requests;
create trigger trg_chat_requests_sync_parties
before insert or update on public.chat_requests
for each row
execute function public.sync_chat_request_parties();

create table if not exists public.blocked_users (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint blocked_users_unique unique (blocker_id, blocked_user_id),
  constraint blocked_users_self_block_check check (blocker_id <> blocked_user_id)
);

create index if not exists idx_blocked_users_blocker
  on public.blocked_users (blocker_id, created_at desc);

create index if not exists idx_blocked_users_blocked
  on public.blocked_users (blocked_user_id, created_at desc);

create table if not exists public.user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  reported_user_id uuid not null references public.profiles (id) on delete cascade,
  reason text not null default 'profile_report',
  created_at timestamptz not null default now(),
  constraint user_reports_self_report_check check (reporter_id <> reported_user_id)
);

create index if not exists idx_user_reports_reporter
  on public.user_reports (reporter_id, created_at desc);

create index if not exists idx_user_reports_reported
  on public.user_reports (reported_user_id, created_at desc);

grant select, insert, delete on public.blocked_users to authenticated;
grant insert on public.user_reports to authenticated;

alter table if exists public.user_reports enable row level security;

drop policy if exists "user_reports_insert_own" on public.user_reports;
create policy "user_reports_insert_own"
on public.user_reports
for insert
to authenticated
with check (reporter_id = auth.uid());

insert into storage.buckets (id, name, public)
values ('profile-images', 'profile-images', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "profile_images_insert_own" on storage.objects;
create policy "profile_images_insert_own"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'profile-images'
  and ((storage.foldername(name))[1]) = auth.uid()::text
);

drop policy if exists "profile_images_update_own" on storage.objects;
create policy "profile_images_update_own"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'profile-images'
  and ((storage.foldername(name))[1]) = auth.uid()::text
)
with check (
  bucket_id = 'profile-images'
  and ((storage.foldername(name))[1]) = auth.uid()::text
);

drop policy if exists "profile_images_delete_own" on storage.objects;
create policy "profile_images_delete_own"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'profile-images'
  and ((storage.foldername(name))[1]) = auth.uid()::text
);
