-- Rapports de test : espace séparé des données scolaires.
-- Les testeurs peuvent uniquement créer un rapport depuis une session anonyme.
create table if not exists public.tester_feedback (
  id uuid primary key default gen_random_uuid(),
  tester_name text check (tester_name is null or char_length(trim(tester_name)) <= 100),
  report_type text not null check (report_type in ('bug','security','constraint','suggestion')),
  module_name text not null check (char_length(trim(module_name)) between 1 and 80),
  severity text not null default 'medium' check (severity in ('low','medium','high')),
  details text not null check (char_length(trim(details)) between 10 and 3000),
  status text not null default 'new' check (status in ('new','reviewing','resolved','dismissed')),
  created_at timestamptz not null default now()
);

alter table public.tester_feedback enable row level security;
revoke all on public.tester_feedback from anon, authenticated;
grant insert, select on public.tester_feedback to authenticated;

drop policy if exists "anonymous testers submit feedback" on public.tester_feedback;
create policy "anonymous testers submit feedback"
on public.tester_feedback for insert to authenticated
with check (
  (select auth.jwt()->>'is_anonymous') = 'true'
  and status = 'new'
);

drop policy if exists "school staff read tester feedback" on public.tester_feedback;
create policy "school staff read tester feedback"
on public.tester_feedback for select to authenticated
using (public.chat_is_staff());

-- No public read/update/delete policy: test reports are private to authorized school staff.
