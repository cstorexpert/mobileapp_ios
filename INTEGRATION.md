# CountX × MobileCLIP Integration

Short status of how the fusion pipeline is wired into Live Scan.  
Sibling pipeline repo: `POC 3 COUNTX Fusion Pipeline` (sandbox on port **8000**).

**Defaults:** MobileCLIP-S2 · Excel `scan_code` identity · no YOLO · user always confirms ADD.  
**Phase 5 default:** `fusionBaseUrl` empty → on-device visual; LAN is opt-in debug.

| Phase | Status | Where |
|-------|--------|--------|
| 0 — Registry + sandbox API | Done | Fusion pipeline |
| 1 — LAN bridge in app | Done | This repo |
| 2 — Visual match UX | Done | This repo |
| 3 — Save appearance enroll | Done | Both |
| 4 — Calibrate / harden | Done | Both |
| 5 — On-device ONNX | Done | Both |

Demo scripts: [`DEMO_PHASE4.md`](DEMO_PHASE4.md) (LAN) · [`DEMO_PHASE5.md`](DEMO_PHASE5.md) (offline).

---

## How Live Scan works today (Phase 5)

1. **Live Scan (camera)** — **barcode → OCR → Excel**. No CLIP. **ADD** counts only (does not enroll).
2. **Tap ✨** — center-crop → visual identify:
   - **`fusionBaseUrl` empty (default):** on-device MobileCLIP ORT + I2I cosine over **local SQLite gallery**.
   - **`fusionBaseUrl` set:** LAN `POST /api/fuse` (debug fallback; health-check banner if sandbox down).
3. **High** → Visual match card; **Medium / weak (low band ≥ floor)** → top-3 picker; user still taps **ADD**.
4. **Unknown** → **No visual match** + **Save appearance**.
5. **Save appearance** (face-forward only):
   - Tapping **Save appearance** hides the tall product card and opens a **compact capture overlay** so the green framing guide stays visible.
   - **Capture** → in-memory crop preview → user **Confirm** or **Retake** (human-in-the-loop). JPEG is **not** kept on disk after Confirm.
   - On-device: quality gate → ORT embed → **SQLite embedding only**.
   - LAN mode: also `embedCrop` + `register_sku` when URL set (JPEG sent in memory).
6. **Barcode** never enrolls by itself. Cap ~10 views/code (overlay shows count only; hard stop at cap); **Forget appearance** clears local embeddings (+ LAN when URL set). Legacy `product_crops/` folders are purged.

### Visual gallery vs Excel (important)

| | Excel price book | Visual gallery |
|--|------------------|----------------|
| Role | Identity / name / price | Pack-face fingerprints for ✨ |
| Size | Full uploaded sheet | Only **Save appearance** (phone) and/or sandbox seeds (LAN) |
| ✨ searches? | No — only maps winners | Yes — nearest neighbors |

Offline ✨ can only suggest products you previously **Save appearance**’d on this phone (or that still exist in SQLite). It does **not** search all Excel rows. Unenrolled faces either hit **unknown** or (if scores clear the weak floor) look like the nearest enrolled / seed faces — not hardcoded brands.

### Visual mode switch

| Config | Behavior |
|--------|----------|
| `fusionBaseUrl = ""` | On-device ORT + SQLite I2I |
| `fusionBaseUrl = "http://<PC-IP>:8000/"` | LAN fuse (debug) |
| `mobileClipModelBaseUrl` | HTTP base for download-on-first-run (`…/models/`) |

---

## Phase 5 — On-device MobileCLIP (done)

### What changed in this app

