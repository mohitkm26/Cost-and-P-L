-- Run this once. Adds the infrastructure for month-end close: a real event ledger
-- (the app currently has no memory of WHEN a provision was booked or reversed, only
-- current state — this fixes that), an entry_date on invoices (separate from the
-- invoice's own date, per the accounting rule agreed), and a period lock.

alter table invoices add column if not exists entry_date date;

create table if not exists provision_ledger (
  id bigint generated always as identity primary key,
  shipment_id text references shipments(shipment_id) on delete cascade,
  cost_header text,
  event_type text not null,        -- BOOKED | REVERSED
  amount numeric not null,
  event_date date not null,        -- BOOKED: pickup_date. REVERSED: the invoice's entry_date.
  related_invoice_id bigint references invoices(id),
  created_at timestamptz default now()
);
create index if not exists idx_ledger_shipment_header on provision_ledger(shipment_id, cost_header);
create index if not exists idx_ledger_event_date on provision_ledger(event_date);
create index if not exists idx_ledger_event_type on provision_ledger(event_type);
alter table provision_ledger enable row level security;
drop policy if exists "authenticated full access" on provision_ledger;
create policy "authenticated full access" on provision_ledger
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- Single-row table — one current lock date for the whole system, not per-header/per-LOB.
create table if not exists period_lock (
  id int primary key default 1,
  locked_through date,
  locked_by uuid,
  locked_at timestamptz default now(),
  constraint period_lock_single_row check (id = 1)
);
insert into period_lock (id, locked_through) values (1, null) on conflict (id) do nothing;
alter table period_lock enable row level security;
drop policy if exists "authenticated full access" on period_lock;
create policy "authenticated full access" on period_lock
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

create table if not exists period_lock_log (
  id bigint generated always as identity primary key,
  action text not null,   -- LOCKED | UNLOCKED
  locked_through date,
  reason text,
  performed_by uuid,
  performed_at timestamptz default now()
);
alter table period_lock_log enable row level security;
drop policy if exists "authenticated full access" on period_lock_log;
create policy "authenticated full access" on period_lock_log
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
