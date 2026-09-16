-- =====================================================================
-- ALL MIGRATIONS, CONSOLIDATED — run this whole file once, top to bottom.
--
-- Every statement here is idempotent (IF NOT EXISTS / IF EXISTS / OR REPLACE),
-- so it's safe to run again on a database that already has some or all of
-- this applied — nothing will error or duplicate.
--
-- PREREQUISITE: this assumes schema.sql has ALREADY been run first (it
-- creates the base tables — invoices, shipments, shipment_costs, etc. —
-- that everything below adds to or builds on). This file does not include
-- schema.sql itself; run that first on a genuinely fresh database.
--
-- Supersedes and replaces: migration_fx_and_delete.sql, migration_lm_tags.sql,
-- migration_shipment_attributes.sql, migration_pnl_pickup_date.sql
-- (migration_pnl_view.sql and migration_pnl_materialized.sql are intentionally
-- NOT included — both were superseded by migration_pnl_pickup_date.sql, whose
-- content is what appears below; running the older two as well would just be
-- wasted work, not wrong, since the final DROP+CREATE here supersedes them.)
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1. FX rates master + currency tracking on invoice_tags, and CANCELLED
--    status support for invoices (no column needed — status is already text).
-- ---------------------------------------------------------------------
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
drop policy if exists "authenticated full access" on fx_rates;
create policy "authenticated full access" on fx_rates
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
insert into fx_rates (currency, rate_to_inr) values ('INR', 1) on conflict (currency) do nothing;


-- ---------------------------------------------------------------------
-- 2. Last Mile invoice tags — proper tag-based reconciliation for boxes,
--    mirroring invoice_tags/shipment_costs (replaces the old direct-write
--    mechanism that never actually reverse-provisioned).
-- ---------------------------------------------------------------------
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
drop policy if exists "authenticated full access" on lm_invoice_tags;
create policy "authenticated full access" on lm_invoice_tags
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');


-- ---------------------------------------------------------------------
-- 3. Shipment attributes — flexible, growing, named attribute store
--    (Product, Country, etc.) with no schema change needed per new one.
-- ---------------------------------------------------------------------
create table if not exists shipment_attributes (
  id bigint generated always as identity primary key,
  shipment_id text references shipments(shipment_id) on delete cascade,
  attribute_name text not null,
  value text,
  updated_at timestamptz default now(),
  unique(shipment_id, attribute_name)
);
alter table shipment_attributes enable row level security;
drop policy if exists "authenticated full access" on shipment_attributes;
create policy "authenticated full access" on shipment_attributes
  for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');
create index if not exists idx_shipattr_shipment on shipment_attributes(shipment_id);
create index if not exists idx_shipattr_name on shipment_attributes(attribute_name);


-- ---------------------------------------------------------------------
-- 4. P&L materialized view (final version, includes pickup_date for the
--    date filter). A MATERIALIZED view, not a plain one — a plain view
--    with GROUP BY re-runs the full aggregation on every paginated read,
--    which is what caused P&L to hang; this is computed once and stored.
-- ---------------------------------------------------------------------
drop materialized view if exists pnl_shipment_level;

create materialized view pnl_shipment_level as
select
  s.shipment_id,
  coalesce(s.lob, 'Unassigned') as lob,
  s.pickup_date,
  coalesce(s.revenue_amount, 0) as revenue,
  coalesce(sum(sc.provisional_amount), 0) as prov_cost,
  coalesce(sum(coalesce(sc.actual_amount, sc.provisional_amount)), 0) as act_cost,
  count(sc.cost_header) as header_count,
  bool_or(sc.actual_amount is null) as any_unsettled
from shipments s
left join shipment_costs sc on sc.shipment_id = s.shipment_id
group by s.shipment_id, s.lob, s.pickup_date, s.revenue_amount;

create unique index if not exists idx_pnl_shipment_level_id on pnl_shipment_level(shipment_id);
grant select on pnl_shipment_level to authenticated;

-- PostgREST can't call REFRESH MATERIALIZED VIEW directly — wrap it in a callable function.
create or replace function refresh_pnl_shipment_level()
returns void
language sql
security definer
as $$
  refresh materialized view concurrently pnl_shipment_level;
$$;
grant execute on function refresh_pnl_shipment_level() to authenticated;

-- Populate it once now, so the first P&L load after this migration has data immediately.
refresh materialized view pnl_shipment_level;

-- =====================================================================
-- Done. Expect no errors on a re-run against a database that already has
-- some of this — every statement is written to be safely repeatable.
-- =====================================================================
