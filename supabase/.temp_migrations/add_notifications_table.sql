-- ─────────────────────────────────────────────────────────────────
-- Persistent in-app notifications
-- Each row represents one notification entry per user.
-- The Flutter NotificationProvider writes here on every _add() call
-- and reads here on login to restore history after app restart.
-- ─────────────────────────────────────────────────────────────────

create table if not exists public.notifications (
  id          uuid        primary key default gen_random_uuid(),
  user_id     uuid        not null references auth.users(id) on delete cascade,
  notif_key   text        not null,          -- Flutter dedup key e.g. '{orderId}_placed'
  title       text        not null,
  body        text        not null,
  order_id    uuid        references public.orders(id) on delete set null,
  is_read     boolean     not null default false,
  created_at  timestamptz not null default now()
);

-- Prevent duplicate notifications per user
create unique index if not exists notifications_user_key_idx
  on public.notifications (user_id, notif_key);

-- Fast per-user queries ordered by time
create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

-- ── Row Level Security ────────────────────────────────────────────
alter table public.notifications enable row level security;

-- Users can only read their own notifications
create policy "notifications_select_own"
  on public.notifications for select
  using (user_id = auth.uid());

-- Users insert their own (Realtime callbacks run in user auth context)
create policy "notifications_insert_own"
  on public.notifications for insert
  with check (user_id = auth.uid());

-- Users can mark their own as read
create policy "notifications_update_own"
  on public.notifications for update
  using (user_id = auth.uid());

-- Users can clear their own
create policy "notifications_delete_own"
  on public.notifications for delete
  using (user_id = auth.uid());