| File | Role |
|------|------|
| `lib/config/config.dart` | Empty `fusionBaseUrl` by default; `mobileClipModelBaseUrl` for model HTTP |
| `lib/services/mobileclip_model_store.dart` | Download/cache `mobileclip_visual.onnx` + `.onnx.data` (~147 MB) into documents `mobileclip/` |
| `lib/utils/mobileclip_preprocess.dart` | 256 bicubic + CLIP mean/std (sandbox parity) |
| `lib/services/mobileclip_onnx_service.dart` | `flutter_onnxruntime` file session → L2 512-d |
| `lib/services/local_gallery_search.dart` | Max cosine over SQLite views (I2I-only; no T2I) |
| `lib/services/product_identification_service.dart` | On-device branch when URL empty; Excel display-name fallback |
| `lib/services/product_enrollment_service.dart` | On-device embed when LAN unavailable; offline success toast |
| `lib/services/product_embedding_repository.dart` | `listAllViews()` for offline search |
| `lib/screens/live_scan_screen.dart` | Model missing/download banner; on-device ✨; product title fallback |
| `pubspec.yaml` | `flutter_onnxruntime` |
| `ios/Podfile` | iOS 16 + static linkage (ORT) |
| `android/app/proguard-rules.pro` | Keep `ai.onnxruntime.**` |
| `test/mobileclip_preprocess_parity_test.dart` | Dart vs Python preprocess cosine ≥ 0.99 |
| `test/local_gallery_search_test.dart` | Cosine unit checks |
| `DEMO_PHASE5.md` | Offline demo script |

### Sibling pipeline (not this git repo)

| File | Role |
|------|------|
| `countx_live_preview_sandbox/server.py` | Serves `/models/` for first-run download |
| `scripts/export_phase5_parity_fixture.py` / `assert_phase5_parity.py` | Python ORT cosine ≥ 0.99 |
| `dataset/phase5_parity/` | Fixture JPEG + expected tensor/embedding |

### Locked Phase 5 decisions

- **Model delivery:** download-on-first-run (not bundled in APK); USB/`adb` documented as fallback.
- **Offline scoring:** I2I-only over SQLite (no on-device text encoder).
- **Mode switch:** empty URL → on-device; non-empty → LAN debug.
- **Bands:** reuse Phase 4 shared thresholds; tweak JSON+Dart together if phone I2I drifts.

### Model install (first run)

1. Start sandbox (`:8000`) so `/models/mobileclip_visual.onnx(.data)` is reachable, **or**
2. USB / `adb push` both files into the app documents folder `mobileclip/` (same filenames).
3. In Live Scan, if the teal banner says model missing → **Download** (~147 MB once). After that, airplane mode / stopped sandbox still works for ✨.

Expected sizes: graph ~3.26 MB, weights ~137.4 MB.

**Full restart required** after changing `fusionBaseUrl` / `mobileClipModelBaseUrl` (hot reload does not rebuild `const` config).

---

## Phase 0–4 (done)

See git history / [`DEMO_PHASE4.md`](DEMO_PHASE4.md). Shared thresholds: `fusion_thresholds.json` ↔ `fusion_thresholds.dart` (`lib/config/fusion_thresholds.dart`).

Bands: High ≥0.70+margin; Medium ≥0.38; weak picker ≥0.30; else unknown.

---

## Setup checklist

**On-device (default)**

1. `AppConfig.fusionBaseUrl = ""`.
2. `AppConfig.mobileClipModelBaseUrl` = `http://<PC-LAN-IP>:8000/models/` (or empty + USB/`adb`).
3. Start sandbox if downloading over Wi‑Fi.
4. Full restart app → Download model once → Save appearance → stop sandbox / airplane → ✨.

**LAN debug**

1. Start sandbox (`.\start_sandbox.ps1` or venv `server.py`).
2. Set `fusionBaseUrl` to `http://<PC-LAN-IP>:8000/`.
3. Full restart; ✨ uses `/api/fuse` (scores may differ from on-device I2I — compare rank/band, not raw equality).

---

## Explicit non-goals (yet)

- Auto-CLIP while scanning.
- Auto-add from visual match.
- Auto-enroll on ADD or barcode lock.
- Classifying all ~11k Excel rows without enrollment.
- Mixing SigLIP with MobileCLIP.
- YOLO in the live path.
- Bundling 147 MB into the APK/IPA (download / USB instead).
- On-device text encoder / T2I blend (I2I-only offline).

Display: some Excel rows leave Item Description empty and put the label in Item Code — Live Scan / ✨ fall back to `code` before showing the barcode.
