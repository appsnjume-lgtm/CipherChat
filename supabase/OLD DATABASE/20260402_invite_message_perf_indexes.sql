create index if not exists idx_chat_requests_requested_by_status
  on public.chat_requests (requested_by, status, created_at desc);

create index if not exists idx_message_receipts_user_unread_chat
  on public.message_receipts (user_id, chat_id)
  where read_at is null;
