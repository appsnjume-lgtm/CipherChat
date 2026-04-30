-- Remove the unused url_previews table and harden direct_chat_pairs.
--
-- direct_chat_pairs is an internal support table for security definer
-- functions and should not be readable directly by authenticated clients.

drop table if exists public.url_previews;

alter table if exists public.direct_chat_pairs enable row level security;

revoke select on public.direct_chat_pairs from authenticated;