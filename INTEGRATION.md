# CountX × MobileCLIP Integration

Short status of how the fusion pipeline is wired into Live Scan.  
Sibling pipeline repo: `POC 3 COUNTX Fusion Pipeline` (sandbox on port **8000**).

**Defaults:** MobileCLIP-S2 · Excel `scan_code` identity · no YOLO · user always confirms ADD.

| Phase | Status | Where |
|-------|--------|--------|
| 0 — Registry + sandbox API | Done | Fusion pipeline |
| 1 — LAN bridge in app | Done | This repo |
| 2 — Visual match UX | Done | This repo |
| 3 — Enroll on ADD | Not started | Both |
| 4 — Calibrate / harden | Not started | Both |
| 5 — On-device ONNX | Not started | Both |

---

## How Live Scan works today (Phase 2)

1. **Live Scan (camera)** — traditional path only: **barcode → OCR → Excel**. No CLIP.
2. **Tap ✨** — takes a still, center-crops the bottle frame, calls LAN `/api/fuse`.
3. Result mapped only to rows already in the uploaded price book (`previousStock`).
4. **High** confidence → one suggested product card (`Visual match`).
5. **Medium** (~0.4–0.7, typical phone scores) → **top-3 picker**; user picks.
6. **Low** / no Excel match → toast; no inventing products.
7. User still taps **ADD**. Barcode always wins if it fires while a picker is open.

---

## Phase 0 (fusion pipeline) — done

Built so the app can reason in Excel `scan_code`s:

- `dataset/sku_registry.json` — 12 seed SKUs (`scan_code`, names, refs)
- Gallery embeddings keyed by `scan_code` (not folder Title-Case alone)
- Sandbox seed: `countx_live_preview_sandbox/test_dataset/`
- Scripts: `scripts/seed_phase0_sandbox.py`, `scripts/smoke_phase0_fuse.py`
- API (`countx_live_preview_sandbox/server.py`):
  - `POST /api/fuse` → `scan_code`, `confidence`, `top_k[]`
  - `POST /api/embed_crop`, `POST /api/register_sku` (for Phase 3)

Run sandbox from the pipeline repo:

```bash
python countx_live_preview_sandbox/server.py
```

Phone and PC must be on the same Wi‑Fi.

---

## Phase 1 (this app) — done

LAN proof that the app can talk to MobileCLIP:

| File | Role |
|------|------|
| `lib/config/config.dart` | `fusionBaseUrl` (PC LAN IP, trailing `/`) |
| `lib/services/fusion_api_service.dart` | Dio client: `fuseFrame`, `embedCrop` |
| `lib/models/fusion_result.dart` | Fuse response + `top_k` |
| `lib/utils/fusion_frame_crop.dart` | Center bottle JPEG crop |

Commit: `Add Phase 1 LAN MobileCLIP fusion preview to Live Scan.`

---

## Phase 2 (this app) — done

✨-triggered identify (plan cascade was adjusted: **not** auto-CLIP after OCR miss):

| File | Role |
|------|------|
| `lib/services/product_identification_service.dart` | Fuse + Excel map + confidence bands |
| `lib/models/identification_result.dart` | `IdentificationResult` / `VisualCandidate` / bands |
| `lib/screens/live_scan_screen.dart` | ✨ → identify; top-3 picker; `Visual match` card |

Bands (phone-tuned starters; Phase 4 will recalibrate):

- High: score ≥ 0.70 and margin ≥ 0.08 → single card  
- Medium: score ≥ 0.38 → top-3  
- Low: floor ~0.30 or no in-sheet candidates → no claim  

Commit: `Add Phase 2 visual match via Live Scan sparkle button.`

---

## Setup checklist

1. Start sandbox on PC (`:8000`).
2. Set `AppConfig.fusionBaseUrl` to `http://<PC-LAN-IP>:8000/`.
3. Hot-restart / reinstall the app.
4. Live Scan: barcode/OCR unchanged.
5. Aim product in frame → tap ✨ → pick / ADD.

If sandbox is down, barcode/OCR still work; ✨ shows an error toast.

---

## Explicit non-goals (yet)

- Auto-CLIP while scanning (removed on purpose).
- Auto-add from visual match.
- Classifying all ~11k Excel rows without enrollment.
- Mixing SigLIP embeddings with MobileCLIP.
- YOLO in the live path.
- On-device ONNX (Phase 5).

Known cosmetic: some Excel rows show `(no name)` while the description sits in `code` — price-book field mapping, not fusion.
