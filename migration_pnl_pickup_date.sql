-- Run this once. Recreates pnl_shipment_level with pickup_date included, needed for the
-- new date/month filter — materialized views can't be ALTERed to add a column, only
-- dropped and recreated.

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

create or replace function refresh_pnl_shipment_level()
returns void
language sql
security definer
as $$
  refresh materialized view concurrently pnl_shipment_level;
$$;
grant execute on function refresh_pnl_shipment_level() to authenticated;

refresh materialized view pnl_shipment_level;
