-- Repairs the "ghost reversal" gap: invoice_tags already correctly marked REVERSED (with
-- shipment_costs already correctly settled) but with NO corresponding provision_ledger
-- REVERSED event, because the ledger insert's error was previously never checked before
-- the status update ran anyway (now fixed in the app — this script repairs what already
-- happened before that fix).
--
-- Scoped to the whole database, not just one invoice — the same bug could have affected
-- any invoice processed through the bulk-accept or single-accept path before this fix.
-- Safe to run more than once: only inserts where a NOT EXISTS check confirms the ledger
-- entry is genuinely still missing.

-- 1. See the scale before repairing anything.
select it.invoice_id, count(*) as missing_ledger_entries
from invoice_tags it
join shipment_costs sc on sc.shipment_id = it.group_key and sc.cost_header = it.cost_header
where it.group_type = 'SHIPMENT' and it.status = 'REVERSED'
  and not exists (
    select 1 from provision_ledger pl
    where pl.shipment_id = it.group_key and pl.cost_header = it.cost_header
      and pl.related_invoice_id = it.invoice_id and pl.event_type = 'REVERSED'
  )
group by it.invoice_id
order by missing_ledger_entries desc;

-- 2. The actual repair. event_date uses the same fallback chain as everywhere else:
--    the invoice's entry_date, else invoice_date, else when it was created.
insert into provision_ledger (shipment_id, cost_header, event_type, amount, event_date, related_invoice_id)
select it.group_key, it.cost_header, 'REVERSED', sc.provisional_amount,
       coalesce(i.entry_date, i.invoice_date, i.created_at::date, current_date), it.invoice_id
from invoice_tags it
join shipment_costs sc on sc.shipment_id = it.group_key and sc.cost_header = it.cost_header
join invoices i on i.id = it.invoice_id
where it.group_type = 'SHIPMENT' and it.status = 'REVERSED'
  and not exists (
    select 1 from provision_ledger pl
    where pl.shipment_id = it.group_key and pl.cost_header = it.cost_header
      and pl.related_invoice_id = it.invoice_id and pl.event_type = 'REVERSED'
  );

-- 3. Confirm afterward — should return zero rows.
-- select count(*) from invoice_tags it
-- join shipment_costs sc on sc.shipment_id = it.group_key and sc.cost_header = it.cost_header
-- where it.group_type = 'SHIPMENT' and it.status = 'REVERSED'
--   and not exists (select 1 from provision_ledger pl where pl.shipment_id = it.group_key
--     and pl.cost_header = it.cost_header and pl.related_invoice_id = it.invoice_id and pl.event_type = 'REVERSED');
