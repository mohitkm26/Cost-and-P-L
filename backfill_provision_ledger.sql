-- Run this ONCE, after migration_month_end_close.sql, to reconstruct ledger history from
-- data that already existed before this feature shipped. Every insert is protected by a
-- NOT EXISTS check against provision_ledger, so this is safe to run more than once — it
-- will never create a duplicate event, and any real events written by live usage since
-- deployment are left completely untouched.
--
-- Dates used: BOOKED -> the shipment's pickup_date. REVERSED -> the linked invoice's
-- entry_date if set, else invoice_date, else the invoice's created_at date — entry_date
-- didn't exist before this feature, so every backfilled REVERSED event falls back to
-- whatever real date is closest to when it actually happened.

-- 1. BOOKED events from shipment_costs (Other Headers' cost grain).
insert into provision_ledger (shipment_id, cost_header, event_type, amount, event_date, related_invoice_id)
select sc.shipment_id, sc.cost_header, 'BOOKED', sc.provisional_amount,
       coalesce(s.pickup_date, current_date), null
from shipment_costs sc
join shipments s on s.shipment_id = sc.shipment_id
where sc.provisional_amount is not null
  and not exists (
    select 1 from provision_ledger pl
    where pl.shipment_id = sc.shipment_id and pl.cost_header = sc.cost_header and pl.event_type = 'BOOKED'
  );

-- 2. REVERSED events from shipment_costs rows already settled against a real invoice.
insert into provision_ledger (shipment_id, cost_header, event_type, amount, event_date, related_invoice_id)
select sc.shipment_id, sc.cost_header, 'REVERSED', sc.provisional_amount,
       coalesce(i.entry_date, i.invoice_date, i.created_at::date, current_date), sc.locked_by_invoice_id
from shipment_costs sc
join invoices i on i.id = sc.locked_by_invoice_id
where sc.status = 'REVERSED' and sc.locked_by_invoice_id is not null
  and not exists (
    select 1 from provision_ledger pl
    where pl.shipment_id = sc.shipment_id and pl.cost_header = sc.cost_header
      and pl.event_type = 'REVERSED' and pl.related_invoice_id = sc.locked_by_invoice_id
  );

-- 3. BOOKED events from box_lm_costs (Last Mile's box grain), aggregated per shipment
--    under the standard 'LM' header — same convention the live code already uses.
insert into provision_ledger (shipment_id, cost_header, event_type, amount, event_date, related_invoice_id)
select b.shipment_id, 'LM', 'BOOKED', sum(b.amount), coalesce(max(s.pickup_date), current_date), null
from box_lm_costs b
join shipments s on s.shipment_id = b.shipment_id
where not exists (
    select 1 from provision_ledger pl
    where pl.shipment_id = b.shipment_id and pl.cost_header = 'LM' and pl.event_type = 'BOOKED'
  )
group by b.shipment_id;

-- 4. REVERSED events from box_lm_costs rows already settled against a real invoice.
insert into provision_ledger (shipment_id, cost_header, event_type, amount, event_date, related_invoice_id)
select b.shipment_id, 'LM', 'REVERSED', sum(b.amount),
       coalesce(max(i.entry_date), max(i.invoice_date), max(i.created_at::date), current_date), b.locked_by_invoice_id
from box_lm_costs b
join invoices i on i.id = b.locked_by_invoice_id
where b.status = 'REVERSED' and b.locked_by_invoice_id is not null
  and not exists (
    select 1 from provision_ledger pl
    where pl.shipment_id = b.shipment_id and pl.cost_header = 'LM'
      and pl.event_type = 'REVERSED' and pl.related_invoice_id = b.locked_by_invoice_id
  )
group by b.shipment_id, b.locked_by_invoice_id;

-- Sanity check afterward — compare against what you expect:
-- select event_type, cost_header, count(*), sum(amount) from provision_ledger group by 1,2 order by 1,2;
