class AppConfig {
  //static const String baseUrl = "http://192.168.0.103:4000/api/"; // Local PC backend (LAN)
  //static const String baseUrl = "http://192.168.0.207:4000/api/"; // Replace with your Keycloak base URL
  //static const String baseUrl = "http://172.17.176.1:4000/api/"; // Replace with your Keycloak base URL
  static const String baseUrl = "https://cstorexpert-backend.onrender.com/api/";

  /// CountX MobileCLIP sandbox (LAN debug fallback).
  /// Empty → Phase 5 on-device visual path. Non-empty → POST /api/fuse over Wi‑Fi.
  /// Trailing slash required when set. Example: `http://192.168.1.7:8000/`.
  static const String fusionBaseUrl = "";

  /// HTTP base that serves MobileCLIP ONNX files for download-on-first-run.
  /// Expects `{base}mobileclip_visual.onnx` and `{base}mobileclip_visual.onnx.data`.
  /// Sandbox serves these at `/models/` when running. Trailing slash required when set.
  /// Example: `http://192.168.1.7:8000/models/`.
  /// Leave empty to rely on USB/`adb push` into app documents `mobileclip/`.
  static const String mobileClipModelBaseUrl = "http://192.168.1.7:8000/models/";
}
