-- Cost Subledger — Phase 1 (simplified allocation + full approval workflow)
-- Run once in Supabase SQL Editor.

-- ============================= REFERENCE / MASTERS =============================

create table if not exists cost_headers (
  code text primary key,
  label text not null,
  allocation_grain text not null -- 'NODE_PERIOD' | 'MAWB' | 'SHIPMENT'
);
insert into cost_headers (code,label,allocation_grain) values
  ('PICKUP','Pickup','NODE_PERIOD'),
  ('FM','First Mile','NODE_PERIOD'),
  ('HUB','Hub','NODE_PERIOD'),
  ('OC','Origin Customs','MAWB'),
  ('MM','Middle Mile','MAWB'),
  ('DC','Destination Handling','MAWB'),
  ('DESTCLEAR','Destination Clearance','MAWB'),
  ('IOR','IOR','MAWB'),
  ('OCEAN','Ocean','MAWB'),
  ('TRANSSHIP','Trans-shipment','MAWB'),
  ('LM_PICKUP','LM Pickup','SHIPMENT'),
  ('LM','Last Mile','SHIPMENT'),        -- has box/charge-code detail beneath it
  ('AGGREGATION','Aggregation','SHIPMENT'),
  ('INDIA_UK_MM','India to UK MM','MAWB')
on conflict (code) do nothing;

create table if not exists vendors (
  code text primary key,
  name text not null,
  created_at timestamptz default now()
);

create table if not exists charge_code_master (
  charge_code text primary key,
  label text,
  cost_header text references cost_headers(code),
  vendor_code text references vendors(code),
  reimbursable_default boolean default false,
  created_at timestamptz default now()
);

-- Approval routing thresholds, configurable per LOB x Cost Header.
-- Escalation is AND-gated: both pct AND value must be breached to move up a level.
create table if not exists approval_thresholds (
  lob text not null,
  cost_header text references cost_headers(code),
  finance_head_pct numeric default 2,
  finance_head_value numeric default 10000,
  ceo_pct numeric default 5,
  ceo_value numeric default 500000,
  primary key (lob, cost_header)
);

-- ============================= SHIPMENTS & PROVISIONAL COST =============================

create table if not exists shipments (
  shipment_id text primary key,
  lob text,
  node text,
  pickup_date date,
  mawb text,
  gross_weight numeric,
  revenue_amount numeric,
  revenue_currency text default 'INR',
  shipment_status text default 'ACTIVE', -- ACTIVE | CANCELLED
  updated_at timestamptz default now()
);
create index if not exists idx_shipments_mawb on shipments(mawb);
create index if not exists idx_shipments_node_pickup on shipments(node, pickup_date);

-- One row per shipment + cost header (no charge code, except LM which has box detail below).
-- This is the lockable/reversible unit for every header except LM.
create table if not exists shipment_costs (
  shipment_id text references shipments(shipment_id) on delete cascade,
  cost_header text references cost_headers(code),
  provisional_amount numeric not null,
  currency text default 'INR',
  actual_amount numeric,              -- cumulative actual recorded against this shipment+header
  status text default 'OPEN',         -- OPEN | LOCKED | REVERSED | WRITTEN_BACK
  locked_by_invoice_id bigint,
  source_file text,
  uploaded_at timestamptz default now(),
  primary key (shipment_id, cost_header)
);

-- Last Mile box-level charge-code detail (unchanged shape from the pilot).
create table if not exists box_lm_costs (
  id bigint generated always as identity primary key,
  shipment_id text not null,
  box_id text not null,
  lm_partner text,
  lm_tracking_number text,
  charge_code text,
  amount numeric not null,
  currency text default 'INR',
  weight_used numeric,
  weight_unit text,
  length_used numeric, width_used numeric, height_used numeric, dim_unit text,
  address_fba_id text,
  actual_amount numeric,
  status text default 'OPEN',         -- OPEN | LOCKED | REVERSED | WRITTEN_BACK
  locked_by_invoice_id bigint,
  source text default 'file',
  uploaded_at timestamptz default now()
);
create index if not exists idx_boxlm_shipment on box_lm_costs(shipment_id);
create index if not exists idx_boxlm_box_code on box_lm_costs(box_id, charge_code);

-- ============================= INVOICES & TAGGING =============================

create table if not exists invoices (
  id bigint generated always as identity primary key,
  vendor_code text references vendors(code),
  invoice_number text,
  invoice_date date,
  currency text default 'INR',
  taxable_amount numeric not null,     -- GST/tax excluded — this is what reconciles
  total_amount numeric,                -- incl. tax, reference only
  source_file_path text not null,      -- mandatory
  backup_file_path text,
  status text default 'DRAFT',         -- DRAFT | PENDING_APPROVAL | APPROVED | REJECTED | DISPUTED
  current_level text,                  -- LOB_OWNER | FINANCE_HEAD | CEO | FINANCE_MGR_WILDCARD
  entered_by uuid,
  is_multi_lob boolean default false,
  duplicate_of_invoice_id bigint,       -- set if vendor+invoice_number matched an existing one
  created_at timestamptz default now()
);

