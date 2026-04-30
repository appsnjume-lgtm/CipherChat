-- CipherChat canonical schema validation.
--
-- Run this after applying supabase/cipherchat_schema.sql to a brand-new
-- Supabase database. The script is intentionally read-only and fails fast when
-- a required object or hardening rule is missing.

-- ============================================================================
-- Core Schema Surface
-- ============================================================================

do $$
begin
  perform 1
  from information_schema.tables
  where table_schema = 'public'
    and table_name = 'direct_chat_pairs';

  if not found then
    raise exception 'Validation failed: public.direct_chat_pairs is missing.';
  end if;

  perform 1
  from information_schema.tables
  where table_schema = 'public'
    and table_name = 'stickers';

  if not found then
    raise exception 'Validation failed: public.stickers is missing.';
  end if;

  perform 1
  from information_schema.tables
  where table_schema = 'public'
    and table_name = 'user_stickers';

  if not found then
    raise exception 'Validation failed: public.user_stickers is missing.';
  end if;

  perform 1
  from information_schema.tables
  where table_schema = 'public'
    and table_name = 'url_previews';

  if found then
    raise exception 'Validation failed: public.url_previews should not exist.';
  end if;

  perform 1
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_visible_profiles_by_ids';

  if not found then
    raise exception 'Validation failed: public.get_visible_profiles_by_ids(uuid[]) is missing.';
  end if;

  perform 1
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'search_visible_profiles';

  if not found then
    raise exception 'Validation failed: public.search_visible_profiles(text, integer) is missing.';
  end if;

  perform 1
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'ensure_direct_chat';

  if not found then
    raise exception 'Validation failed: public.ensure_direct_chat(uuid, uuid) is missing.';
  end if;

  perform 1
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'get_chat_participant_keys';

  if not found then
    raise exception 'Validation failed: public.get_chat_participant_keys(uuid) is missing.';
  end if;

  perform 1
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'can_access_sticker';

  if not found then
    raise exception 'Validation failed: public.can_access_sticker(uuid, uuid) is missing.';
  end if;

  perform 1
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'can_save_sticker';

  if not found then
    raise exception 'Validation failed: public.can_save_sticker(uuid, uuid) is missing.';
  end if;

  perform 1
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'can_manage_sticker_storage_object';

  if not found then
    raise exception 'Validation failed: public.can_manage_sticker_storage_object(text, uuid) is missing.';
  end if;

  perform 1
  from pg_publication_tables
  where pubname = 'supabase_realtime'
    and schemaname = 'public'
    and tablename = 'messages';

  if not found then
    raise exception 'Validation failed: public.messages is missing from supabase_realtime.';
  end if;

  perform 1
  from pg_publication_tables
  where pubname = 'supabase_realtime'
    and schemaname = 'public'
    and tablename = 'message_receipts';

  if not found then
    raise exception 'Validation failed: public.message_receipts is missing from supabase_realtime.';
  end if;
  raise notice 'Core schema surface checks passed.';
end;
$$;

-- ============================================================================
-- Privacy And Search Hardening
-- ============================================================================

