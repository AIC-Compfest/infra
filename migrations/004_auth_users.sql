-- Migration: 004_auth_users.sql
-- Description: Creates users authentication & RBAC table for Supabase
-- Reference: PRD_MVP.md §36, §37

-- Enable UUID extension if not exists
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Users Table
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL,
    company_name VARCHAR(255) DEFAULT 'PT Enterprise Logistik',
    role VARCHAR(50) NOT NULL DEFAULT 'AP_MANAGER' CHECK (role IN ('AP_MANAGER', 'FINANCE_CONTROLLER', 'LOGISTICS_MANAGER', 'AUDITOR', 'ADMIN')),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Indexes for High-Performance Lookups
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);

-- 3. Automatic updated_at Trigger
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_users_updated_at ON public.users;
CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- 4. Seed Default Enterprise Accounts (Password: password123)
-- Genuine Bcrypt hash of 'password123': $2a$10$WYvdx.trijZe4MmXMmOJEO.qgO9.7SQvmh0b/716luqL1mjuGctse
INSERT INTO public.users (id, email, password_hash, name, company_name, role, is_active)
VALUES 
    ('a0000001-0000-0000-0000-000000000001', 'ap.manager@enterprise.com', '$2a$10$WYvdx.trijZe4MmXMmOJEO.qgO9.7SQvmh0b/716luqL1mjuGctse', 'Rian AP Manager', 'PT Global Freight Nusantara', 'AP_MANAGER', TRUE),
    ('a0000002-0000-0000-0000-000000000002', 'controller@enterprise.com', '$2a$10$WYvdx.trijZe4MmXMmOJEO.qgO9.7SQvmh0b/716luqL1mjuGctse', 'Siti Finance Controller', 'PT Global Freight Nusantara', 'FINANCE_CONTROLLER', TRUE),
    ('a0000003-0000-0000-0000-000000000003', 'logistics@enterprise.com', '$2a$10$WYvdx.trijZe4MmXMmOJEO.qgO9.7SQvmh0b/716luqL1mjuGctse', 'Budi Logistics Ops', 'PT Global Freight Nusantara', 'LOGISTICS_MANAGER', TRUE)
ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash, is_active = TRUE;