-- Which shipment/MAWB-group/node-period-group + cost header(s) this invoice is tagged against.
create table if not exists invoice_tags (
  id bigint generated always as identity primary key,
  invoice_id bigint references invoices(id) on delete cascade,
  cost_header text references cost_headers(code),
  group_type text not null,             -- 'MAWB' | 'NODE_PERIOD' | 'SHIPMENT'
  group_key text not null,              -- mawb value, or 'node|period', or shipment_id
  entered_amount numeric,               -- optional manual split; null = compare against summed group total
  status text default 'LOCKED',         -- LOCKED | RELEASED | REVERSED
  tagged_by uuid,
  tagged_at timestamptz default now(),
  edit_reason text                      -- mandatory if this tag was edited after initial entry
);

-- Raw charge lines parsed off the invoice — feeds the Charge Code Master, not used for matching yet.
create table if not exists invoice_lines (
  id bigint generated always as identity primary key,
  invoice_id bigint references invoices(id) on delete cascade,
  charge_code_raw text,
  charge_code text,
  amount numeric,
  currency text default 'INR'
);

-- ============================= APPROVAL WORKFLOW =============================

create table if not exists approval_actions (
  id bigint generated always as identity primary key,
  invoice_id bigint references invoices(id) on delete cascade,
  action text not null,   -- ENTERED | TAGGED | TAG_EDITED | APPROVED | REJECTED | SENT_BACK | REASSIGNED | ESCALATED | OVERRIDE
  level text,             -- level this action happened at
  actor uuid,
  reassigned_to uuid,
  reason text,
  is_escalation_driven boolean default false,
  created_at timestamptz default now()
);

-- ============================= DISPUTES & CREDIT NOTES =============================

create table if not exists disputes (
  id bigint generated always as identity primary key,
  invoice_id bigint references invoices(id) on delete cascade,
  status text default 'RAISED',   -- RAISED | AGREED | DENIED | SETTLED
  dispute_text text,              -- vendor-facing dispute description
  resolution_reason text,         -- mandatory for DENIED (why our data was wrong) or context for SETTLED
  settled_basis text,             -- free text: e.g. "715kg at Rs500" — negotiated final figure
  raised_by uuid,
  resolved_by uuid,
  created_at timestamptz default now(),
  resolved_at timestamptz
);

create table if not exists credit_notes (
  id bigint generated always as identity primary key,
  invoice_id bigint references invoices(id) on delete cascade,
  dispute_id bigint references disputes(id),
  amount numeric not null,
  reason text,
  created_at timestamptz default now()
);

-- ============================= REIMBURSABLE CHARGES =============================

create table if not exists reimbursement_decisions (
  id bigint generated always as identity primary key,
  invoice_id bigint references invoices(id),
  charge_code text,
  shipment_id text,               -- always shipment-specific, never pool-spread
  proposed_reimbursable boolean,  -- proposed by entry-level user
  decided_by uuid,                -- only an authorised approver can decide
  decision text,                  -- 'PURSUE' | 'ABSORB'
  reason_if_absorbed text,        -- mandatory if decision = ABSORB despite being reimbursable-type
  reimburse_against_shipment_id text,
  created_at timestamptz default now()
);

-- ============================= WRITE-BACK LEDGER =============================

create table if not exists cost_written_back_ledger (
  id bigint generated always as identity primary key,
  group_type text,                -- 'SHIPMENT' | 'MAWB' | 'NODE_PERIOD'
  group_key text,
  cost_header text,
  amount numeric not null,
  reason text not null,
  actioned_by uuid,
  actioned_at timestamptz default now()
);

-- ============================= ACCESS MANAGEMENT =============================

create table if not exists user_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null,     -- FINANCE_EXECUTIVE | LOB_OWNER | FINANCE_HEAD | CEO | FINANCE_MANAGER | ADMIN
  lob text,               -- populated when role = LOB_OWNER
  created_at timestamptz default now()
);

-- ============================= ROW LEVEL SECURITY =============================
-- Kept simple for the pilot: any authenticated user can read/write. Role-based
-- restriction is enforced in the app layer for now; tighten with per-role
-- policies once the workflow is stable and engineering takes this over.

do $$
declare t text;
begin
  for t in select unnest(array[
    'cost_headers','vendors','charge_code_master','approval_thresholds',
    'shipments','shipment_costs','box_lm_costs','invoices','invoice_tags',
    'invoice_lines','approval_actions','disputes','credit_notes',
    'reimbursement_decisions','cost_written_back_ledger','user_profiles'
  ])
  loop
    execute format('alter table %I enable row level security', t);
    execute format('create policy "authenticated full access" on %I for all using (auth.role() = ''authenticated'') with check (auth.role() = ''authenticated'')', t);
  end loop;
end $$;

-- Seed default approval thresholds (placeholders — configurable per LOB later)
insert into approval_thresholds (lob, cost_header, finance_head_pct, finance_head_value, ceo_pct, ceo_value)
select lob, code, 2, 10000, 5, 500000
from (values ('Xindus Lite'),('Air Premium'),('Air Xpress'),('Xpress B2B')) as l(lob)
cross join cost_headers
on conflict (lob, cost_header) do nothing;
