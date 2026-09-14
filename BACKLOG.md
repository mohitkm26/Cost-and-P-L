# Cost Subledger — Build Backlog
*Compiled from the full testing session. Items marked DONE were built in this pass — check them against real usage before trusting fully. Everything else, plus the three open design questions, is still outstanding.*

---

## Confirmed bugs

| # | Bug | Status |
|---|---|---|
| B1 | Timezone date-shift at month boundaries | **DONE** — date parsing rewritten to be guaranteed UTC-safe throughout (no more `cellDates:true`, no local Date getters, no generic string-to-Date parsing). Re-upload and re-check counts to confirm. |
| B2 | Accept action fails silently on the final status write | **DONE** — every write in accept/dispute now checks for an error and alerts rather than failing silently. |
| B3 | Stale Accept button risk | **DONE** — direct consequence of B2's fix; button state now only changes once the write actually succeeds. |
| B4 | Export vs. Accept can compute from different snapshots | **DONE** — both now read from one cached snapshot per detail-view session instead of independent live queries. |

## Missing safeguards

| # | Item | Status |
|---|---|---|
| S1 | Invoice creation not blocked on zero shipment match | **DONE** — both the single-entry form and multi-MAWB batch block creation (not just acceptance) on a zero-match group. |
| S2 | No way to delete/cancel a pending invoice | **DONE** — "Cancel this invoice" releases every lock back to OPEN and soft-deletes (status CANCELLED) for audit trail. |
| S3 | Duplicate-flagged invoices can still be Accepted freely | **DONE** — accepting a flagged duplicate now requires an explicit confirm. |

## UI/UX fixes

| # | Item | Status |
|---|---|---|
| U1 | Group key fields should be dropdowns/autocomplete, not free text | **DONE** — Node dropdown + native month picker for Node+Period; live search-as-you-type (datalist-backed) for MAWB and Shipment ID. Only built for the single-entry form, not the batch file (which doesn't need it). |
| U2 | Header display order should be fixed, not alphabetical | **DONE** — applied to Shipment Lookup and P&L drill-down. |
| U3 | Margin % missing from Shipment Lookup summary | **DONE** — Provisional GM% and Actual GM% now shown alongside revenue. |
| U4 | Invoice reference shows internal ID only | **DONE** — Shipment Lookup and P&L drill-down now show vendor + invoice number, with a "(view)" link to the invoice detail and an "(export allocation)" link where applicable. |
| U5 | Allocation Excel export missing key columns | **DONE** — now includes Provisional Amount, Delta, and Delta % alongside Weight/Share%/Allocated Amount. |
| U6 | Multi-MAWB batch file's identifier column is MAWB-only | **DONE** — batch file now accepts either a MAWB or a Shipment column per row, determining that row's group type automatically. |

## Design questions — still open, nothing built against these

| # | Question |
|---|---|
| D1 | Pickup (and possibly Hub, First Mile) need to support more than one grain — fixed vehicle pool (Node+Period) vs. adhoc/courier (shipment-level) — chosen per invoice, not hardcoded. **Not built.** |
| D2 | Aggregation, Ocean, and Trans-shipment cost logic was never validated against a real invoice the way Pickup/MM/OC/DC were. Ocean specifically may need volume(CBM)-based allocation and a different grouping key than MAWB. **Not built — needs real invoices first.** |
| D3 | Date-wise export grain — assumed as a pickup-date-filtered version of the Shipment Level report for the Reports section below. **Assumption made to unblock Reports; not confirmed with you.** |

## New section — not yet built

**Reports section** (separate tab, for offline download/analysis) — still entirely unbuilt:
- Header Level, Invoice Level, Shipment Level, Date-wise exports
- Filterable by pickup-date range, downloadable as Excel

## Currency / FX handling

**DONE**: schema migration (`migration_fx_and_delete.sql` — run this in Supabase before using the new build), FX Rates master UI under Access & Thresholds, multi-MAWB batch file now parses a per-row Currency column, converts using the rate on file, and locks that rate to the invoice line permanently (original currency/amount/rate all stored alongside the converted INR figure).

**Still deferred, as agreed**: separating "real cost variance" from "FX movement between provisioning and invoicing" — full allocation happens at the locked rate, no decomposition yet.

---

*Migration required before this build works: run `migration_fx_and_delete.sql` in Supabase SQL Editor first — it adds the FX rates table and new columns this version depends on.*
