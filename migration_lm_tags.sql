-- Run this once in Supabase SQL Editor before the new LM invoice mechanism works.
-- This replaces the old direct box_lm_costs.actual_amount write with a proper
-- tag-based system, mirroring invoice_tags/shipment_costs but for boxes — so LM
-- invoices actually reverse provision the same way Other-Header invoices do.

create table if not exists lm_invoice_tags (
  id bigint generated always as identity primary key,
  invoice_id bigint references invoices(id) on delete cascade,
  shipment_id text not null,
  box_ids text[] not null,        -- one box for a normal box-level charge, many for an LTL lump split across boxes
  charge_code text not null,      -- free text for now
  entered_amount numeric,         -- converted to INR, this is what gets compared/reversed
  original_currency text,
  original_amount numeric,
  fx_rate_used numeric,
  status text default 'LOCKED',   -- LOCKED | REVERSED | DISPUTED | RELEASED
  source text default 'manual',   -- 'manual' | 'file'
  tagged_by uuid,
  tagged_at timestamptz default now()
);
alter table lm_invoice_tags enable row level security;
create policy "authenticated full access" on lm_invoice_tags
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
