-- Migration: 005_add_approved_status_and_sod_support.sql
-- Description: Adds 'APPROVED', 'DISPUTED', 'REJECTED', 'RESOLVED' to shipment_events and reconciliation_cases status constraints for SoD and Human-in-the-Loop approval workflows.
-- Reference: PRD_MVP.md §34, §36, §37, §64

-- 1. Update status check constraint on shipment_events
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'shipment_events_status_check'
    ) THEN
        ALTER TABLE shipment_events DROP CONSTRAINT shipment_events_status_check;
    END IF;
END $$;

ALTER TABLE shipment_events 
    ADD CONSTRAINT shipment_events_status_check 
    CHECK (status IN ('MATCH', 'EXCEPTION', 'MISSING', 'DUPLICATE', 'INSUFFICIENT_EVIDENCE', 'APPROVED', 'DISPUTED', 'REJECTED', 'RESOLVED'));

-- 2. Update status check constraint on reconciliation_cases
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'reconciliation_cases_status_check'
    ) THEN
        ALTER TABLE reconciliation_cases DROP CONSTRAINT reconciliation_cases_status_check;
    END IF;
END $$;

ALTER TABLE reconciliation_cases 
    ADD CONSTRAINT reconciliation_cases_status_check 
    CHECK (status IN ('OPEN', 'IN_REVIEW', 'APPROVED', 'DISPUTED', 'REJECTED', 'RESOLVED'));

-- 3. Create index for fast status queries on shipment_events
CREATE INDEX IF NOT EXISTS idx_shipment_events_status ON shipment_events(status);
