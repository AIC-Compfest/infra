-- Migration: 001_initial_schema.sql
-- Description: Creates master document, extraction, shipment, invoice, POD, Surat Jalan, and Contract tables.
-- Reference: PRD_MVP.md §64, §65

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Documents Ingestion Table
CREATE TABLE IF NOT EXISTS documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    filename VARCHAR(255) NOT NULL,
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    sha256_hash VARCHAR(64) UNIQUE NOT NULL,
    storage_path VARCHAR(500) NOT NULL,
    status VARCHAR(50) DEFAULT 'QUEUED' CHECK (status IN ('QUEUED', 'PROCESSING', 'COMPLETED', 'FAILED')),
    classification VARCHAR(50) DEFAULT 'UNKNOWN' CHECK (classification IN ('INVOICE', 'SURAT_JALAN', 'POD', 'RATE_AGREEMENT', 'UNKNOWN')),
    classification_confidence NUMERIC(5, 4) DEFAULT 0.0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Document Pages Table
CREATE TABLE IF NOT EXISTS document_pages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    page_number INT NOT NULL,
    width INT NOT NULL,
    height INT NOT NULL,
    ocr_text TEXT,
    ocr_confidence NUMERIC(5, 4) DEFAULT 0.0,
    layout_json JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (document_id, page_number)
);

-- 3. Document Extractions Table
CREATE TABLE IF NOT EXISTS document_extractions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    schema_version VARCHAR(50) DEFAULT '0.1.0',
    extracted_json JSONB NOT NULL,
    overall_confidence NUMERIC(5, 4) DEFAULT 0.0,
    extraction_method VARCHAR(50) DEFAULT 'ocr',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Shipments Master Table
CREATE TABLE IF NOT EXISTS shipments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shipment_id VARCHAR(100) UNIQUE NOT NULL,
    origin VARCHAR(100) NOT NULL,
    destination VARCHAR(100) NOT NULL,
    service_type VARCHAR(50) DEFAULT 'REGULAR',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Invoices Table
CREATE TABLE IF NOT EXISTS invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id UUID REFERENCES documents(id) ON DELETE SET NULL,
    invoice_number VARCHAR(100) UNIQUE NOT NULL,
    vendor_id VARCHAR(100) NOT NULL,
    vendor_name VARCHAR(255) NOT NULL,
    customer_id VARCHAR(100),
    customer_name VARCHAR(255),
    billing_period_start DATE,
    billing_period_end DATE,
    invoice_date DATE NOT NULL,
    due_date DATE,
    currency VARCHAR(10) DEFAULT 'IDR',
    subtotal NUMERIC(15, 2) NOT NULL,
    tax_amount NUMERIC(15, 2) DEFAULT 0.0,
    grand_total NUMERIC(15, 2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Invoice Line Items Table
CREATE TABLE IF NOT EXISTS invoice_line_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    invoice_id UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    line_number INT NOT NULL,
    shipment_id VARCHAR(100) NOT NULL,
    awb_number VARCHAR(100),
    service_type VARCHAR(50) DEFAULT 'REGULAR',
    origin VARCHAR(100),
    destination VARCHAR(100),
    weight_kg NUMERIC(10, 2) NOT NULL,
    base_charge NUMERIC(15, 2) NOT NULL,
    fuel_surcharge NUMERIC(15, 2) DEFAULT 0.0,
    fuel_surcharge_percent NUMERIC(5, 2) DEFAULT 0.0,
    line_total NUMERIC(15, 2) NOT NULL,
    evidence_json JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (invoice_id, line_number)
);

-- 7. Surat Jalan Table
CREATE TABLE IF NOT EXISTS surat_jalans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id UUID REFERENCES documents(id) ON DELETE SET NULL,
    surat_jalan_number VARCHAR(100) UNIQUE NOT NULL,
    shipment_id VARCHAR(100) NOT NULL,
    awb_number VARCHAR(100),
    shipment_date DATE NOT NULL,
    sender_name VARCHAR(255),
    sender_city VARCHAR(100),
    receiver_name VARCHAR(255),
    receiver_city VARCHAR(100),
    actual_weight_kg NUMERIC(10, 2) NOT NULL,
    total_packages INT DEFAULT 1,
    item_description TEXT,
    evidence_json JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. Proof of Delivery (POD) Table
CREATE TABLE IF NOT EXISTS pods (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id UUID REFERENCES documents(id) ON DELETE SET NULL,
    pod_number VARCHAR(100) UNIQUE NOT NULL,
    shipment_id VARCHAR(100) NOT NULL,
    awb_number VARCHAR(100),
    delivery_status VARCHAR(50) DEFAULT 'DELIVERED' CHECK (delivery_status IN ('DELIVERED', 'PARTIALLY_DELIVERED', 'FAILED', 'RETURNED')),
    delivery_date DATE NOT NULL,
    receiver_name VARCHAR(255),
    condition VARCHAR(50) DEFAULT 'GOOD',
    signature_present BOOLEAN DEFAULT FALSE,
    signature_confidence NUMERIC(5, 4) DEFAULT 0.0,
    signature_bbox JSONB,
    stamp_present BOOLEAN DEFAULT FALSE,
    stamp_bbox JSONB,
    evidence_json JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. Rate Agreements Table
CREATE TABLE IF NOT EXISTS rate_agreements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    document_id UUID REFERENCES documents(id) ON DELETE SET NULL,
    agreement_id VARCHAR(100) UNIQUE NOT NULL,
    vendor_id VARCHAR(100) NOT NULL,
    vendor_name VARCHAR(255) NOT NULL,
    effective_from DATE NOT NULL,
    effective_to DATE NOT NULL,
    currency VARCHAR(10) DEFAULT 'IDR',
    fuel_surcharge_percent NUMERIC(5, 2) DEFAULT 14.0,
    minimum_charge NUMERIC(15, 2) DEFAULT 0.0,
    dispute_window_days INT DEFAULT 30,
    evidence_json JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. Pricing Rules (Rate Cards) Table
CREATE TABLE IF NOT EXISTS pricing_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    agreement_id UUID NOT NULL REFERENCES rate_agreements(id) ON DELETE CASCADE,
    origin_zone VARCHAR(100) NOT NULL,
    destination_zone VARCHAR(100) NOT NULL,
    service_type VARCHAR(50) DEFAULT 'REGULAR',
    weight_min_kg NUMERIC(10, 2) NOT NULL,
    weight_max_kg NUMERIC(10, 2) NOT NULL,
    base_rate NUMERIC(15, 2) NOT NULL,
    rate_unit VARCHAR(50) DEFAULT 'FLAT_PER_SHIPMENT',
    sla_days INT DEFAULT 2,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_documents_sha256 ON documents(sha256_hash);
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(status);
CREATE INDEX IF NOT EXISTS idx_invoice_line_items_shipment ON invoice_line_items(shipment_id);
CREATE INDEX IF NOT EXISTS idx_surat_jalans_shipment ON surat_jalans(shipment_id);
CREATE INDEX IF NOT EXISTS idx_pods_shipment ON pods(shipment_id);
