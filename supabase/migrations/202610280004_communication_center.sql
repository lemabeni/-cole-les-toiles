-- Centre de communication : annonces, messages privés, notifications, présence et pièces jointes.
-- À exécuter après 202610280003_chat_discussions.sql.

alter table public.chat_messages
  add column if not exists attachment_path text,
  add column if not exists attachment_name text,
  add column if not exists attachment_mime text;

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(trim(title)) between 1 and 180),
  body text not null check (char_length(trim(body)) between 1 and 6000),
  audience_type text not null default 'all'
    check (audience_type in ('all','staff','role')),
  audience_value text,
  pinned boolean not null default false,
  published boolean not null default true,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (audience_type in ('all','staff') and audience_value is null)
    or (audience_type = 'role' and audience_value in ('admin','personnel','titulaire','professeur'))
  )
);
create index if not exists announcements_published_created_idx
  on public.announcements (published, pinned desc, created_at desc);

create table if not exists public.announcement_reads (
  announcement_id uuid not null references public.announcements(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (announcement_id,user_id)
);

create table if not exists public.private_conversations (
  id uuid primary key default gen_random_uuid(),
  participant_one uuid not null references auth.users(id) on delete cascade,
  participant_two uuid not null references auth.users(id) on delete cascade,
  created_by uuid not null references auth.users(id) on delete cascade,
  title text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint private_conversation_distinct_people check (participant_one <> participant_two)
);
create unique index if not exists private_conversation_pair_unique
  on public.private_conversations (
    least(participant_one::text, participant_two::text),
    greatest(participant_one::text, participant_two::text)
  );

create table if not exists public.private_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.private_conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  message_text text not null check (char_length(trim(message_text)) between 1 and 4000),
  attachment_path text,
  attachment_name text,
  attachment_mime text,
  created_at timestamptz not null default now()
);
create index if not exists private_messages_conversation_created_idx
  on public.private_messages (conversation_id,created_at);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  notification_type text not null check (notification_type in ('message','announcement','system')),
  title text not null check (char_length(trim(title)) between 1 and 180),
  body text not null default '' check (char_length(body) <= 500),
  link_type text,
  link_id uuid,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user_unread_idx
  on public.notifications (user_id,created_at desc) where read_at is null;

create table if not exists public.user_presence (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_seen_at timestamptz not null default now(),
  presence_state text not null default 'online' check (presence_state in ('online','away','offline'))
);

alter table public.announcements enable row level security;
alter table public.announcement_reads enable row level security;
alter table public.private_conversations enable row level security;
alter table public.private_messages enable row level security;
alter table public.notifications enable row level security;
alter table public.user_presence enable row level security;

revoke all on public.announcements, public.announcement_reads, public.private_conversations,
  public.private_messages, public.notifications, public.user_presence from anon, authenticated;
grant select, insert, update, delete on public.announcements to authenticated;
grant select, insert, update on public.announcement_reads to authenticated;
grant select, insert on public.private_conversations to authenticated;
grant select, insert on public.private_messages to authenticated;
grant select, insert, update on public.notifications to authenticated;
grant select, insert, update on public.user_presence to authenticated;

-- Announcements: any connected school account can read the announcements addressed to it.
drop policy if exists "announcements read for audience" on public.announcements;
create policy "announcements read for audience" on public.announcements
for select to authenticated using (
  public.chat_is_staff() and published and (
    audience_type = 'all'
    or audience_type = 'staff'
    or (audience_type = 'role' and audience_value = (
      select p.role from public.profiles p where p.user_id = (select auth.uid())
    ))
  )
  or (
    public.chat_is_staff()
    and exists(select 1 from public.profiles p where p.user_id=(select auth.uid()) and p.role='admin')
  )
);
drop policy if exists "announcements admin insert" on public.announcements;
create policy "announcements admin insert" on public.announcements
for insert to authenticated with check (
  created_by = (select auth.uid())
  and exists(select 1 from public.profiles p where p.user_id=(select auth.uid()) and p.role='admin')
);
drop policy if exists "announcements admin update" on public.announcements;
create policy "announcements admin update" on public.announcements
for update to authenticated using (
  exists(select 1 from public.profiles p where p.user_id=(select auth.uid()) and p.role='admin')
) with check (
  exists(select 1 from public.profiles p where p.user_id=(select auth.uid()) and p.role='admin')
);
drop policy if exists "announcements admin delete" on public.announcements;
create policy "announcements admin delete" on public.announcements
for delete to authenticated using (
  exists(select 1 from public.profiles p where p.user_id=(select auth.uid()) and p.role='admin')
);

drop policy if exists "announcement reads own select" on public.announcement_reads;
create policy "announcement reads own select" on public.announcement_reads
for select to authenticated using (user_id=(select auth.uid()));
drop policy if exists "announcement reads own insert" on public.announcement_reads;
create policy "announcement reads own insert" on public.announcement_reads
for insert to authenticated with check (
  user_id=(select auth.uid())
  and exists(select 1 from public.announcements a where a.id=announcement_id and a.published)
);
drop policy if exists "announcement reads own update" on public.announcement_reads;
create policy "announcement reads own update" on public.announcement_reads
for update to authenticated using (user_id=(select auth.uid()))
with check (user_id=(select auth.uid()));

