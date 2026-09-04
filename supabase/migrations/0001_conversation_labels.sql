-- One manual flag per WhatsApp number (Spam / Lead / Potential / Collab).
-- "Unread" and "All" aren't stored here -- they're computed client-side from
-- host_conversations (Unread = has a row with response IS NULL).
create table public.conversation_labels (
  sender text primary key,
  label text not null check (label in ('Spam', 'Lead', 'Potential', 'Collab')),
  updated_at timestamptz not null default now()
);

alter table public.conversation_labels enable row level security;

create policy "authenticated read" on public.conversation_labels
  for select using (auth.role() = 'authenticated');

create policy "authenticated insert" on public.conversation_labels
  for insert with check (auth.role() = 'authenticated');

create policy "authenticated update" on public.conversation_labels
  for update using (auth.role() = 'authenticated');

create policy "authenticated delete" on public.conversation_labels
  for delete using (auth.role() = 'authenticated');
