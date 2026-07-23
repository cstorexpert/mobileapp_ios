# CountX × MobileCLIP Integration

Short status of how the fusion pipeline is wired into Live Scan.  
Sibling pipeline repo: `POC 3 COUNTX Fusion Pipeline` (sandbox on port **8000**).

**Defaults:** MobileCLIP-S2 · Excel `scan_code` identity · no YOLO · user always confirms ADD.

| Phase | Status | Where |
|-------|--------|--------|
| 0 — Registry + sandbox API | Done | Fusion pipeline |
| 1 — LAN bridge in app | Done | This repo |
| 2 — Visual match UX | Done | This repo |
| 3 — Save appearance enroll | Done | Both |
| 4 — Calibrate / harden | Done | Both |
| 5 — On-device ONNX | Not started | Both |

---

## How Live Scan works today (Phase 4)

1. **Live Scan (camera)** — **barcode → OCR → Excel**. No CLIP. **ADD** counts only (does not enroll).
2. **Tap ✨** — health-check → center-crop → LAN `/api/fuse`. Offline banner if sandbox down; barcode/OCR keep working.
3. **High** → Visual match card; **Medium / weak (low band ≥ floor)** → top-3 picker; user still taps **ADD**.
4. **Unknown** (no Excel-mapped candidates or score below floor) → **No visual match** + **Save appearance**.
5. **Save appearance** (face-forward only):
   - On locked Excel card: capture crop now → local + LAN enroll under `scan_code`.
   - From ✨ unknown / **None of these**: keep face crop → scan barcode to link → enroll.
   - Toast reports LAN view count or a clear LAN-failure warning (✨ needs the sandbox gallery).
6. **Barcode** never enrolls by itself (barcode side ≠ pack face).
7. Cap ~5 views / code; blurry/tiny crops skipped; **Forget appearance** clears **local + LAN** gallery for that code.

---

## Phase 0 (fusion pipeline) — done

- `dataset/sku_registry.json` — 12 seed SKUs
- Sandbox seed + `POST /api/fuse` (`scan_code`, `top_k`, `resolution_status`: `unknown` | `needs_review` | `auto-accepted`)
- `POST /api/embed_crop`, `POST /api/register_sku` (`append=true` for multi-view)

Run sandbox from the pipeline repo (preferred — strips conda PATH conflicts):

```powershell
.\start_sandbox.ps1
```

Or manually with the venv python (avoid `conda activate`):

```powershell
.\venv\Scripts\python.exe countx_live_preview_sandbox\server.py
```

Phone and PC must be on the same Wi‑Fi.

---

## Phase 1 (this app) — done

| File | Role |
|------|------|
| `lib/config/config.dart` | `fusionBaseUrl` |
| `lib/services/fusion_api_service.dart` | `fuseFrame`, `embedCrop`, `registerSku`, `forgetSku`, `healthCheck` |
| `lib/models/fusion_result.dart` | Fuse response |
| `lib/utils/fusion_frame_crop.dart` | Center bottle JPEG crop |

---

## Phase 2 (this app) — done

✨-only identify (not auto-CLIP after OCR miss):

| File | Role |
|------|------|
| `lib/services/product_identification_service.dart` | Fuse + bands + open-set unknown |
| `lib/models/identification_result.dart` | Result models |
| `lib/screens/live_scan_screen.dart` | ✨ UX |

Bands (shared with sandbox JSON): High ≥0.70+margin; Medium ≥0.38; weak picker ≥0.30; else unknown.

---

## Phase 3 (this app + sandbox) — done

| File | Role |
|------|------|
| `lib/services/product_embedding_repository.dart` | Local `sqflite` gallery |
| `lib/services/product_enrollment_service.dart` | Quality gate → local + LAN |
| `lib/utils/crop_quality.dart` | Blur / size gate |
| `lib/screens/live_scan_screen.dart` | Save appearance; barcode-link; Forget |
| `countx_live_preview_sandbox/server.py` | Fuse `unknown`; register append |

---

## Phase 4 (this app + sandbox) — done

| File | Role |
|------|------|
| `countx_live_preview_sandbox/fusion_thresholds.json` | Shared thresholds |
| `lib/config/fusion_thresholds.dart` | Flutter mirror |
| `scripts/assert_threshold_parity.py` | JSON ↔ Dart check |
| `scripts/eval_phase4_fuse.py` | HTTP fuse metrics |
| `dataset/phase4_eval/` | Manifest + crop corpus |
| `POST /api/forget_sku` | LAN gallery wipe per `scan_code` |
| `DEMO_PHASE4.md` | Teammate demo + metrics sheet |

**Demo:** see [`DEMO_PHASE4.md`](DEMO_PHASE4.md). Live checks 1–5 (barcode, Save appearance → ✨, confusers, offline, Forget+re-enroll) accepted; similar Red Bull flavors may need the top‑3 picker.

---

## Setup checklist

1. Start sandbox (`:8000`).
2. Set `AppConfig.fusionBaseUrl` to `http://<PC-LAN-IP>:8000/`.
3. Hot-restart app.
4. Barcode/OCR unchanged; ✨ for visual; Save appearance for enroll.
5. After threshold edits: `python scripts/assert_threshold_parity.py`.

---

## Explicit non-goals (yet)

- Auto-CLIP while scanning.
- Auto-add from visual match.
- Auto-enroll on ADD or barcode lock.
- Classifying all ~11k Excel rows without enrollment.
- Mixing SigLIP with MobileCLIP.
- YOLO in the live path.
- On-device ONNX (Phase 5).

Known cosmetic: some Excel rows show `(no name)` while the description sits in `code`.