drop policy if exists "private conversations participant select" on public.private_conversations;
create policy "private conversations participant select" on public.private_conversations
for select to authenticated using (
  public.chat_is_staff()
  and ((select auth.uid())=participant_one or (select auth.uid())=participant_two)
);
drop policy if exists "private conversations create by participant" on public.private_conversations;
create policy "private conversations create by participant" on public.private_conversations
for insert to authenticated with check (
  public.chat_is_staff()
  and created_by=(select auth.uid())
  and ((select auth.uid())=participant_one or (select auth.uid())=participant_two)
  and exists(select 1 from public.profiles p where p.user_id=participant_one)
  and exists(select 1 from public.profiles p where p.user_id=participant_two)
);
drop policy if exists "private conversations participant update" on public.private_conversations;
create policy "private conversations participant update" on public.private_conversations
for update to authenticated using (
  public.chat_is_staff()
  and ((select auth.uid())=participant_one or (select auth.uid())=participant_two)
) with check (
  public.chat_is_staff()
  and ((select auth.uid())=participant_one or (select auth.uid())=participant_two)
  and participant_one is not null and participant_two is not null
);

drop policy if exists "private messages participants select" on public.private_messages;
create policy "private messages participants select" on public.private_messages
for select to authenticated using (
  exists(select 1 from public.private_conversations c
    where c.id=conversation_id and public.chat_is_staff()
      and ((select auth.uid())=c.participant_one or (select auth.uid())=c.participant_two))
);
drop policy if exists "private messages participant insert" on public.private_messages;
create policy "private messages participant insert" on public.private_messages
for insert to authenticated with check (
  sender_id=(select auth.uid())
  and exists(select 1 from public.private_conversations c
    where c.id=conversation_id and public.chat_is_staff()
      and ((select auth.uid())=c.participant_one or (select auth.uid())=c.participant_two))
);

drop policy if exists "notifications own select" on public.notifications;
create policy "notifications own select" on public.notifications
for select to authenticated using (user_id=(select auth.uid()));
drop policy if exists "notifications staff create" on public.notifications;
create policy "notifications staff create" on public.notifications
for insert to authenticated with check (
  public.chat_is_staff()
  and (
    user_id=(select auth.uid())
    or exists(select 1 from public.profiles p where p.user_id=(select auth.uid()) and p.role='admin')
    or (
      notification_type='message'
      and link_type='private_conversation'
      and exists(select 1 from public.private_conversations c
        where c.id=link_id
          and ((select auth.uid())=c.participant_one or (select auth.uid())=c.participant_two)
          and user_id in (c.participant_one,c.participant_two)
          and user_id <> (select auth.uid()))
    )
  )
);
drop policy if exists "notifications own update" on public.notifications;
create policy "notifications own update" on public.notifications
for update to authenticated using (user_id=(select auth.uid()))
with check (user_id=(select auth.uid()));

drop policy if exists "presence staff read" on public.user_presence;
create policy "presence staff read" on public.user_presence
for select to authenticated using (public.chat_is_staff());
drop policy if exists "presence own insert" on public.user_presence;
create policy "presence own insert" on public.user_presence
for insert to authenticated with check (user_id=(select auth.uid()) and public.chat_is_staff());
drop policy if exists "presence own update" on public.user_presence;
create policy "presence own update" on public.user_presence
for update to authenticated using (user_id=(select auth.uid()) and public.chat_is_staff())
with check (user_id=(select auth.uid()) and public.chat_is_staff());

-- Private Storage bucket for chat attachments.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('chat-attachments','chat-attachments',false,10485760,
  array['image/jpeg','image/png','image/webp','application/pdf','text/plain'])
on conflict (id) do update set public=false,file_size_limit=10485760,
  allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "chat attachments staff upload" on storage.objects;
create policy "chat attachments staff upload" on storage.objects
for insert to authenticated with check (
  bucket_id='chat-attachments'
  and public.chat_is_staff()
  and (
    (split_part(name,'/',1)='internal' and split_part(name,'/',2)=(select auth.uid())::text)
    or (
      split_part(name,'/',1)='visitor'
      and split_part(name,'/',3)=(select auth.uid())::text
      and (select auth.jwt()->>'is_anonymous')='true'
      and exists(select 1 from public.chat_conversations c
        where c.id::text=split_part(name,'/',2) and c.created_by=(select auth.uid()))
    )
    or (
      split_part(name,'/',1)='private'
      and split_part(name,'/',3)=(select auth.uid())::text
      and exists(select 1 from public.private_conversations c
        where c.id::text=split_part(name,'/',2)
          and ((select auth.uid())=c.participant_one or (select auth.uid())=c.participant_two))
    )
  )
);
drop policy if exists "chat attachments authorized read" on storage.objects;
create policy "chat attachments authorized read" on storage.objects
for select to authenticated using (
  bucket_id='chat-attachments'
  and public.chat_is_staff()
  and (
    split_part(name,'/',1)='internal'
    or (
      split_part(name,'/',1)='visitor'
      and (select auth.jwt()->>'is_anonymous')='true'
      and exists(select 1 from public.chat_conversations c
        where c.id::text=split_part(name,'/',2) and c.created_by=(select auth.uid()))
    )
    or (
      split_part(name,'/',1)='private'
      and exists(select 1 from public.private_conversations c
        where c.id::text=split_part(name,'/',2)
          and ((select auth.uid())=c.participant_one or (select auth.uid())=c.participant_two))
    )
  )
);

-- Enable Realtime on the tables whose updates are displayed live.
do $$
declare t text;
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    foreach t in array array['announcements','private_messages','notifications','user_presence'] loop
      if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=t) then
        execute format('alter publication supabase_realtime add table public.%I',t);
      end if;
    end loop;
  end if;
end $$;
