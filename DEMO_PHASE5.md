# Phase 5 demo — On-device MobileCLIP

Teammate script for offline visual match after Phases 0–4.

## Preconditions

- Price book Excel uploaded in the app (so ✨ can map to rows).
- [`lib/config/config.dart`](lib/config/config.dart):
  - `fusionBaseUrl = ""` (on-device)
  - `mobileClipModelBaseUrl = "http://<PC-IP>:8000/models/"` **or** plan USB/`adb` push
- MobileCLIP files exist on the PC under `dataset/mobileclip_visual.onnx` + `.onnx.data` (~147 MB).

## Check 1 — Model install

1. Start sandbox on PC (`.\start_sandbox.ps1`) so `/models/` is served.
2. Open Live Scan. Teal banner: **Visual model not installed**.
3. Tap **Download**. Wait for ~147 MB (progress bar).
4. Snack: **Visual model ready**. Banner clears.
5. Barcode/OCR still work during download.

**USB fallback:** push both ONNX files into the app documents `mobileclip/` folder (same filenames). Then Retry / reopen Live Scan.

## Check 2 — Offline Save appearance → ✨

1. Enable airplane mode (or leave Wi‑Fi on; URL is empty so LAN is unused).
2. Lock a product via **barcode**.
3. Hold pack face in frame → **Save appearance** → toast **Saved appearance on phone**.
4. Clear lock / hide barcode → tap **✨**.
5. Expect high card or top‑3 picker with the same Excel row.

## Check 3 — Unenrolled pack

1. Point at a face that was never Save-appearance’d.
2. ✨ → **No visual match** + Save appearance (not a forced seed SKU).

## Check 4 — Forget + re-enroll

1. Lock enrolled product → **Forget appearance** → local cleared.
2. ✨ should miss → Save appearance again → ✨ hits again.

## Check 5 — LAN debug still works

1. Set `fusionBaseUrl` to `http://<PC-IP>:8000/`, hot-restart.
2. With sandbox up, ✨ uses LAN fuse (orange offline banner if sandbox down).
3. Scores may differ slightly from on-device I2I (LAN blends T2I); compare **rank / band / top‑3**, not raw equality.

## Parity gate (dev)

```powershell
# From pipeline repo root
.\venv\Scripts\python.exe scripts\assert_phase5_parity.py

cd mobileapp_ios
flutter test test/mobileclip_preprocess_parity_test.dart
```

Both must report cosine ≥ 0.99 vs the Phase 5 fixture.

## Known OK

- Similar SKUs (e.g. Red Bull flavors) may need the top‑3 picker — same as Phase 4.
- First ORT session load can take a few seconds after download.
