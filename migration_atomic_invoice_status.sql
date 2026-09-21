-- Fixes a confirmed bug: an invoice was found marked APPROVED in the database with 3,191
-- of its 7,075 lines still LOCKED. The app's check was "read every tag's status, THEN
-- decide, THEN write" as separate steps — a classic check-then-act race condition. If this
-- ever ran more than once in close succession (a double-click, or an overlapping retry from
-- an interrupted earlier attempt), one call could act on a stale read. The fix is to make
-- the "no LOCKED tags remain" condition part of the database WRITE itself, atomically, so
-- it can never be fooled by timing regardless of how many times or how close together it's
-- called.

create or replace function finalize_invoice_status(inv_id bigint)
returns void
language sql
security definer
as $$
  update invoices
  set status = case
    when exists (select 1 from invoice_tags where invoice_id = inv_id and status = 'DISPUTED') then 'DISPUTED'
    else 'APPROVED'
  end
  where id = inv_id
    and exists (select 1 from invoice_tags where invoice_id = inv_id)
    and not exists (select 1 from invoice_tags where invoice_id = inv_id and status = 'LOCKED');
$$;
grant execute on function finalize_invoice_status(bigint) to authenticated;

create or replace function finalize_lm_invoice_status(inv_id bigint)
returns void
language sql
security definer
as $$
  update invoices
  set status = case
    when exists (select 1 from lm_invoice_tags where invoice_id = inv_id and status = 'DISPUTED') then 'DISPUTED'
    else 'APPROVED'
  end
  where id = inv_id
    and exists (select 1 from lm_invoice_tags where invoice_id = inv_id)
    and not exists (select 1 from lm_invoice_tags where invoice_id = inv_id and status = 'LOCKED');
$$;
grant execute on function finalize_lm_invoice_status(bigint) to authenticated;
