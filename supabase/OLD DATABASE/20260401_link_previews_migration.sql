-- This migration is a placeholder/documentation.
-- In our E2EE architecture, URL previews are stored inside the encrypted 'payload_encrypted' JSONB column.
-- Therefore, no schema changes are strictly required for the 'messages' table.

-- However, if we wanted to allow users to search for links or cache unencrypted previews (optional/less private),
-- we could create a cache table. But for maximum privacy, we keep it in the encrypted payload.

-- One thing we CAN add is an index on message_type to speed up filtering if we ever want to find all 'text' messages with potential links.
create index if not exists idx_messages_type on public.messages (message_type);

-- If you decide to add a server-side cache for previews (NOT E2EE friendly, but faster):
create table if not exists public.url_previews (
  url_hash text primary key, -- sha256 of normalized url
  title text,
  description text,
  image_url text,
  created_at timestamptz default now()
);

