-- Adds persisted reply support for chat messages.
-- Run this on existing CipherChat databases.

alter table public.messages
  add column if not exists reply_to_message_id uuid references public.messages (id) on delete set null;

create index if not exists idx_messages_reply_to_message
  on public.messages (reply_to_message_id);

create or replace function public.validate_message_reply_target()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.reply_to_message_id is null then
    return new;
  end if;

  if not exists (
    select 1
    from public.messages m
    where m.id = new.reply_to_message_id
      and m.chat_id = new.chat_id
  ) then
    raise exception 'Reply target must belong to the same chat.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_messages_validate_reply_target on public.messages;
create trigger trg_messages_validate_reply_target
before insert or update on public.messages
for each row
execute function public.validate_message_reply_target();
