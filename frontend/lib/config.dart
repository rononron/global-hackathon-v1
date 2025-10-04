class AppConfig {
  // API-Konfiguration
  //static const String apiUrl = 'http://localhost:8000/memories';
  static const String apiUrl = 'https://ronnyactahackathon.onrender.com/memories';
  
  // Weitere Konfigurationen können hier hinzugefügt werden
  static const String appName = 'Memory Keeper';
  static const String appVersion = '1.0.0';
  
  // Entwicklung vs. Produktion
  static const bool isDevelopment = true;
  
  // API-Endpunkte
  static const String memoriesEndpoint = '/memories';
  static const String uploadMediaEndpoint = '/upload-media';
  static const String mediaEndpoint = '/media';
}
