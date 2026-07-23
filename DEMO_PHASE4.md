# Phase 4 demo — Harden + Calibrate

~10 minute teammate script. Phases 0–3 must already work (sandbox + Live Scan ✨ + Save appearance).

**Status:** Demo path accepted on device (barcode, enroll→✨, offline, Forget+LAN). Close Red Bull flavors often land in top‑3 rather than top‑1 — expected; confirmation still required.

## Setup

1. PC: `.\start_sandbox.ps1` (port **8000**).
2. Phone + PC same Wi‑Fi.
3. Set `AppConfig.fusionBaseUrl` in `lib/config/config.dart` to `http://<PC-LAN-IP>:8000/`.
4. Hot-restart the app; upload price book Excel.
5. Optional: `python scripts/assert_threshold_parity.py`

## Demo steps

1. **Barcode seed** — Scan a Pepsi/Red Bull barcode → product card → **ADD** (does not enroll).
2. **Save appearance** — Non-seed Excel item, face forward → **Save appearance** → toast shows LAN view count.
3. **Visual match** — Hide barcode → ✨ → same `scan_code` → **ADD**.
4. **Confuser** — Pepsi Diet vs Zero (face only) → expect correct high **or** top-3 picker; never silent wrong ADD without looking.
5. **Offline** — Stop sandbox → banner “Visual match offline” → barcode still works → ✨ shows clear failure snack.
6. **Wrong enroll recover** — Save appearance under wrong product (or enroll then realize mistake) → **Forget appearance** → toast “local + LAN” → Save appearance again on correct face → ✨ recovers.

## Metrics sheet (fill during live matrix)

| Metric | How | Result |
|--------|-----|--------|
| Barcode hit rate | Live | |
| OCR hit rate | Live | |
| Visual top-1 | `python scripts/eval_phase4_fuse.py` + live ✨ | |
| Visual top-3 | same | |
| False accept (high wrong) | live + harness | |
| Fuse latency p50/p95 | harness | |
| % needing manual pick | medium/weak picker path | |

## Acceptance gates

- Seed face top-3 ≥ **90%** on held-out phone crops (top-1 ≥ **70%** after calibration).
- Open-set false high-claim ≤ **5%**.
- Confuser pairs: zero silent high wrong (picker OK).
- Offline: barcode works; ✨ fails clearly.
- Forget clears LAN; re-enroll works.

## Thresholds

Shared file: `countx_live_preview_sandbox/fusion_thresholds.json`  
Flutter mirror: `lib/config/fusion_thresholds.dart`  
After editing both: `python scripts/assert_threshold_parity.py`

## Eval harness

```powershell
python scripts\bootstrap_phase4_manifest.py
# Add phone crops under dataset/phase4_eval/crops/ and update manifest.jsonl
python scripts\eval_phase4_fuse.py --base-url http://127.0.0.1:8000
```
