-- Chat interne et assistance aux visiteurs
-- À exécuter dans le SQL Editor du projet Supabase École Privée Les Étoiles.

create table if not exists public.chat_conversations (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null,
  guest_name text not null check (char_length(trim(guest_name)) between 1 and 120),
  subject text not null default 'Question générale' check (char_length(trim(subject)) between 1 and 180),
  status text not null default 'open' check (status in ('open','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid references public.chat_conversations(id) on delete cascade,
  channel_type text not null check (channel_type in ('internal','visitor')),
  sender_id uuid not null,
  sender_name text not null check (char_length(trim(sender_name)) between 1 and 120),
  sender_role text not null default 'Visiteur' check (char_length(trim(sender_role)) between 1 and 60),
  message_text text not null check (char_length(trim(message_text)) between 1 and 4000),
  created_at timestamptz not null default now(),
  constraint chat_message_channel_conversation check (
    (channel_type = 'internal' and conversation_id is null)
    or (channel_type = 'visitor' and conversation_id is not null)
  )
);

create index if not exists chat_messages_internal_created_idx
  on public.chat_messages (created_at desc) where channel_type = 'internal';
create index if not exists chat_messages_conversation_created_idx
  on public.chat_messages (conversation_id, created_at);
create index if not exists chat_conversations_status_updated_idx
  on public.chat_conversations (status, updated_at desc);

create or replace function public.chat_is_staff()
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.user_id = (select auth.uid())
      and p.role in ('admin','personnel','titulaire','professeur')
  );
$$;

alter table public.chat_conversations enable row level security;
alter table public.chat_messages enable row level security;

revoke all on public.chat_conversations from anon, authenticated;
revoke all on public.chat_messages from anon, authenticated;
grant select, insert, update on public.chat_conversations to authenticated;
grant select, insert on public.chat_messages to authenticated;

drop policy if exists "chat conversations select participants" on public.chat_conversations;
create policy "chat conversations select participants"
on public.chat_conversations for select to authenticated
using (
  public.chat_is_staff()
  or (
    created_by = (select auth.uid())
    and (select auth.jwt()->>'is_anonymous') = 'true'
  )
);

drop policy if exists "chat visitors create own conversation" on public.chat_conversations;
create policy "chat visitors create own conversation"
on public.chat_conversations for insert to authenticated
with check (
  created_by = (select auth.uid())
  and (select auth.jwt()->>'is_anonymous') = 'true'
);

drop policy if exists "chat participants update conversation" on public.chat_conversations;
create policy "chat participants update conversation"
on public.chat_conversations for update to authenticated
using (
  public.chat_is_staff()
  or (
    created_by = (select auth.uid())
    and (select auth.jwt()->>'is_anonymous') = 'true'
  )
)
with check (
  public.chat_is_staff()
  or (
    created_by = (select auth.uid())
    and (select auth.jwt()->>'is_anonymous') = 'true'
  )
);

drop policy if exists "chat messages select channel access" on public.chat_messages;
create policy "chat messages select channel access"
on public.chat_messages for select to authenticated
using (
  (channel_type = 'internal' and public.chat_is_staff())
  or (
    channel_type = 'visitor'
    and exists (
      select 1
      from public.chat_conversations c
      where c.id = chat_messages.conversation_id
        and (
          public.chat_is_staff()
          or (
            c.created_by = (select auth.uid())
            and (select auth.jwt()->>'is_anonymous') = 'true'
          )
        )
    )
  )
);

drop policy if exists "chat messages insert own identity" on public.chat_messages;
create policy "chat messages insert own identity"
on public.chat_messages for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and (
    (channel_type = 'internal' and conversation_id is null and public.chat_is_staff())
    or (
      channel_type = 'visitor'
      and exists (
        select 1
        from public.chat_conversations c
        where c.id = chat_messages.conversation_id
          and (
            public.chat_is_staff()
            or (
              c.created_by = (select auth.uid())
              and (select auth.jwt()->>'is_anonymous') = 'true'
            )
          )
      )
    )
  )
);

-- Active la diffusion Realtime des nouveaux messages si la publication existe.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'chat_messages'
     ) then
    execute 'alter publication supabase_realtime add table public.chat_messages';
  end if;
end $$;
