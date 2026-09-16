-- Run this AFTER migration_pnl_view.sql (or instead of it, if that one hasn't run yet —
-- this drops and replaces it either way).
--
-- The plain VIEW from migration_pnl_view.sql was the wrong tool: a view with GROUP BY
-- is not free to paginate — every .range() page request makes Postgres re-run the full
-- aggregation over shipment_costs from scratch, so 24 pages meant recomputing the whole
-- thing 24 times. A MATERIALIZED view computes it once and stores the result like a real
-- table, so reads are cheap — the cost only shows up when you explicitly refresh it.

drop view if exists pnl_shipment_level;

create materialized view pnl_shipment_level as
select
  s.shipment_id,
  coalesce(s.lob, 'Unassigned') as lob,
  coalesce(s.revenue_amount, 0) as revenue,
  coalesce(sum(sc.provisional_amount), 0) as prov_cost,
  coalesce(sum(coalesce(sc.actual_amount, sc.provisional_amount)), 0) as act_cost,
  count(sc.cost_header) as header_count,
  bool_or(sc.actual_amount is null) as any_unsettled
from shipments s
left join shipment_costs sc on sc.shipment_id = s.shipment_id
group by s.shipment_id, s.lob, s.revenue_amount;

-- Required for REFRESH ... CONCURRENTLY, which refreshes without locking out readers.
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

-- Populate it once now, so the very first P&L load after this migration has data
-- immediately rather than showing an empty table until someone clicks Refresh.
refresh materialized view pnl_shipment_level;
