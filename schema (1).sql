-- Cost Subledger — Phase 1 pilot schema
-- Run this once in Supabase: Dashboard -> SQL Editor -> New query -> paste -> Run

create table if not exists shipments (
  shipment_id text primary key,
  lob text,
  node text,
  pickup_date text,   -- kept as text: source exports mix Excel date serials and strings
  gross_weight numeric,
  revenue numeric,
  updated_at timestamptz default now()
);

create table if not exists shipment_costs (
  shipment_id text references shipments(shipment_id) on delete cascade,
  header text not null,          -- PICKUP, FM, HUB, OC, MM, OCEAN, TRANSSHIP, DC, DESTCLEAR, IOR, DROPOFF, LM
  amount numeric not null,
  source_file text,
  uploaded_at timestamptz default now(),
  primary key (shipment_id, header)
);

create table if not exists box_lm_costs (
  id bigint generated always as identity primary key,
  shipment_id text not null,
  box_id text not null,
  charge_code text not null,
  amount numeric not null,
  source text default 'file',    -- 'file' or 'db' (for when engineering wires in the real connection)
  uploaded_at timestamptz default now()
);

create table if not exists invoice_groups (
  id text primary key,
  name text not null,
  cost_header text not null,
  vendor text,
  created_at timestamptz default now()
);

create table if not exists invoice_lines (
  id bigint generated always as identity primary key,
  invoice_group_id text references invoice_groups(id) on delete cascade,
  shipment_id text not null,
  box_id text,
  charge_code_raw text,
  charge_code text,
  amount numeric not null,
  cost_header text not null,
  file_name text,
  uploaded_at timestamptz default now()
);

create table if not exists charge_code_dictionary (
  keyword text primary key,
  charge_code text not null
);

-- Row-level security: only logged-in users (your team, added manually in
-- Supabase Dashboard -> Authentication -> Users) can read or write anything.
alter table shipments enable row level security;
alter table shipment_costs enable row level security;
alter table box_lm_costs enable row level security;
alter table invoice_groups enable row level security;
alter table invoice_lines enable row level security;
alter table charge_code_dictionary enable row level security;

create policy "authenticated full access" on shipments
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated full access" on shipment_costs
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated full access" on box_lm_costs
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated full access" on invoice_groups
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated full access" on invoice_lines
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create policy "authenticated full access" on charge_code_dictionary
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

-- Seed the known Last Mile charge-code dictionary
insert into charge_code_dictionary (keyword, charge_code) values
  ('base cost','LM_BASE'), ('fuel surcharge','LM_FUEL'), ('residentital surcharge ups','LM_RES'),
  ('residential surcharge','LM_RES'), ('das charges ups / fedex','LM_DAS'), ('addl wight handle charges','LM_ADDLWT'),
  ('over dim surcharges ups & fedex,amazon ground','LM_OVERDIM_A'),
  ('over dim surcharges usps, dhl & pandion,shipx ground','LM_OVERDIM_B'),
  ('over dim bt,uniuni,fedex','LM_OVERDIM_C'), ('boxc dhl additonal cost','LM_BOXC_DHL'),
  ('peak surcharge','LM_PEAK'), ('packaging surcharge','LM_PACKAGING'),
  ('fuel','LM_FUEL'), ('oversize','LM_OVERDIM_A'), ('dimensional','LM_OVERDIM_A'), ('cod','LM_COD'), ('rto','LM_RTO')
on conflict (keyword) do nothing;
