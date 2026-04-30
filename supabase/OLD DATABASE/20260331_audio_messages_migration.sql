-- Adds first-class audio and voice-note message support to the existing encrypted message schema.
-- Voice-note metadata such as duration stays inside payload_encrypted, so no extra columns are required.

alter table if exists public.messages
  drop constraint if exists messages_type_check;

alter table if exists public.messages
  add constraint messages_type_check
  check (message_type in ('text', 'image', 'video', 'file', 'audio'));