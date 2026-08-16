-- Migration: 003_storage_and_rls.sql
-- Description: Sets up storage bucket metadata and enforces database immutability triggers for audit trail.
-- Reference: PRD_MVP.md §36, §37, §65

-- 1. Storage Buckets Metadata Registry
CREATE TABLE IF NOT EXISTS storage_buckets (
    id VARCHAR(100) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    is_public BOOLEAN DEFAULT FALSE,
    allowed_mime_types TEXT[] DEFAULT ARRAY['application/pdf', 'image/jpeg', 'image/png'],
    max_file_size_bytes BIGINT DEFAULT 26214400,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Register default buckets
INSERT INTO storage_buckets (id, name, is_public, allowed_mime_types, max_file_size_bytes)
VALUES
    ('documents-original', 'Original Ingested Logistics Documents', FALSE, ARRAY['application/pdf', 'image/jpeg', 'image/png', 'image/heic'], 26214400),
    ('documents-preprocessed', 'Preprocessed Document Images', FALSE, ARRAY['image/jpeg', 'image/png'], 26214400),
    ('dispute-packages', 'Generated Vendor Dispute PDF Packages', FALSE, ARRAY['application/pdf', 'application/json'], 52428800)
ON CONFLICT (id) DO NOTHING;

-- 2. Audit Trail Immutability Trigger (Strict Append-Only Guarantee)
CREATE OR REPLACE FUNCTION prevent_audit_modification()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        RAISE EXCEPTION 'Security Violation: UPDATE operations are strictly prohibited on immutable audit_events table.';
    ELSIF TG_OP = 'DELETE' THEN
        RAISE EXCEPTION 'Security Violation: DELETE operations are strictly prohibited on immutable audit_events table.';
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_immutable_audit_events ON audit_events;
CREATE TRIGGER trg_immutable_audit_events
BEFORE UPDATE OR DELETE ON audit_events
FOR EACH ROW
EXECUTE FUNCTION prevent_audit_modification();