do $$
begin
  perform 1
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'messages'
    and column_name = 'search_text';

  if found then
    raise exception 'Validation failed: public.messages.search_text should not exist.';
  end if;

  perform 1
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'messages'
    and column_name = 'sticker_id';

  if not found then
    raise exception 'Validation failed: public.messages.sticker_id is missing.';
  end if;

  perform 1
  from information_schema.columns
  where table_schema = 'public'
    and table_name = 'stickers'
    and column_name = 'mime_type';

  if not found then
    raise exception 'Validation failed: public.stickers.mime_type is missing.';
  end if;

  perform 1
  from pg_constraint
  where conrelid = 'public.stickers'::regclass
    and conname = 'stickers_mime_type_check'
    and pg_get_constraintdef(oid) like '%image/webp%';

  if not found then
    raise exception 'Validation failed: stickers_mime_type_check is missing or does not allow image/webp.';
  end if;

  perform 1
  from pg_constraint
  where conrelid = 'public.stickers'::regclass
    and conname = 'stickers_storage_path_extension_check'
    and lower(pg_get_constraintdef(oid)) like '%png%'
    and lower(pg_get_constraintdef(oid)) like '%jpe%'
    and lower(pg_get_constraintdef(oid)) like '%webp%';

  if not found then
    raise exception 'Validation failed: stickers_storage_path_extension_check is missing or does not restrict stickers to image file extensions.';
  end if;

  perform 1
  from pg_constraint
  where conrelid = 'public.stickers'::regclass
    and conname = 'stickers_storage_path_matches_mime_type_check'
    and pg_get_constraintdef(oid) like '%image/webp%';

  if not found then
    raise exception 'Validation failed: stickers_storage_path_matches_mime_type_check is missing or does not keep file extensions aligned with sticker mime types.';
  end if;

  perform 1
  from pg_constraint
  where conrelid = 'public.messages'::regclass
    and conname = 'messages_type_check'
    and pg_get_constraintdef(oid) like '%sticker%';

  if not found then
    raise exception 'Validation failed: messages_type_check does not allow sticker.';
  end if;

  perform 1
  from pg_constraint
  where conrelid = 'public.messages'::regclass
    and conname = 'messages_sticker_reference_check';

  if not found then
    raise exception 'Validation failed: messages_sticker_reference_check is missing.';
  end if;

  perform 1
  from pg_class cls
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'public'
    and cls.relname = 'stickers'
    and cls.relrowsecurity = true;

  if not found then
    raise exception 'Validation failed: public.stickers does not have RLS enabled.';
  end if;

  perform 1
  from pg_class cls
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'public'
    and cls.relname = 'user_stickers'
    and cls.relrowsecurity = true;

  if not found then
    raise exception 'Validation failed: public.user_stickers does not have RLS enabled.';
  end if;

  perform 1
  from pg_policy pol
  join pg_class cls on cls.oid = pol.polrelid
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'public'
    and cls.relname = 'stickers'
    and pol.polname = 'stickers_select_public_or_owner'
    and coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') like '%true%';

  if not found then
    raise exception 'Validation failed: stickers_select_public_or_owner must allow all stickers to be visible.';
  end if;

  perform 1
  from pg_policy pol
  join pg_class cls on cls.oid = pol.polrelid
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'public'
    and cls.relname = 'messages'
    and pol.polname = 'messages_insert_members_only'
    and coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '') like '%can_access_sticker%';

  if not found then
    raise exception 'Validation failed: messages_insert_members_only is not sticker-aware.';
  end if;

  perform 1
  from pg_policy pol
  join pg_class cls on cls.oid = pol.polrelid
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'public'
    and cls.relname = 'user_stickers'
    and pol.polname = 'user_stickers_insert_owner_only'
    and coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '') like '%can_save_sticker%';

  if not found then
    raise exception 'Validation failed: user_stickers_insert_owner_only must be gated by can_save_sticker.';
  end if;

  perform 1
  from pg_policy pol
  join pg_class cls on cls.oid = pol.polrelid
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'public'
    and cls.relname = 'user_stickers'
    and pol.polname = 'user_stickers_update_owner_only'
    and coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '') like '%can_save_sticker%';

  if not found then
    raise exception 'Validation failed: user_stickers_update_owner_only must be gated by can_save_sticker.';
  end if;

  perform 1
  from pg_policy pol
  join pg_class cls on cls.oid = pol.polrelid
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'public'
    and cls.relname = 'profiles'
    and pol.polname = 'profiles_select_authenticated'
    and coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') like '%auth.uid()%id%';

  if not found then
    raise exception 'Validation failed: profiles_select_authenticated is not self-scoped.';
  end if;

  perform 1
  from pg_class cls
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'public'
    and cls.relname = 'direct_chat_pairs'
    and cls.relrowsecurity = true;

  if not found then
    raise exception 'Validation failed: public.direct_chat_pairs does not have RLS enabled.';
  end if;

  perform 1
  from information_schema.role_table_grants
  where table_schema = 'public'
    and table_name = 'direct_chat_pairs'
    and grantee = 'authenticated'
    and privilege_type = 'SELECT';

  if found then
    raise exception 'Validation failed: authenticated should not have direct SELECT on public.direct_chat_pairs.';
  end if;

  raise notice 'Privacy and search hardening checks passed.';
end;
$$;

-- ============================================================================
-- Storage Hardening
-- ============================================================================

do $$
begin
  perform 1
  from storage.buckets
  where id = 'secure-media'
    and public = false;

  if not found then
    raise exception 'Validation failed: secure-media bucket is missing or public.';
  end if;

  perform 1
  from storage.buckets
  where id = 'stickers'
    and public = true;

  if not found then
    raise exception 'Validation failed: stickers bucket is missing or not public.';
  end if;

  perform 1
  from pg_policy pol
  join pg_class cls on cls.oid = pol.polrelid
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'storage'
    and cls.relname = 'objects'
    and pol.polname = 'secure_media_select_authenticated'
    and coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') like '%can_access_secure_media_object%';

  if not found then
    raise exception 'Validation failed: secure_media_select_authenticated is not membership-scoped.';
  end if;

  perform 1
  from pg_policy pol
  join pg_class cls on cls.oid = pol.polrelid
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'storage'
    and cls.relname = 'objects'
    and pol.polname = 'secure_media_delete_authenticated'
    and coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') like '%can_delete_secure_media_object%';

  if not found then
    raise exception 'Validation failed: secure_media_delete_authenticated is not sender-scoped.';
  end if;

  perform 1
  from pg_policy pol
  join pg_class cls on cls.oid = pol.polrelid
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'storage'
    and cls.relname = 'objects'
    and pol.polname = 'stickers_insert_authenticated'
    and coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '') like '%can_manage_sticker_storage_object%';

  if not found then
    raise exception 'Validation failed: stickers_insert_authenticated is not owner-scoped.';
  end if;

  perform 1
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'can_manage_sticker_storage_object'
    and pg_get_functiondef(p.oid) like '%png|jpe?g|webp%';

  if not found then
    raise exception 'Validation failed: can_manage_sticker_storage_object must reject non-image sticker object paths.';
  end if;

  perform 1
  from pg_policy pol
  join pg_class cls on cls.oid = pol.polrelid
  join pg_namespace ns on ns.oid = cls.relnamespace
  where ns.nspname = 'storage'
    and cls.relname = 'objects'
    and pol.polname = 'stickers_select_public'
    and coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') like '%stickers%';

  if not found then
    raise exception 'Validation failed: stickers_select_public is missing.';
  end if;

  raise notice 'Storage hardening checks passed.';
end;
$$;

-- ============================================================================
-- Success
-- ============================================================================

do $$
begin
  raise notice 'cipherchat_schema.sql validation passed.';
end;
$$;




