-- Run this once in Supabase SQL Editor before the attribute-mapping feature works.
-- Generic, growing attribute store for shipment fields that don't have a fixed
-- column (Product, Country, etc.) — no schema change needed for each new one.

create table if not exists shipment_attributes (
  id bigint generated always as identity primary key,
  shipment_id text references shipments(shipment_id) on delete cascade,
  attribute_name text not null,
  value text,
  updated_at timestamptz default now(),
  unique(shipment_id, attribute_name)
);
alter table shipment_attributes enable row level security;
create policy "authenticated full access" on shipment_attributes
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create index if not exists idx_shipattr_shipment on shipment_attributes(shipment_id);
create index if not exists idx_shipattr_name on shipment_attributes(attribute_name);
