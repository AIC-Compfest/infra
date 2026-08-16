-- Migration: 002_reconciliation_schema.sql
-- Description: Creates canonical shipment events, reconciliation cases, discrepancies, and audit log tables.
-- Reference: PRD_MVP.md §30, §31, §34, §64, §65

-- 1. Canonical Shipment Events Table
CREATE TABLE IF NOT EXISTS shipment_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    event_id VARCHAR(100) UNIQUE NOT NULL,
    shipment_id VARCHAR(100) NOT NULL,
    vendor_id VARCHAR(100) NOT NULL,
    match_confidence NUMERIC(5, 4) DEFAULT 0.0,
    invoice_id UUID REFERENCES invoices(id) ON DELETE SET NULL,
    surat_jalan_id UUID REFERENCES surat_jalans(id) ON DELETE SET NULL,
    pod_id UUID REFERENCES pods(id) ON DELETE SET NULL,
    rate_agreement_id UUID REFERENCES rate_agreements(id) ON DELETE SET NULL,
    
    -- Deterministic Pricing Results
    expected_base_charge NUMERIC(15, 2) NOT NULL,
    expected_fuel_surcharge NUMERIC(15, 2) NOT NULL,
    expected_total_charge NUMERIC(15, 2) NOT NULL,
    billed_total_charge NUMERIC(15, 2) NOT NULL,
    difference_amount NUMERIC(15, 2) NOT NULL,
    is_material BOOLEAN DEFAULT FALSE,
    calculation_trace TEXT,
    
    -- Reconciliation State
    status VARCHAR(50) DEFAULT 'MATCH' CHECK (status IN ('MATCH', 'EXCEPTION', 'MISSING', 'DUPLICATE', 'INSUFFICIENT_EVIDENCE')),
    priority_score NUMERIC(5, 2) DEFAULT 0.0,
    requires_human_review BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Reconciliation Cases (Review Queue) Table
CREATE TABLE IF NOT EXISTS reconciliation_cases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    case_id VARCHAR(100) UNIQUE NOT NULL,
    event_id UUID NOT NULL REFERENCES shipment_events(id) ON DELETE CASCADE,
    vendor_id VARCHAR(100) NOT NULL,
    status VARCHAR(50) DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'IN_REVIEW', 'APPROVED', 'DISPUTED', 'REJECTED', 'RESOLVED')),
    priority_score NUMERIC(5, 2) DEFAULT 0.0,
    financial_exposure_idr NUMERIC(15, 2) DEFAULT 0.0,
    dispute_deadline DATE,
    assigned_reviewer_id VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Discrepancies Table
CREATE TABLE IF NOT EXISTS discrepancies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    case_id UUID NOT NULL REFERENCES reconciliation_cases(id) ON DELETE CASCADE,
    code VARCHAR(100) NOT NULL,
    category VARCHAR(50) NOT NULL CHECK (category IN ('PRICING', 'SHIPMENT', 'DOCUMENTATION', 'TEMPORAL', 'SYSTEM_CONFIDENCE')),
    description TEXT NOT NULL,
    severity VARCHAR(20) DEFAULT 'WARNING' CHECK (severity IN ('CRITICAL', 'WARNING', 'INFO')),
    billed_value JSONB,
    expected_value JSONB,
    delta_amount NUMERIC(15, 2),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Review Decisions (HITL Approval / Dispute Actions) Table
CREATE TABLE IF NOT EXISTS review_decisions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    case_id UUID NOT NULL REFERENCES reconciliation_cases(id) ON DELETE CASCADE,
    action VARCHAR(50) NOT NULL CHECK (action IN ('APPROVE', 'DISPUTE', 'REJECT')),
    reviewer_id VARCHAR(100) NOT NULL,
    reviewer_role VARCHAR(50) DEFAULT 'AP_MANAGER',
    reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Audit Events (Append-Only Immutable Ledger) Table
CREATE TABLE IF NOT EXISTS audit_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    case_id UUID REFERENCES reconciliation_cases(id) ON DELETE SET NULL,
    event_id UUID REFERENCES shipment_events(id) ON DELETE SET NULL,
    action VARCHAR(100) NOT NULL,
    actor_id VARCHAR(100) NOT NULL,
    actor_role VARCHAR(50) NOT NULL,
    previous_status VARCHAR(50),
    new_status VARCHAR(50),
    notes TEXT,
    timestamp TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for querying review queue and audit log
CREATE INDEX IF NOT EXISTS idx_reconciliation_cases_status ON reconciliation_cases(status);
CREATE INDEX IF NOT EXISTS idx_reconciliation_cases_priority ON reconciliation_cases(priority_score DESC);
CREATE INDEX IF NOT EXISTS idx_discrepancies_case_id ON discrepancies(case_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_case_id ON audit_events(case_id);
CREATE INDEX IF NOT EXISTS idx_audit_events_timestamp ON audit_events(timestamp DESC);
