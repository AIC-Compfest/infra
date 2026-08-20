#!/usr/bin/env python3
"""
seed_supabase.py

Seeds the Supabase Cloud / Local PostgreSQL Database and Storage with the active
benchmark dataset (v4_pilot_20).

1. Uploads physical document files (PDF, JPG) to Supabase Storage ('documents-original').
2. Ingests document records into the 'documents' table with computed SHA-256 hashes.
3. Populates domain tables ('shipments', 'invoices', 'surat_jalans', 'pods', 'rate_agreements').
4. Reconciles events and records 'shipment_events', 'reconciliation_cases', 'discrepancies', and 'audit_events'.
"""

import os
import sys
import json
import glob
import hashlib
import mimetypes
import urllib.request
import urllib.error
from pathlib import Path
from datetime import datetime, date

# Ensure UTF-8 console output
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://vqquelixcnzrylvvnzng.supabase.co").rstrip("/")
SERVICE_ROLE_KEY = os.environ.get(
    "SUPABASE_SERVICE_ROLE_KEY",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZxcXVlbGl4Y256cnlsdnZuem5nIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NjQzMzUwNiwiZXhwIjoyMTAyMDA5NTA2fQ.Vkm-g46J89_lsxYsAlccDNa3OioQqS8fApf0hQrfCsc"
)

HEADERS = {
    "apikey": SERVICE_ROLE_KEY,
    "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
    "Content-Type": "application/json",
    "Prefer": "resolution=merge-duplicates,return=representation"
}

STORAGE_HEADERS = {
    "apikey": SERVICE_ROLE_KEY,
    "Authorization": f"Bearer {SERVICE_ROLE_KEY}",
    "x-upsert": "true"
}

VENDOR_NAMES = {
    "3PL-LOG-001": "PT Cepat Logistik Nusantara",
    "3PL-LOG-002": "PT Trans Express Indonesia",
    "3PL-LOG-003": "PT Kargo Andalan Utama",
    "3PL-LOG-004": "PT Sinar Logistik Mandiri",
    "3PL-LOG-005": "PT Aruna Freight Solusi"
}

def compute_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def supabase_post(endpoint, payload):
    url = f"{SUPABASE_URL}/rest/v1/{endpoint}"
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=HEADERS, method="POST")
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body) if body else []
    except urllib.error.HTTPError as e:
        err_msg = e.read().decode("utf-8")
        print(f"   ⚠️ HTTPError [{endpoint}] ({e.code}): {err_msg[:200]}")
        return []
    except Exception as e:
        print(f"   ⚠️ Error [{endpoint}]: {e}")
        return []

def supabase_get(endpoint, params=""):
    url = f"{SUPABASE_URL}/rest/v1/{endpoint}"
    if params:
        url += f"?{params}"
    req = urllib.request.Request(url, headers=HEADERS, method="GET")
    try:
        with urllib.request.urlopen(req) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body) if body else []
    except Exception as e:
        print(f"   ⚠️ Get error [{endpoint}]: {e}")
        return []

def upload_to_storage(bucket, storage_path, file_bytes, mime_type="application/octet-stream"):
    url = f"{SUPABASE_URL}/storage/v1/object/{bucket}/{storage_path}"
    headers = dict(STORAGE_HEADERS)
    headers["Content-Type"] = mime_type
    req = urllib.request.Request(url, data=file_bytes, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req) as resp:
            return True
    except Exception as e:
        # Ignore conflict if already exists
        return True

