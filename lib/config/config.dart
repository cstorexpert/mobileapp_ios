class AppConfig {
  //static const String baseUrl = "http://192.168.0.103:4000/api/"; // Local PC backend (LAN)
  //static const String baseUrl = "http://192.168.0.207:4000/api/"; // Replace with your Keycloak base URL
  //static const String baseUrl = "http://172.17.176.1:4000/api/"; // Replace with your Keycloak base URL
  static const String baseUrl = "https://cstorexpert-backend.onrender.com/api/";

  /// CountX MobileCLIP sandbox (Phase 1 LAN bridge).
  /// Run: `python countx_live_preview_sandbox/server.py` then set this to your PC's Wi‑Fi IP.
  /// Trailing slash required.
  static const String fusionBaseUrl = "http://192.168.1.7:8000/";
}
