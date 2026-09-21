-- Deletes ONE specific invoice and everything linked to it, releasing its locks back to
-- OPEN so the underlying provisional data is ready for a fresh invoice to be created and
-- matched against again. Same pattern as the earlier full-reset script, scoped to a single
-- invoice_id instead of everything.
--
-- Replace every 12345 below with the actual invoice id before running (find & replace).
-- Deliberately NOT touched: shipments, shipment_attributes, provisional_amount, and BOOKED
-- ledger events — none of that is invoice activity, it's the underlying cost data and stays
-- exactly as-is, ready to be matched against the re-upload.

-- 1. Release every lock this invoice created, clearing settled amounts back to a clean slate.
update shipment_costs
set status = 'OPEN', actual_amount = null, locked_by_invoice_id = null
where locked_by_invoice_id = 12345;

update box_lm_costs
set status = 'OPEN', actual_amount = null, locked_by_invoice_id = null
where locked_by_invoice_id = 12345;

-- 2. Remove only this invoice's REVERSED ledger entries (both the genuine ones and the
--    642 duplicates / ~2,700 ghost gaps discussed above — all cleanly gone either way).
--    BOOKED events are untouched regardless, since those never belonged to this invoice.
delete from provision_ledger where related_invoice_id = 12345 and event_type = 'REVERSED';

-- 3. Remove everything that references this invoice, before removing the invoice itself.
delete from disputes where invoice_id = 12345;
delete from approval_actions where invoice_id = 12345;
delete from invoice_tags where invoice_id = 12345;
delete from lm_invoice_tags where invoice_id = 12345;
delete from invoices where id = 12345;

-- Sanity check afterward — every one of these should come back 0:
-- select
--   (select count(*) from invoices where id = 12345) as invoice_still_exists,
--   (select count(*) from invoice_tags where invoice_id = 12345) as tags_remaining,
--   (select count(*) from provision_ledger where related_invoice_id = 12345 and event_type='REVERSED') as reversed_ledger_remaining,
--   (select count(*) from shipment_costs where locked_by_invoice_id = 12345) as still_locked;
