-- Run this once in Supabase SQL Editor. Fixes P&L never finishing/populating: the previous
-- approach pulled every shipment_costs row (potentially hundreds of thousands, given every
-- Accept action writes one row per shipment) into the browser just to sum them. This view
-- does that summing in the database instead — the browser only ever receives one row per
-- shipment, which already loads fast regardless of how large shipment_costs itself gets.

create or replace view pnl_shipment_level as
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

-- Views don't automatically inherit the underlying tables' RLS policies — grant access
-- to the authenticated role explicitly, same role every other policy in this app uses.
grant select on pnl_shipment_level to authenticated;
