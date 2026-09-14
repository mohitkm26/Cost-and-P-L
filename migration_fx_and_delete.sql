-- Run this once in Supabase SQL Editor before the new app version goes live.

alter table invoice_tags add column if not exists original_currency text;
alter table invoice_tags add column if not exists original_amount numeric;
alter table invoice_tags add column if not exists fx_rate_used numeric;

create table if not exists fx_rates (
  currency text primary key,
  rate_to_inr numeric not null,
  updated_by uuid,
  updated_at timestamptz default now()
);
alter table fx_rates enable row level security;
create policy "authenticated full access" on fx_rates
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
insert into fx_rates (currency, rate_to_inr) values ('INR', 1) on conflict (currency) do nothing;

-- Soft-delete support for pending invoices (releases locks, keeps an audit trace instead of hard deleting)
-- No column needed — status text already accepts 'CANCELLED' as a new value.