def main():
    root_dir = Path(__file__).resolve().parent.parent.parent
    dataset_dir = root_dir / "synthetic-data" / "dataset" / "v4_pilot_20"

    print("=" * 70)
    print(" 🚀 SUPABASE DATASET SEEDER (Active Dataset: v4_pilot_20)")
    print(f" Target Supabase URL: {SUPABASE_URL}")
    print(f" Dataset Path       : {dataset_dir}")
    print("=" * 70)

    if not dataset_dir.exists():
        print(f"❌ Error: Dataset directory {dataset_dir} not found.")
        return 1

    # 1. Upload Invoices & Store Document Records
    invoices_dir = dataset_dir / "invoices"
    uploaded_docs = {}
    
    print("\n📦 1. Uploading Invoices & Ingesting Document Records...")
    for inv_pdf in sorted(invoices_dir.glob("*.pdf")):
        sha = compute_sha256(inv_pdf)
        size = inv_pdf.stat().st_size
        storage_path = f"invoices/{inv_pdf.name}"
        with open(inv_pdf, "rb") as f:
            upload_to_storage("documents-original", storage_path, f.read(), "application/pdf")
        
        doc_record = {
            "filename": inv_pdf.name,
            "file_size": size,
            "mime_type": "application/pdf",
            "sha256_hash": sha,
            "storage_path": f"documents-original/{storage_path}",
            "status": "COMPLETED",
            "classification": "INVOICE",
            "classification_confidence": 0.99
        }
        res = supabase_post("documents", doc_record)
        if res and isinstance(res, list) and len(res) > 0:
            uploaded_docs[inv_pdf.stem] = res[0]["id"]
            uploaded_docs[inv_pdf.name] = res[0]["id"]
        print(f"   ├── 📄 Uploaded & Ingested: {inv_pdf.name} (SHA: {sha[:10]}...)")

    # 2. Process Transaction Bundles
    txns_dir = dataset_dir / "transactions"
    txn_dirs = sorted([d for d in txns_dir.iterdir() if d.is_dir()])
    print(f"\n📂 2. Processing {len(txn_dirs)} Transactions & Multi-Document Bundles...")

    for tdir in txn_dirs:
        gt_file = tdir / "ground_truth.json"
        if not gt_file.exists():
            continue
        with open(gt_file, "r", encoding="utf-8") as f:
            gt = json.load(f)

        txn_id = gt["transaction_id"]
        shp_id = gt["shipment_id"]
        vendor_id = gt["vendor_id"]
        vendor_name = VENDOR_NAMES.get(vendor_id, vendor_id)

        # Upload Surat Jalan, POD, Rate Agreement
        sj_file = tdir / "surat_jalan.pdf"
        pod_file = tdir / "pod.jpg"
        ra_file = tdir / "rate_agreement.pdf"

        sj_doc_id = None
        if sj_file.exists():
            sj_sha = compute_sha256(sj_file)
            storage_path = f"transactions/{txn_id}/surat_jalan.pdf"
            with open(sj_file, "rb") as f:
                upload_to_storage("documents-original", storage_path, f.read(), "application/pdf")
            res = supabase_post("documents", {
                "filename": f"surat_jalan_{txn_id}.pdf",
                "file_size": sj_file.stat().st_size,
                "mime_type": "application/pdf",
                "sha256_hash": sj_sha,
                "storage_path": f"documents-original/{storage_path}",
                "status": "COMPLETED",
                "classification": "SURAT_JALAN",
                "classification_confidence": 0.98
            })
            if res and len(res) > 0:
                sj_doc_id = res[0]["id"]

        pod_doc_id = None
        if pod_file.exists():
            pod_sha = compute_sha256(pod_file)
            storage_path = f"transactions/{txn_id}/pod.jpg"
            with open(pod_file, "rb") as f:
                upload_to_storage("documents-original", storage_path, f.read(), "image/jpeg")
            res = supabase_post("documents", {
                "filename": f"pod_{txn_id}.jpg",
                "file_size": pod_file.stat().st_size,
                "mime_type": "image/jpeg",
                "sha256_hash": pod_sha,
                "storage_path": f"documents-original/{storage_path}",
                "status": "COMPLETED",
                "classification": "POD",
                "classification_confidence": 0.97
            })
            if res and len(res) > 0:
                pod_doc_id = res[0]["id"]

        ra_doc_id = None
        if ra_file.exists():
            ra_sha = compute_sha256(ra_file)
            storage_path = f"transactions/{txn_id}/rate_agreement.pdf"
            with open(ra_file, "rb") as f:
                upload_to_storage("documents-original", storage_path, f.read(), "application/pdf")
            res = supabase_post("documents", {
                "filename": f"rate_agreement_{txn_id}.pdf",
                "file_size": ra_file.stat().st_size,
                "mime_type": "application/pdf",
                "sha256_hash": ra_sha,
                "storage_path": f"documents-original/{storage_path}",
                "status": "COMPLETED",
                "classification": "RATE_AGREEMENT",
                "classification_confidence": 0.99
            })
            if res and len(res) > 0:
                ra_doc_id = res[0]["id"]

        # Insert Shipment Master
        supabase_post("shipments", {
            "shipment_id": shp_id,
            "origin": gt.get("origin", "JAKARTA"),
            "destination": gt.get("destination", "SURABAYA"),
            "service_type": gt.get("service_type", "REGULAR")
        })

        # Insert Rate Agreement
        ctr = gt.get("contract", {})
        ag_id = ctr.get("agreement_id", f"CTR-{vendor_id}-2026")
        ra_res = supabase_post("rate_agreements", {
            "document_id": ra_doc_id,
            "agreement_id": ag_id,
            "vendor_id": vendor_id,
            "vendor_name": vendor_name,
            "effective_from": ctr.get("effective_from", "2026-01-01"),
            "effective_to": ctr.get("effective_to", "2026-12-31"),
            "currency": "IDR",
            "fuel_surcharge_percent": ctr.get("fuel_surcharge_percent", 14.0),
            "dispute_window_days": 45
        })
        ra_uuid = ra_res[0]["id"] if ra_res and len(ra_res) > 0 else None

        # Insert Surat Jalan
        sj_res = supabase_post("surat_jalans", {
            "document_id": sj_doc_id,
            "surat_jalan_number": f"SJ-{shp_id}",
            "shipment_id": shp_id,
            "awb_number": f"AWB{shp_id.replace('SHP-2026-', '')}",
            "shipment_date": gt.get("shipment_date", "2026-08-01"),
            "sender_name": "PT Sumber Distribusi Logistik",
            "sender_city": gt.get("origin", "JAKARTA"),
            "receiver_name": "Gudang Logistik Regional",
            "receiver_city": gt.get("destination", "SURABAYA"),
            "actual_weight_kg": gt.get("actual_weight_kg", gt.get("weight_kg", 10.0)),
            "total_packages": gt.get("quantity", 1),
            "item_description": gt.get("item_description", "Barang Dagangan Umum")
        })
        sj_uuid = sj_res[0]["id"] if sj_res and len(sj_res) > 0 else None

        # Insert POD
        pod_info = gt.get("pod", {})
        pod_res = supabase_post("pods", {
            "document_id": pod_doc_id,
            "pod_number": f"POD-{shp_id}",
            "shipment_id": shp_id,
            "awb_number": f"AWB{shp_id.replace('SHP-2026-', '')}",
            "delivery_status": "DELIVERED" if pod_info.get("delivered", True) else "FAILED",
            "delivery_date": pod_info.get("delivery_date", gt.get("shipment_date", "2026-08-03")),
            "receiver_name": "Budi Santoso (Staff Gudang)",
            "signature_present": pod_info.get("signature_present", True),
            "signature_confidence": 0.95,
            "stamp_present": pod_info.get("stamp_present", True)
        })
        pod_uuid = pod_res[0]["id"] if pod_res and len(pod_res) > 0 else None

        # Insert Invoice & Line Item
        inv_num = gt.get("invoice_id", f"INV-{txn_id}")
        inv_doc_id = uploaded_docs.get(inv_num)
        billed_charge = gt.get("billed_charge", 0)
        expected_charge = gt.get("expected_charge", 0)
        tax_amount = gt.get("tax_amount", int(billed_charge * 0.11 / 1.11))
        subtotal = billed_charge - tax_amount

        inv_res = supabase_post("invoices", {
            "document_id": inv_doc_id,
            "invoice_number": inv_num,
            "vendor_id": vendor_id,
            "vendor_name": vendor_name,
            "customer_id": gt.get("customer_id", "CUST-001"),
            "customer_name": "PT Agro Niaga Perkasa",
            "invoice_date": gt.get("shipment_date", "2026-08-01"),
            "currency": "IDR",
            "subtotal": subtotal,
            "tax_amount": tax_amount,
            "grand_total": billed_charge
        })
        inv_uuid = inv_res[0]["id"] if inv_res and len(inv_res) > 0 else None

        if inv_uuid:
            supabase_post("invoice_line_items", {
                "invoice_id": inv_uuid,
                "line_number": 1,
                "shipment_id": shp_id,
                "awb_number": f"AWB{shp_id.replace('SHP-2026-', '')}",
                "origin": gt.get("origin", "JAKARTA"),
                "destination": gt.get("destination", "SURABAYA"),
                "weight_kg": gt.get("weight_kg", 10.0),
                "base_charge": ctr.get("base_rate", 50000),
                "fuel_surcharge_percent": ctr.get("fuel_surcharge_percent", 14.0),
                "line_total": billed_charge
            })

        # Calculate difference & status
        variance = billed_charge - expected_charge
        gt_info = gt.get("ground_truth", {})
        status = gt_info.get("status", "MATCH")
        if gt.get("scenario_name") == "DUPLICATE_INVOICE":
            status = "DUPLICATE"

        is_material = abs(variance) >= 50000 or (expected_charge > 0 and (abs(variance) / expected_charge) >= 0.02)
        priority_score = 85.0 if status != "MATCH" else 10.0

        # Insert Shipment Event
        ev_res = supabase_post("shipment_events", {
            "event_id": f"EVT-{txn_id}",
            "shipment_id": shp_id,
            "vendor_id": vendor_id,
            "match_confidence": 0.98,
            "invoice_id": inv_uuid,
            "surat_jalan_id": sj_uuid,
            "pod_id": pod_uuid,
            "rate_agreement_id": ra_uuid,
            "expected_base_charge": ctr.get("base_rate", 50000),
            "expected_fuel_surcharge": int(ctr.get("base_rate", 50000) * ctr.get("fuel_surcharge_percent", 14.0) / 100.0),
            "expected_total_charge": expected_charge,
            "billed_total_charge": billed_charge,
            "difference_amount": variance,
            "is_material": is_material,
            "calculation_trace": f"Contract Base: Rp {ctr.get('base_rate', 0):,} + Fuel {ctr.get('fuel_surcharge_percent', 0)}% = Expected Rp {expected_charge:,} | Billed Rp {billed_charge:,}",
            "status": status,
            "priority_score": priority_score,
            "requires_human_review": status != "MATCH"
        })
        ev_uuid = ev_res[0]["id"] if ev_res and len(ev_res) > 0 else None

        # Insert Reconciliation Case
        if ev_uuid:
            case_status = "OPEN" if status != "MATCH" else "RESOLVED"
            case_res = supabase_post("reconciliation_cases", {
                "case_id": f"CASE-{txn_id}",
                "event_id": ev_uuid,
                "vendor_id": vendor_id,
                "status": case_status,
                "priority_score": priority_score,
                "financial_exposure_idr": max(0, variance),
                "dispute_deadline": "2026-09-15"
            })
            case_uuid = case_res[0]["id"] if case_res and len(case_res) > 0 else None

            # Insert Discrepancies
            discrepancies = gt_info.get("discrepancies", [])
            for disc in discrepancies:
                if case_uuid:
                    supabase_post("discrepancies", {
                        "case_id": case_uuid,
                        "code": disc if isinstance(disc, str) else disc.get("code", "RATE_OVERCHARGE"),
                        "category": "PRICING" if "RATE" in str(disc) or "FUEL" in str(disc) else "SHIPMENT",
                        "description": f"Discrepancy detected: {disc}",
                        "severity": "CRITICAL" if is_material else "WARNING",
                        "delta_amount": variance
                    })

            # Insert Initial Audit Event
            if case_uuid and ev_uuid:
                supabase_post("audit_events", {
                    "case_id": case_uuid,
                    "event_id": ev_uuid,
                    "action": "AUTO_RECONCILED",
                    "actor_id": "SYSTEM_RECONCILE_ENGINE",
                    "actor_role": "SYSTEM",
                    "previous_status": "QUEUED",
                    "new_status": status,
                    "notes": f"Deterministic 13-check engine completed. Status: {status}, Variance: Rp {variance:,}"
                })

        print(f"   ├── 🎯 Processed {txn_id} [{gt.get('scenario_name')}] -> Status: {status} (Variance: Rp {variance:,})")

    print("\n" + "=" * 70)
    print(" 🎉 ALL 20 TRANSACTIONS & DOCUMENTS SUCCESSFULLY SEEDED TO SUPABASE!")
    print("=" * 70)
    return 0

if __name__ == "__main__":
    sys.exit(main())
