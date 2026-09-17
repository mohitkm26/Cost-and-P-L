-- Resets every invoice-side test record: invoices, their tags (Other Headers and Last
-- Mile), disputes, action logs, and the REVERSED half of the provision ledger.
-- Also releases every lock this created, bringing shipment_costs and box_lm_costs back
-- to a clean OPEN state — as if no invoice had ever touched them.
--
-- Deliberately NOT touched: shipments, shipment_attributes, the provisional_amount
-- values themselves, and BOOKED ledger events — none of that came from invoice
-- activity, it's your underlying cost data and stays exactly as-is.
--
-- This is irreversible. Run it only because these are genuinely test invoices with
-- nothing real behind them.

-- 1. Release every lock and clear every settled amount, back to a clean slate.
update shipment_costs
set status = 'OPEN', actual_amount = null, locked_by_invoice_id = null
where status in ('LOCKED', 'REVERSED') or locked_by_invoice_id is not null;

update box_lm_costs
set status = 'OPEN', actual_amount = null, locked_by_invoice_id = null
where status in ('LOCKED', 'REVERSED') or locked_by_invoice_id is not null;

-- 2. Remove only the REVERSED half of the ledger — BOOKED events are your real
--    provisional-cost history (from shipment uploads, nothing to do with invoices)
--    and must stay exactly as they are.
delete from provision_ledger where event_type = 'REVERSED';

-- 3. Remove everything that references an invoice, before removing the invoices
--    themselves — explicit, rather than relying on cascade behavior being set up
--    the same way on every one of these tables.
delete from disputes;
delete from approval_actions;
delete from invoice_tags;
delete from lm_invoice_tags;
delete from invoices;

-- Sanity check afterward — every one of these should come back 0:
-- select
--   (select count(*) from invoices) as invoices,
--   (select count(*) from invoice_tags) as invoice_tags,
--   (select count(*) from lm_invoice_tags) as lm_invoice_tags,
--   (select count(*) from disputes) as disputes,
--   (select count(*) from approval_actions) as approval_actions,
--   (select count(*) from provision_ledger where event_type='REVERSED') as reversed_ledger_entries,
--   (select count(*) from shipment_costs where status != 'OPEN') as still_locked_costs,
--   (select count(*) from box_lm_costs where status != 'OPEN') as still_locked_boxes;
