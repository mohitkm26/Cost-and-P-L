-- Removes duplicate REVERSED ledger entries caused by a bug in the bulk-accept path: if
-- the final invoice_tags status-update step failed to complete for some lines after their
-- shipment_costs/ledger writes had already succeeded, those lines stayed selectable and got
-- re-processed on a later retry, writing a second identical ledger row. Confirmed on invoice
-- <fill in the invoice ID> via direct query: 642 shipment+header combinations had the exact
-- same reversal recorded twice (identical amount, identical date), inflating that invoice's
-- reported "Provisions Reversed" by ₹4,72,708.
--
-- Keeps exactly one row per (shipment_id, cost_header, related_invoice_id, event_type)
-- combination — the earliest one, by id — and deletes any extras. Does NOT touch anything
-- with only one row for its combination.
--
-- Run the check query first to see the scale before deleting anything.

-- 1. See what this would remove before running the delete.
select shipment_id, cost_header, related_invoice_id, count(*) as copies, sum(amount) as total_if_all_kept
from provision_ledger
where event_type = 'REVERSED'
group by shipment_id, cost_header, related_invoice_id
having count(*) > 1
order by related_invoice_id, shipment_id;

-- 2. The actual cleanup — deletes every row except the earliest (lowest id) per combination.
delete from provision_ledger pl
using (
  select id,
         row_number() over (partition by shipment_id, cost_header, related_invoice_id, event_type order by id) as rn
  from provision_ledger
  where event_type = 'REVERSED'
) ranked
where pl.id = ranked.id and ranked.rn > 1;

-- 3. Confirm afterward — should return zero rows.
-- select shipment_id, cost_header, related_invoice_id, count(*)
-- from provision_ledger where event_type='REVERSED'
-- group by shipment_id, cost_header, related_invoice_id having count(*) > 1;
