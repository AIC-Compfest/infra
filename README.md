# @aic/infra

**Pusat Infrastruktur, Migrasi Database, Kebijakan Bisnis Terpusat & Orkestrasi Docker Compose** untuk **Evidence-First AI 3PL Invoice Reconciliation Engine** (COMPFEST 18 AI Innovation Challenge — Smart Logistics).

---

## 📌 Tanggung Jawab Modul `infra`

Repositori `infra` bertindak sebagai **Single Source of Truth** untuk:
1. **Kebijakan Bisnis Terpusat (`configs/`):** Ambang batas pencocokan otomatis (*auto-match threshold* 0.95), batas toleransi selisih biaya (*materiality threshold* Rp50.000 / 2%), serta aturan peringatan tenggat waktu sanggahan (*dispute window alert*).
2. **Migrasi Database PostgreSQL / Supabase (`migrations/`):** Seluruh skema DDL relasional untuk data persepsi dokumen, entity resolution, kalkulasi harga deterministik, dan log audit tidak dapat diubah (*append-only*).
3. **Keamanan & Tata Kelola Penyimpanan (*Storage Governance*):** Pengaturan bucket penyimpanan file asli dan trigger database yang menjamin catatan audit tidak dapat dimanipulasi (*tamper-proof immutability*).
4. **Orkestrasi Multi-Service Lokal (`docker-compose.yml`):** Menjalankan seluruh sistem (4 kontainer) dengan satu perintah terpadu.

---

## 🌐 Pemetaan Port & Layanan (*Service Architecture*)

| Service | Teknologi | Port Host | Endpoint / Pengecekan Kesehatan | Tanggung Jawab Utama |
|---|---|---|---|---|
| **`frontend`** | Next.js 15 / React / Tailwind CSS | `3000` | `GET /api/health` | Workspace Reviewer & penampil kotak bukti visual (*Bounding Box*). |
| **`backend-api`** | Go / Gin / REST | `8080` | `GET /healthz` & `GET /readyz` | API Gateway, alur kerja bisnis, kalkulasi harga deterministik, & resolusi entitas. |
| **`ai-service`** | Python / FastAPI / PP-OCRv6 | `8100` | `GET /healthz` | Layanan AI Stateless: Klasifikasi, Preprocessing OpenCV, OCR, & Deteksi Tanda Tangan. |
| **`postgres`** | PostgreSQL 16 Alpine | `5432` | `pg_isready` | Database relasional untuk menyimpan state transaksi dan audit trail. |

---

## 🚀 Panduan Menjalankan Sistem Lokal (Docker Compose)

### 1. Salin Pengaturan Lingkungan (*Environment*)
```bash
cp .env.example .env
```

### 2. Jalankan Seluruh Kontainer
```bash
docker compose up --build
```
Semua 4 layanan akan menyala secara otomatis sesuai urutan dependensi dengan pengecekan kesehatan (*healthcheck*) berkala.

### 3. Uji Kesehatan Layanan (*Healthcheck Validator*)
Jalankan skrip penguji kesiapan endpoint:
```bash
python scripts/check_health.py
```

---

## 🗄️ Skema Migrasi Database (`migrations/`)

Seluruh berkas migrasi SQL dieksekusi secara otomatis saat inisialisasi awal kontainer PostgreSQL melalui direktori `/docker-entrypoint-initdb.d/` atau dapat dijalankan langsung di SQL Editor Supabase:

| Berkas Migrasi | Deskripsi & Isi Tabel |
|---|---|
| [`001_initial_schema.sql`](migrations/001_initial_schema.sql) | **Tabel Entitas Master:** `documents`, `document_pages`, `document_extractions`, `shipments`, `invoices`, `invoice_line_items`, `surat_jalans`, `pods`, `rate_agreements`, `pricing_rules`. |
| [`002_reconciliation_schema.sql`](migrations/002_reconciliation_schema.sql) | **Tabel Rekonsiliasi & Audit:** `shipment_events`, `reconciliation_cases`, `discrepancies`, `review_decisions`, `audit_events`. |
| [`003_storage_and_rls.sql`](migrations/003_storage_and_rls.sql) | **Tata Kelola Penyimpanan & Immutability:** Registrasi 3 bucket storage (`documents-original`, `documents-preprocessed`, `dispute-packages`) serta **Database Trigger yang menjamin tabel `audit_events` bersifat mutlak APPEND-ONLY** (melarang operasi `UPDATE` dan `DELETE`). |

---

## ⚙️ Kebijakan Bisnis Terpusat (`configs/`)

* **[`configs/thresholds.yaml`](configs/thresholds.yaml):** Menentukan ambang batas minimum pencocokan otomatis ($\ge 0.95$), toleransi selisih uang ($\ge \text{Rp}50.000$ atau $\ge 2\%$), dan peringatan sisa waktu sengketa ($\le 7\text{ hari}$).
* **[`configs/pricing.yaml`](configs/pricing.yaml):** Aturan dasar perhitungan tarif, metode pembulatan (*Round Half Up*), dan perpajakan (PPN 0% B2B logistik).
* **[`configs/document_types.yaml`](configs/document_types.yaml):** Batas ukuran dokumen maksimal 25 MB dan daftar ekstensi file yang diizinkan (`.pdf`, `.jpg`, `.jpeg`, `.png`, `.heic`).
