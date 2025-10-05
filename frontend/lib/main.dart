import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:html' as html;
import 'config.dart';

// Datenmodelle
class MediaFile {
  final String filename;
  final String fileType; // 'photo', 'video', 'audio'
  final int fileSize;
  final int? duration; // Für Audio/Video in Sekunden
  final File? localFile; // Lokale Datei für Upload

  MediaFile({
    required this.filename,
    required this.fileType,
    required this.fileSize,
    this.duration,
    this.localFile,
  });

  Map<String, dynamic> toJson() => {
    'filename': filename,
    'file_type': fileType,
    'file_size': fileSize,
    'duration': duration,
  };

  factory MediaFile.fromJson(Map<String, dynamic> json) => MediaFile(
    filename: json['filename'],
    fileType: json['file_type'],
    fileSize: json['file_size'] ?? 0, // Default für Demo
    duration: json['duration'],
  );
}

class Memory {
  final int? id;
  final String title;
  final String content;
  final List<MediaFile> mediaFiles;
  final String? lifeChapter; // Neues Feld für Lebensabschnitt
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Memory({
    this.id,
    required this.title,
    required this.content,
    this.mediaFiles = const [],
    this.lifeChapter,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'media_files': mediaFiles.map((f) => f.toJson()).toList(),
    'life_chapter': lifeChapter,
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };

  factory Memory.fromJson(Map<String, dynamic> json) => Memory(
    id: json['id'],
    title: json['title'],
    content: json['content'],
    mediaFiles: (json['media_files'] as List?)
        ?.map((f) => MediaFile.fromJson(f))
        .toList() ?? [],
    lifeChapter: json['life_chapter'],
    createdAt: json['created_at'] != null 
        ? DateTime.parse(json['created_at']) 
        : null,
    updatedAt: json['updated_at'] != null 
        ? DateTime.parse(json['updated_at']) 
        : null,
  );
}

class Question {
  final int id;
  final String questionText;
  final String category;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Question({
    required this.id,
    required this.questionText,
    required this.category,
    this.createdAt,
    this.updatedAt,
  });

  factory Question.fromJson(Map<String, dynamic> json) => Question(
    id: json['id'],
    questionText: json['question_text'],
    category: json['category'],
    createdAt: json['created_at'] != null 
        ? DateTime.parse(json['created_at']) 
        : null,
    updatedAt: json['updated_at'] != null 
        ? DateTime.parse(json['updated_at']) 
        : null,
  );
}

class DailySummary {
  final int? id;
  final String date;
  final String summary;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DailySummary({
    this.id,
    required this.date,
    required this.summary,
    this.createdAt,
    this.updatedAt,
  });

  factory DailySummary.fromJson(Map<String, dynamic> json) => DailySummary(
    id: json['id'],
    date: json['date'],
    summary: json['summary'],
    createdAt: json['created_at'] != null 
        ? DateTime.parse(json['created_at']) 
        : null,
    updatedAt: json['updated_at'] != null 
        ? DateTime.parse(json['updated_at']) 
        : null,
  );
}

void main() {
  runApp(MemoryKeeperApp());
}

class MemoryKeeperApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Memory Keeper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: Colors.teal[400],
        scaffoldBackgroundColor: Colors.grey[50],
        textTheme: TextTheme(
          bodyMedium: TextStyle(color: Colors.grey[800], fontSize: 16),
        ),
      ),
      home: MemoryPage(),
    );
  }
}

class MemoryPage extends StatefulWidget {
  @override
  _MemoryPageState createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _speechController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  List<Memory> memories = [];
  List<Question> questions = [];
  List<DailySummary> dailySummaries = [];
  final apiUrl = AppConfig.apiUrl;
  bool showPostEditor = false;
  bool isListening = false;
  bool showHistory = false;
  bool showDetailView = false;
  bool showDailySummary = false;
  bool showSeamlessScrollView = false; // Neue Variable für seamless Scroll-Ansicht
  bool showDailySummariesList = false; // Neue Variable für Tageszusammenfassungs-Liste (Oma-Seite)
  bool showChatView = false; // Neue Variable für Chat-Ansicht (Oma-Seite)
  DateTime? seamlessScrollStartDay; // Tag von dem die seamless scroll view startet
  Map<String, dynamic>? selectedEntry;
  DailySummary? currentDailySummary;
  int currentStreak = 0;
  late bool isLargeMode = true; // Standard: vergrößerter Modus
  bool hasSelectedUserType = false; // Neue Variable für Einstiegspunkt
  bool isFamilyView = false; // Neue Variable für Familienmitglieder-Ansicht
  Set<int> viewedMemoryIds = {}; // IDs der bereits gesehenen Memories
  bool hasVisitedFamilyView = false; // Track ob Familienmitglieder-Seite schon besucht wurde
  bool isOmaView = false; // Neue Variable für Oma-Ansicht
  bool isLifeChaptersView = false; // Neue Variable für Kapitel des Lebens
  bool isFamilyMembersView = false; // Neue Variable für Angehörige der Eingabenden Person
  String? previousView; // Verfolgt die vorherige Ansicht für Navigation
  Set<int> likedMemories = {}; // IDs der gelikten Memories
  Map<int, int> memoryLikeCounts = {}; // Memory ID -> Like Count
  bool hasLoadedLikesForOma = false; // Track ob Likes für Oma-Ansicht geladen wurden
  ScrollController? seamlessScrollController; // Controller für seamless scroll view
  bool hasScrolledToStartDay = false; // Track ob bereits zum Start-Tag gescrollt wurde
  late AnimationController _pulseController;
  late AnimationController _pulseController2;
  String _recognizedText = '';
  bool _isAvailable = true; // Simuliert verfügbare Spracherkennung
  
  // Angehörige für die Eingabende Person
  final List<Map<String, dynamic>> familyMembers = [
    {
      'id': 'son1',
      'name': 'Michael',
      'relation': 'Son',
      'icon': Icons.man,
      'color': Colors.blue,
      'hasNewContent': true,
    },
    {
      'id': 'son2',
      'name': 'Thomas',
      'relation': 'Son',
      'icon': Icons.man,
      'color': Colors.blue,
      'hasNewContent': false,
    },
    {
      'id': 'daughter',
      'name': 'Sarah',
      'relation': 'Daughter',
      'icon': Icons.woman,
      'color': Colors.pink,
      'hasNewContent': true,
    },
    {
      'id': 'grandson1',
      'name': 'Lukas',
      'relation': 'Grandson',
      'icon': Icons.child_care,
      'color': Colors.green,
      'hasNewContent': false,
    },
    {
      'id': 'grandson2',
      'name': 'Max',
      'relation': 'Grandson',
      'icon': Icons.child_care,
      'color': Colors.green,
      'hasNewContent': true,
    },
    {
      'id': 'granddaughter1',
      'name': 'Emma',
      'relation': 'Granddaughter',
      'icon': Icons.child_care,
      'color': Colors.purple,
      'hasNewContent': false,
    },
    {
      'id': 'granddaughter2',
      'name': 'Sophie',
      'relation': 'Granddaughter',
      'icon': Icons.child_care,
      'color': Colors.purple,
      'hasNewContent': true,
    },
  ];

  // Lebensabschnitte für "Kapitel des Lebens"
  final List<Map<String, dynamic>> lifeChapters = [
    {
      'id': 'childhood',
      'title': 'Childhood',
      'subtitle': 'Early memories',
      'icon': Icons.child_care,
      'color': Colors.orange,
      'completed': true,
    },
    {
      'id': 'school',
      'title': 'School Years',
      'subtitle': 'Learning & growing',
      'icon': Icons.school,
      'color': Colors.blue,
      'completed': true,
    },
    {
      'id': 'youth',
      'title': 'Youth',
      'subtitle': 'Adventures & dreams',
      'icon': Icons.emoji_people,
      'color': Colors.green,
      'completed': true,
    },
    {
      'id': 'career',
      'title': 'Career',
      'subtitle': 'Work & achievements',
      'icon': Icons.work,
      'color': Colors.purple,
      'completed': false,
    },
    {
      'id': 'family',
      'title': 'Family Life',
      'subtitle': 'Love & children',
      'icon': Icons.family_restroom,
      'color': Colors.pink,
      'completed': false,
    },
    {
      'id': 'travels',
      'title': 'Travels',
      'subtitle': 'Places & experiences',
      'icon': Icons.flight,
      'color': Colors.teal,
      'completed': false,
    },
    {
      'id': 'wisdom',
      'title': 'Wisdom',
      'subtitle': 'Life lessons',
      'icon': Icons.lightbulb,
      'color': Colors.amber,
      'completed': false,
    },
  ];
  
  // History View States
  late bool isHistoryView = false;
  DateTime currentMonth = DateTime.now();
  DateTime? selectedDay;
  late ScrollController _calendarScrollController;
  List<Map<String, dynamic>> historyEntries = [];
  
  // Media States
  List<MediaFile> _selectedMediaFiles = [];
  final ImagePicker _imagePicker = ImagePicker();
  bool _showSimulatedMedia = false;
  List<Map<String, dynamic>> _simulatedMediaFiles = [];
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _recordingPath;
  bool _showMediaExpanded = false;

  @override
  void initState() {
    super.initState();
    // Wake-up ping to backend for demo purposes
    _wakeUpBackend();
    fetchMemories();
    fetchQuestions();
    _loadLikes();
    _loadLikeCounts();
    seamlessScrollController = ScrollController();
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseController2 = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );
    _calendarScrollController = ScrollController();
    _initializeSampleData();
  }

  void _initializeSampleData() {
    // Beispieldaten werden nicht mehr geladen - nur echte Daten aus der API
    // Die historyEntries werden jetzt über _syncHistoryEntries() mit den echten Daten synchronisiert
    historyEntries = [];
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pulseController2.dispose();
    _speechController.dispose();
    _titleController.dispose();
    _calendarScrollController.dispose();
    seamlessScrollController?.dispose();
    super.dispose();
  }

  // Wake-up ping to backend for demo purposes
  Future<void> _wakeUpBackend() async {
    try {
      // Send a simple ping to wake up the backend server
      final response = await http.get(
        Uri.parse('$apiUrl/wake-up'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(Duration(seconds: 5));
      
      print('Backend wake-up ping sent (status: ${response.statusCode})');
    } catch (e) {
      // Silently ignore errors - this is just a wake-up ping
      print('Backend wake-up ping failed (this is normal): $e');
    }
  }

  Future<void> fetchMemories() async {
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          memories = data.map((json) => Memory.fromJson(json)).toList();
          // Synchronisiere historyEntries mit den echten Daten
          _syncHistoryEntries();
          // Berechne aktuelle Streak
          currentStreak = calculateStreak();
        });
        
        // Lade Like-Counts für alle Memories
        _loadLikeCounts();
      }
    } catch (e) {
      print('Error fetching memories: $e');
    }
  }

  Future<void> fetchQuestions() async {
    try {
      final response = await http.get(Uri.parse('${AppConfig.apiUrl.replaceAll('/memories', '')}/questions'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          questions = data.map((json) => Question.fromJson(json)).toList();
        });
      }
    } catch (e) {
      print('Error fetching questions: $e');
      setState(() {
        questions = []; // Leere Liste bei Fehler
      });
    }
  }

  Future<void> fetchDailySummaries() async {
    try {
      final response = await http.get(Uri.parse('${AppConfig.apiUrl.replaceAll('/memories', '')}/daily-summaries'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          dailySummaries = data.map((json) => DailySummary.fromJson(json)).toList();
        });
      }
    } catch (e) {
      print('Error fetching daily summaries: $e');
      setState(() {
        dailySummaries = [];
      });
    }
  }

  Future<void> fetchDailySummaryForDate(DateTime date) async {
    try {
      final dateString = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final response = await http.get(Uri.parse('${AppConfig.apiUrl.replaceAll('/memories', '')}/daily-summaries/$dateString'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          currentDailySummary = DailySummary.fromJson(data);
          showDailySummary = true;
          // Schließe andere Ansichten um Tageszusammenfassung anzuzeigen
          showDetailView = false;
        });
      } else {
        setState(() {
          currentDailySummary = null;
          showDailySummary = true;
          // Schließe andere Ansichten um Tageszusammenfassung anzuzeigen
          showDetailView = false;
        });
      }
    } catch (e) {
      print('Error fetching daily summary: $e');
      setState(() {
        currentDailySummary = null;
        showDailySummary = true;
        // Schließe andere Ansichten um Tageszusammenfassung anzuzeigen
        showDetailView = false;
      });
    }
  }

  // Alle Tageszusammenfassungen abrufen
  Future<List<DailySummary>> _fetchAllDailySummaries() async {
    try {
      final response = await http.get(Uri.parse('${AppConfig.apiUrl.replaceAll('/memories', '')}/daily-summaries'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => DailySummary.fromJson(json)).toList();
      } else {
        return [];
      }
    } catch (e) {
      print('Error fetching all daily summaries: $e');
      return [];
    }
  }

  Future<void> deleteMemory(int memoryId) async {
    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.apiUrl.replaceAll('/memories', '')}/memories/$memoryId'),
      );
      
      if (response.statusCode == 200) {
        // Memory erfolgreich gelöscht - lade Daten neu
        await fetchMemories();
        print('Memory successfully deleted');
      } else {
        print('Fehler beim Löschen der Memory: ${response.statusCode}');
      }
    } catch (e) {
      print('Error deleting memory: $e');
    }
  }

  void _syncHistoryEntries() {
    // Konvertiere Memory-Objekte zu historyEntries-Format
    historyEntries = memories.map((memory) {
      return {
        'id': memory.id,
        'title': memory.title,
        'content': memory.content,
        'media_files': memory.mediaFiles.map((f) => {
          'filename': f.filename,
          'file_type': f.fileType,
          'file_size': f.fileSize,
          'duration': f.duration,
          'created_at': DateTime.now().toIso8601String(), // Demo-Zeitstempel
        }).toList(),
        'timestamp': memory.createdAt ?? DateTime.now(),
        'date': memory.createdAt ?? DateTime.now(),
      };
    }).toList();
  }

  Future<void> addMemory(String content, {String? title, List<MediaFile>? mediaFiles, String? lifeChapter}) async {
    if (content.trim().isEmpty) return;
    
    // Konvertiere simulierte Anhänge zu MediaFile-Objekten
    final convertedMediaFiles = _simulatedMediaFiles.map((file) => MediaFile(
      filename: file['filename'],
      fileType: file['file_type'],
      fileSize: file['file_size'],
      duration: file['duration'],
    )).toList();
    
    print('DEBUG: Simulierte Anhänge: ${_simulatedMediaFiles.length}');
    print('DEBUG: Konvertierte Anhänge: ${convertedMediaFiles.length}');
    
    final memory = Memory(
      title: title ?? "",  // Erstmal leer - wird von KI generiert
      content: content,
      mediaFiles: mediaFiles ?? convertedMediaFiles,
      lifeChapter: lifeChapter,
    );
    
    try {
      // 1. Memory ohne Titel speichern
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(memory.toJson()),
      );
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final memoryId = responseData['id'];
        
        // 2. KI-Titel generieren und zu Memory hinzufügen
        await _generateAndSetTitle(memoryId, content);
        
        setState(() {
        _controller.clear();
          _titleController.clear();
          _selectedMediaFiles.clear();
          _simulatedMediaFiles.clear(); // Lösche simulierte Anhänge nach dem Speichern
        });
        
        // Lade die Daten neu, damit sie in der Kalender-Ansicht erscheinen
        await fetchMemories();
      }
    } catch (e) {
      print('Error adding memory: $e');
    }
  }

  Future<void> _generateAndSetTitle(int memoryId, String content) async {
    try {
      // KI-Titel generieren
      final titleResponse = await http.post(
        Uri.parse('${AppConfig.apiUrl.replaceAll('/memories', '')}/generate-title'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'content': content}),
      );
      
      if (titleResponse.statusCode == 200) {
        final titleData = json.decode(titleResponse.body);
        final generatedTitle = titleData['generated_title'];
        
        // Titel zur Memory hinzufügen
        await http.put(
          Uri.parse('${AppConfig.apiUrl.replaceAll('/memories', '')}/memories/$memoryId/title'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'content': content}),
        );
        
        print('KI-Titel generiert und gesetzt: $generatedTitle');
      }
    } catch (e) {
      print('Fehler bei KI-Titel-Generierung: $e');
    }
  }


  // Media-Funktionen
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(source: source);
      if (image != null) {
        final file = File(image.path);
        final mediaFile = MediaFile(
          filename: image.name,
          fileType: 'photo',
          fileSize: await file.length(),
          localFile: file,
        );
    setState(() {
          _selectedMediaFiles.add(mediaFile);
        });
      }
    } catch (e) {
      print('Fehler beim Auswählen des Bildes: $e');
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final XFile? video = await _imagePicker.pickVideo(source: source);
      if (video != null) {
        final file = File(video.path);
        final mediaFile = MediaFile(
          filename: video.name,
          fileType: 'video',
          fileSize: await file.length(),
          localFile: file,
        );
    setState(() {
          _selectedMediaFiles.add(mediaFile);
        });
      }
    } catch (e) {
      print('Fehler beim Auswählen des Videos: $e');
    }
  }

  Future<void> _startRecording() async {
    try {
      // Für Web: Simuliere Audio-Aufnahme
      setState(() {
        _isRecording = true;
      });
      
      // Simuliere 3 Sekunden Aufnahme
      await Future.delayed(Duration(seconds: 3));
      
      if (_isRecording) {
        _stopRecording();
      }
    } catch (e) {
      print('Fehler beim Starten der Aufnahme: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      setState(() {
        _isRecording = false;
      });
      
      // Simuliere eine Audio-Datei
      final mediaFile = MediaFile(
        filename: 'recording_${DateTime.now().millisecondsSinceEpoch}.m4a',
        fileType: 'audio',
        fileSize: 1024 * 100, // 100KB simulierte Größe
        duration: 60, // Maximal 1 Minute
      );
      setState(() {
        _selectedMediaFiles.add(mediaFile);
      });
    } catch (e) {
      print('Fehler beim Stoppen der Aufnahme: $e');
    }
  }

  void _removeMediaFile(int index) {
    setState(() {
      _selectedMediaFiles.removeAt(index);
    });
  }

  void _simulatePhotoCapture() {
    setState(() {
      _simulatedMediaFiles.add({
        'filename': 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg',
        'file_type': 'image',
        'file_size': 2048000, // 2MB
        'duration': null,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  void _simulateVideoCapture() {
    setState(() {
      _simulatedMediaFiles.add({
        'filename': 'video_${DateTime.now().millisecondsSinceEpoch}.mp4',
        'file_type': 'video',
        'file_size': 10240000, // 10MB
        'duration': 45, // 45 Sekunden
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  // Hilfsfunktionen für Media-Darstellung
  Color _getMediaColor(String fileType) {
    switch (fileType) {
      case 'photo':
        return Colors.blue[600]!;
      case 'video':
        return Colors.purple[600]!;
      case 'audio':
        return Colors.green[600]!;
      default:
        return Colors.grey[600]!;
    }
  }

  IconData _getMediaIcon(String fileType) {
    switch (fileType) {
      case 'photo':
        return Icons.image;
      case 'video':
        return Icons.video_file;
      case 'audio':
        return Icons.audio_file;
      default:
        return Icons.attach_file;
    }
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) {
      return '${seconds}s';
    } else {
      final minutes = seconds ~/ 60;
      final remainingSeconds = seconds % 60;
      return '${minutes}m ${remainingSeconds}s';
    }
  }

  void startMicrophonePost() {
    if (!_isAvailable) return;
    
    setState(() {
      showPostEditor = true;
      isListening = true;
      _recognizedText = '';
      _speechController.clear();
      _pulseController.repeat();
      Future.delayed(Duration(milliseconds: 500), () {
        if (isListening) {
          _pulseController2.repeat();
        }
      });
      _simulateListening();
    });
  }


  void _simulateListening() async {
    // Simuliert Spracherkennung für Demo-Zwecke - wortweise
    final demoText = "Did you know I went to Italy in 1964?";
    final words = demoText.split(' ');
    
    for (int i = 0; i < words.length; i++) {
      if (!isListening) break; // Stoppe wenn nicht mehr zugehört wird
      
      await Future.delayed(Duration(milliseconds: 800)); // Pause zwischen Wörtern
      
      if (isListening) {
        setState(() {
          // Nur die neuen Wörter bis zum aktuellen Index anzeigen
          String newText = words.sublist(0, i + 1).join(' ');
          _recognizedText = newText;
          _speechController.text = newText;
        });
      }
    }
  }

  void _stopListening() {
    setState(() {
      isListening = false;
      _pulseController.stop();
      _pulseController2.stop();
    });
  }

  void _sendPost() {
    if (_speechController.text.trim().isNotEmpty) {
      addMemory(_speechController.text);
      _speechController.clear();
      _recognizedText = '';
      _selectedMediaFiles.clear();
      setState(() {
        showPostEditor = false;
        isListening = false;
        _pulseController.stop();
        _pulseController2.stop();
      });
    }
  }

  void _cancelPost() {
    _speechController.clear();
    _recognizedText = '';
    _selectedMediaFiles.clear();
    setState(() {
      showPostEditor = false;
      isListening = false;
      _showMediaExpanded = false;
      _pulseController.stop();
      _pulseController2.stop();
    });
  }


  void toggleHistory() {
    setState(() {
      isHistoryView = !isHistoryView;
      selectedDay = null; // Reset selected day when entering/exiting history
      seamlessScrollStartDay = null; // Reset Start-Tag
      hasScrolledToStartDay = false; // Reset Scroll-Flag
      showDetailView = false; // Schließe Detail-Ansicht wenn Historie geschlossen wird
      showDailySummary = false; // Schließe Tageszusammenfassung wenn Historie geschlossen wird
      showSeamlessScrollView = false; // Schließe seamless Scroll-Ansicht wenn Historie geschlossen wird
      showDailySummariesList = false; // Schließe Tageszusammenfassungs-Liste wenn Historie geschlossen wird
      showChatView = false; // Schließe Chat-Ansicht wenn Historie geschlossen wird
    });
    
    // Kein automatisches Scrollen - der Kalender startet standardmäßig beim heutigen Tag (unten)
  }



  void openEntryDetail(Map<String, dynamic> entry) {
    setState(() {
      selectedEntry = entry;
      showDetailView = true;
    });
  }

  void closeEntryDetail() {
    setState(() {
      showDetailView = false;
      selectedEntry = null;
      // Bleibe in der aktuellen Ansicht (seamless scroll oder kalender)
    });
  }

  void closeDailySummary() {
    setState(() {
      showDailySummary = false;
      currentDailySummary = null;
      // Kehre zur seamless scroll view zurück (falls aktiv)
      if (showSeamlessScrollView) {
        // Bleibe in seamless scroll view
      } else {
        // Kehre zur Kalender-Ansicht zurück
      }
    });
  }

  // KI-Symbol Widget für wiederverwendbare Verwendung
  Widget _buildAISymbol({double size = 16}) {
    return Icon(
      Icons.auto_awesome,
      size: size,
      color: Colors.purple[600],
    );
  }

  // Untere Navigationsleiste
  Widget _buildBottomNavigation() {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Links: Kapitel des Lebens
          GestureDetector(
            onTap: () {
              setState(() {
                previousView = 'main'; // Remember we came from main page
                isLifeChaptersView = true;
                isFamilyView = false; // Exit family view when going to life chapters
                isOmaView = false; // Exit Oma view when going to life chapters
              });
            },
            child: Container(
              padding: EdgeInsets.all(isLargeMode ? 20 : 16),
              decoration: BoxDecoration(
                color: Colors.blue[100],
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue[200]!,
                    blurRadius: isLargeMode ? 12 : 8,
                    spreadRadius: isLargeMode ? 3 : 2,
                  ),
                ],
              ),
              child: Icon(
                Icons.menu_book,
                size: isLargeMode ? 40 : 32,
                color: Colors.blue[600],
              ),
            ),
          ),
          
          // Mitte: Mikrofon (Navigation zur Startseite)
          GestureDetector(
            onTap: () {
              // Zurück zur Startseite
              setState(() {
                isHistoryView = false;
                showDetailView = false;
                showDailySummary = false;
                showPostEditor = false;
              });
            },
            child: Container(
              padding: EdgeInsets.all(isLargeMode ? 24 : 20),
              decoration: BoxDecoration(
                color: Colors.teal[100],
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.teal[200]!,
                    blurRadius: isLargeMode ? 12 : 8,
                    spreadRadius: isLargeMode ? 3 : 2,
                  ),
                ],
              ),
              child: Icon(
                Icons.mic_none,
                size: isLargeMode ? 40 : 32,
                color: Colors.teal[600],
              ),
            ),
          ),
          
          // Rechts: Familienmitglieder (Angehörige der Eingabenden Person)
          GestureDetector(
            onTap: () {
              setState(() {
                isFamilyMembersView = true;
                isFamilyView = false;
                isOmaView = false;
                isLifeChaptersView = false;
              });
            },
            child: Container(
              padding: EdgeInsets.all(isLargeMode ? 20 : 16),
              decoration: BoxDecoration(
                color: Colors.green[100],
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.green[200]!,
                    blurRadius: isLargeMode ? 12 : 8,
                    spreadRadius: isLargeMode ? 3 : 2,
                  ),
                ],
              ),
              child: Icon(
                Icons.family_restroom,
                size: isLargeMode ? 40 : 32,
                color: Colors.green[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Berechnet die aktuelle Streak (aufeinanderfolgende Tage mit Einträgen)
  int calculateStreak() {
    if (historyEntries.isEmpty) return 0;
    
    // Sortiere Einträge nach Datum (neueste zuerst)
    final sortedEntries = List<Map<String, dynamic>>.from(historyEntries);
    sortedEntries.sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
    
    // Gruppiere Einträge nach Datum
    final Map<String, List<Map<String, dynamic>>> entriesByDate = {};
    for (var entry in sortedEntries) {
      final date = entry['timestamp'].toIso8601String().split('T')[0];
      if (!entriesByDate.containsKey(date)) {
        entriesByDate[date] = [];
      }
      entriesByDate[date]!.add(entry);
    }
    
    // Berechne Streak rückwärts vom heutigen Tag
    final today = DateTime.now();
    int streak = 0;
    
    // Zähle rückwärts vom heutigen Tag
    for (int i = 0; i < 365; i++) {
      final checkDate = today.subtract(Duration(days: i));
      final dateString = checkDate.toIso8601String().split('T')[0];
      
      if (entriesByDate.containsKey(dateString)) {
        streak++;
      } else {
        // Wenn heute noch keine Einträge hat, aber gestern welche hatte, zähle trotzdem
        if (i == 0 && streak == 0) {
          // Heute hat keine Einträge, aber prüfe ob gestern welche hatte
          continue;
        } else {
          break; // Streak unterbrochen
        }
      }
    }
    
    return streak;
  }

  // Seamless scrollbare Liste der Tageszusammenfassungen (für Oma-Seite)
  Widget _buildDailySummariesListView() {
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Header mit Navigation
          Container(
            padding: EdgeInsets.only(top: 40, left: 20, right: 20, bottom: 20),
            child: Row(
              children: [
                // Zurück-Button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      showDailySummariesList = false;
                      isOmaView = true;
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: isLargeMode ? 12 : 8,
                          spreadRadius: isLargeMode ? 3 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.arrow_back,
                      size: isLargeMode ? 40 : 32,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                SizedBox(width: 20),
                // Titel
                Expanded(
                  child: Text(
                    'Daily Summaries',
                    style: TextStyle(
                      fontSize: isLargeMode ? 32 : 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[400],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Liste der Tageszusammenfassungen
          Expanded(
            child: FutureBuilder<List<DailySummary>>(
              future: _fetchAllDailySummaries(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(
                    child: CircularProgressIndicator(
                      color: Colors.teal[400],
                    ),
                  );
                }
                
                if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.auto_stories,
                          size: isLargeMode ? 80 : 64,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: 20),
                        Text(
                          'No daily summaries yet',
                          style: TextStyle(
                            fontSize: isLargeMode ? 24 : 20,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Summaries will appear here',
                          style: TextStyle(
                            fontSize: isLargeMode ? 18 : 16,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                
                final summaries = snapshot.data!;
                return ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  itemCount: summaries.length,
                  itemBuilder: (context, index) {
                    final summary = summaries[index];
                    final date = DateTime.parse(summary.date);
                    
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          currentDailySummary = summary;
                          showDailySummary = true;
                          showDailySummariesList = false;
                        });
                      },
                      child: Container(
                        margin: EdgeInsets.only(bottom: 16),
                        padding: EdgeInsets.all(isLargeMode ? 20 : 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Datum und AI-Symbol
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: isLargeMode ? 18 : 16,
                                  color: Colors.teal[600],
                                ),
                                SizedBox(width: 8),
                                Text(
                                  _formatDateForDisplay(date),
                                  style: TextStyle(
                                    fontSize: isLargeMode ? 18 : 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.teal[700],
                                  ),
                                ),
                                Spacer(),
                                // AI-Symbol
                                Icon(
                                  Icons.psychology,
                                  size: isLargeMode ? 18 : 16,
                                  color: Colors.grey[500],
                                ),
                              ],
                            ),
                            SizedBox(height: 12),
                            // Zusammenfassung Preview
                            Text(
                              summary.summary.length > 150 
                                  ? '${summary.summary.substring(0, 150)}...'
                                  : summary.summary,
                              style: TextStyle(
                                fontSize: isLargeMode ? 16 : 14,
                                color: Colors.grey[600],
                                height: 1.4,
                              ),
                            ),
                            SizedBox(height: 12),
                            // "Read more" Hinweis
                            Row(
                              children: [
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: isLargeMode ? 14 : 12,
                                  color: Colors.teal[400],
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Tap to read full summary',
                                  style: TextStyle(
                                    fontSize: isLargeMode ? 14 : 12,
                                    color: Colors.teal[400],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Chat-Ansicht für Angehörige (ChatGPT/WhatsApp-ähnlich)
  Widget _buildChatView() {
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Header mit Navigation
          Container(
            padding: EdgeInsets.only(top: 40, left: 20, right: 20, bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              children: [
                // Zurück-Button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      showChatView = false;
                      isOmaView = true;
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: isLargeMode ? 12 : 8,
                          spreadRadius: isLargeMode ? 3 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.arrow_back,
                      size: isLargeMode ? 40 : 32,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                SizedBox(width: 20),
                // Chat-Titel
                Expanded(
                  child: Text(
                    'Chat with Grandma',
                    style: TextStyle(
                      fontSize: isLargeMode ? 32 : 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.pink[400],
                    ),
                  ),
                ),
                // Online-Status
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.green[300]!,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Colors.green[500],
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Online',
                        style: TextStyle(
                          fontSize: isLargeMode ? 14 : 12,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Chat-Nachrichten-Bereich
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ListView.builder(
                itemCount: _getChatMessages().length,
                itemBuilder: (context, index) {
                  final message = _getChatMessages()[index];
                  final isFromGrandma = message['isFromGrandma'];
                  
                  return Container(
                    margin: EdgeInsets.only(bottom: 16),
                    child: Row(
                      mainAxisAlignment: isFromGrandma 
                          ? MainAxisAlignment.start 
                          : MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isFromGrandma) ...[
                          // Avatar für Oma
                          Container(
                            width: isLargeMode ? 40 : 32,
                            height: isLargeMode ? 40 : 32,
                            decoration: BoxDecoration(
                              color: Colors.pink[100],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.pink[200]!,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.elderly_woman,
                              size: isLargeMode ? 24 : 20,
                              color: Colors.pink[600],
                            ),
                          ),
                          SizedBox(width: 12),
                        ],
                        
                        // Nachrichten-Bubble
                        Flexible(
                          child: Container(
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.7,
                            ),
                            padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                            decoration: BoxDecoration(
                              color: isFromGrandma 
                                  ? Colors.white 
                                  : Colors.pink[400],
                              borderRadius: BorderRadius.circular(20).copyWith(
                                bottomLeft: isFromGrandma 
                                    ? Radius.circular(4) 
                                    : Radius.circular(20),
                                bottomRight: isFromGrandma 
                                    ? Radius.circular(20) 
                                    : Radius.circular(4),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message['text'],
                                  style: TextStyle(
                                    fontSize: isLargeMode ? 16 : 14,
                                    color: isFromGrandma 
                                        ? Colors.grey[800] 
                                        : Colors.white,
                                    height: 1.4,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  message['time'],
                                  style: TextStyle(
                                    fontSize: isLargeMode ? 12 : 10,
                                    color: isFromGrandma 
                                        ? Colors.grey[500] 
                                        : Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        if (!isFromGrandma) ...[
                          SizedBox(width: 12),
                          // Avatar für Angehörigen
                          Container(
                            width: isLargeMode ? 40 : 32,
                            height: isLargeMode ? 40 : 32,
                            decoration: BoxDecoration(
                              color: Colors.blue[100],
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.blue[200]!,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.person,
                              size: isLargeMode ? 24 : 20,
                              color: Colors.blue[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          
          // Text-Eingabe-Bereich
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              children: [
                // Text-Eingabe-Feld
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(
                          color: Colors.grey[500],
                          fontSize: isLargeMode ? 16 : 14,
                        ),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: TextStyle(
                        fontSize: isLargeMode ? 16 : 14,
                        color: Colors.grey[800],
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                ),
                SizedBox(width: 12),
                
                // Senden-Button
                GestureDetector(
                  onTap: () {
                    // TODO: Nachricht senden implementieren
                    print('Message sent');
                  },
                  child: Container(
                    width: isLargeMode ? 50 : 44,
                    height: isLargeMode ? 50 : 44,
                    decoration: BoxDecoration(
                      color: Colors.pink[400],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.pink[200]!,
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.send,
                      size: isLargeMode ? 24 : 20,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Beispiel-Chat-Nachrichten für Demo
  List<Map<String, dynamic>> _getChatMessages() {
    return [
      {
        'text': 'Hello dear! How are you doing today?',
        'isFromGrandma': true,
        'time': '10:30 AM',
      },
      {
        'text': 'Hi Grandma! I\'m doing great, thank you for asking. How about you?',
        'isFromGrandma': false,
        'time': '10:32 AM',
      },
      {
        'text': 'I\'m wonderful! I just finished writing about my garden in my memory app. The roses are blooming beautifully this year.',
        'isFromGrandma': true,
        'time': '10:35 AM',
      },
      {
        'text': 'That sounds lovely! I\'d love to see some photos of your roses.',
        'isFromGrandma': false,
        'time': '10:37 AM',
      },
      {
        'text': 'I\'ll take some pictures today and share them with you. The pink ones are especially beautiful this morning.',
        'isFromGrandma': true,
        'time': '10:40 AM',
      },
      {
        'text': 'Perfect! I can\'t wait to see them. Have a wonderful day, Grandma!',
        'isFromGrandma': false,
        'time': '10:42 AM',
      },
    ];
  }

  // Blog-ähnliche Ansicht für Tageszusammenfassung
  Widget _buildDailySummaryView() {
    // Prüfe ob currentDailySummary vorhanden ist
    if (currentDailySummary == null) {
      return Container(
        color: Colors.grey[50],
        child: Center(
          child: Text(
            'No daily summary available',
            style: TextStyle(
              fontSize: isLargeMode ? 24 : 20,
              color: Colors.grey[600],
            ),
          ),
        ),
      );
    }
    
    final dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    
    // Verwende das Datum aus der currentDailySummary
    final summaryDate = DateTime.parse(currentDailySummary!.date);
    
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Header mit Zurück-Button
          Container(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: closeDailySummary,
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.arrow_back, size: 24, color: Colors.grey[700]),
                  ),
                ),
                SizedBox(width: 20),
                Expanded(
                  child: Text(
                    'Daily Summary',
                    style: TextStyle(
                      fontSize: isLargeMode ? 24 : 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Blog-Content
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (currentDailySummary != null) ...[
                    // Datum-Header (Blog-Style)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blue[200]!, width: 1),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${summaryDate.day}. ${monthNames[summaryDate.month - 1]} ${summaryDate.year}',
                            style: TextStyle(
                              fontSize: isLargeMode ? 28 : 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800],
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            dayNames[summaryDate.weekday - 1],
                            style: TextStyle(
                              fontSize: isLargeMode ? 18 : 16,
                              color: Colors.blue[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    SizedBox(height: 32),
                    
                    // Zusammenfassung-Text (Blog-Artikel-Style)
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Artikel-Titel
                          Text(
                            'My Day in Words',
                            style: TextStyle(
                              fontSize: isLargeMode ? 22 : 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                              letterSpacing: 0.5,
                            ),
                          ),
                          
                          SizedBox(height: 24),
                          
                          // Artikel-Text
                          Text(
                            currentDailySummary!.summary,
                            style: TextStyle(
                              fontSize: isLargeMode ? 18 : 16,
                              color: Colors.grey[700],
                              height: 1.6,
                              letterSpacing: 0.3,
                            ),
                          ),
                          
                          SizedBox(height: 32),
                          
                          // Artikel-Footer
                          Container(
                            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                _buildAISymbol(size: isLargeMode ? 20 : 18),
                                SizedBox(width: 12),
                                Text(
                                  'AI-Generated Summary',
                                  style: TextStyle(
                                    fontSize: isLargeMode ? 14 : 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Keine Zusammenfassung vorhanden
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.auto_stories_outlined,
                            size: isLargeMode ? 80 : 64,
                            color: Colors.grey[400],
                          ),
                          SizedBox(height: 24),
                          Text(
                            'No Daily Summary Available',
                            style: TextStyle(
                              fontSize: isLargeMode ? 20 : 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No AI-generated summary has been created for this day yet.',
                            style: TextStyle(
                              fontSize: isLargeMode ? 16 : 14,
                              color: Colors.grey[500],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Generiert alle Monate von Januar bis zum aktuellen Monat
  List<DateTime> _generateMonths() {
    final now = DateTime.now();
    final months = <DateTime>[];
    
    // Starte vom aktuellen Monat und gehe rückwärts zu Januar
    for (int month = now.month; month >= 1; month--) {
      months.add(DateTime(now.year, month));
    }
    
    return months;
  }

  // Hilfsfunktionen für den Kalender
  int _getFirstDayOfWeek(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    return (firstDay.weekday - 1) % 7; // Montag = 0, Sonntag = 6
  }

  int _getDaysInMonth(DateTime month) {
    return DateTime(month.year, month.month + 1, 0).day;
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && 
           date.month == now.month && 
           date.day == now.day;
  }

  // Erstellt ein Grid nur mit vergangenen Tagen, umgekehrt sortiert (neueste zuerst)
  Widget _buildPastDaysGrid(DateTime month, List<Map<String, dynamic>> monthEntries) {
    final now = DateTime.now();
    final pastDays = <int>[];
    
    // Sammle alle vergangenen Tage des Monats
    for (int day = 1; day <= _getDaysInMonth(month); day++) {
      final currentDay = DateTime(month.year, month.month, day);
      if (!currentDay.isAfter(now)) {
        pastDays.add(day);
      }
    }
    
    // Sortiere umgekehrt (neueste Tage zuerst)
    pastDays.sort((a, b) => b.compareTo(a));
    
    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1.0,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: pastDays.length,
      itemBuilder: (context, index) {
        final day = pastDays[index];
        final currentDay = DateTime(month.year, month.month, day);
        final hasEntries = monthEntries.any((entry) => 
          entry['timestamp'].year == currentDay.year &&
          entry['timestamp'].month == currentDay.month &&
          entry['timestamp'].day == currentDay.day
        );
        final isToday = _isToday(currentDay);
        
        return GestureDetector(
          onTap: () => _selectDay(currentDay),
          child: Container(
            decoration: BoxDecoration(
              color: isToday 
                  ? Colors.orange[100] 
                  : hasEntries 
                      ? Colors.teal[100] 
                      : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isToday 
                    ? Colors.orange[400]! 
                    : hasEntries 
                        ? Colors.teal[300]! 
                        : Colors.grey[300]!,
                width: isToday ? 3 : 1,
              ),
              boxShadow: isToday ? [
                BoxShadow(
                  color: Colors.orange[200]!,
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ] : null,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    day.toString(),
                    style: TextStyle(
                      fontSize: isLargeMode ? 18 : 16,
                      fontWeight: FontWeight.bold,
                      color: isToday 
                          ? Colors.orange[800] 
                          : hasEntries 
                              ? Colors.teal[800] 
                              : Colors.grey[800],
                    ),
                  ),
                  if (hasEntries)
                    Container(
                      margin: EdgeInsets.only(top: 2),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isToday ? Colors.orange[600] : Colors.teal[600],
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _selectDay(DateTime day) {
    setState(() {
      selectedDay = day;
      seamlessScrollStartDay = day; // Setze Start-Tag für seamless scroll
      hasScrolledToStartDay = false; // Reset Scroll-Flag für neuen Tag
      showDetailView = false; // Schließe Detail-Ansicht wenn neuer Tag gewählt wird
      showSeamlessScrollView = true; // Öffne seamless Scroll-Ansicht
    });
  }

  void _goBackToCalendar() {
    setState(() {
      selectedDay = null;
      seamlessScrollStartDay = null; // Reset Start-Tag
      hasScrolledToStartDay = false; // Reset Scroll-Flag
      showSeamlessScrollView = false; // Schließe seamless Scroll-Ansicht
      showDailySummariesList = false; // Schließe Tageszusammenfassungs-Liste
      showChatView = false; // Schließe Chat-Ansicht
      showDetailView = false; // Schließe auch Detail-Ansicht
    });
  }

  void _goToPreviousDay() {
    if (selectedDay != null) {
      setState(() {
        selectedDay = selectedDay!.subtract(Duration(days: 1));
      });
    }
  }

  void _goToNextDay() {
    if (selectedDay != null) {
      final today = DateTime.now();
      final tomorrow = selectedDay!.add(Duration(days: 1));
      
      // Nur erlauben bis zum heutigen Tag
      if (tomorrow.isBefore(today) || tomorrow.isAtSameMomentAs(today)) {
        setState(() {
          selectedDay = tomorrow;
        });
      }
    }
  }

  bool _canGoToNextDay() {
    if (selectedDay == null) return false;
    final today = DateTime.now();
    final tomorrow = selectedDay!.add(Duration(days: 1));
    return tomorrow.isBefore(today) || tomorrow.isAtSameMomentAs(today);
  }

  List<Map<String, dynamic>> _getEntriesForDay(DateTime day) {
    return historyEntries
        .where((entry) => 
            entry['date'].year == day.year &&
            entry['date'].month == day.month &&
            entry['date'].day == day.day)
        .toList()
      ..sort((a, b) => a['timestamp'].compareTo(b['timestamp']));
  }

  List<Map<String, dynamic>> _getEntriesForMonth(DateTime month) {
    return historyEntries
        .where((entry) => 
            entry['date'].year == month.year &&
            entry['date'].month == month.month)
        .toList();
  }


  void toggleSizeMode() {
    setState(() {
      isLargeMode = !isLargeMode;
    });
  }

  Widget _buildHistoryView() {
    return Stack(
      children: [
        // Immer nur Kalender-Ansicht, keine Tagesansicht mehr
        _buildCalendarView(),
        
        // Untere Navigationsleiste auch in der Historie
        _buildBottomNavigation(),
      ],
    );
  }

  Widget _buildCalendarView() {
    return _buildScrollableCalendar();
  }

  Widget _buildScrollableCalendar() {
    final months = _generateMonths();
    final monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Header mit Zurück-Button
          Container(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: toggleHistory,
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.arrow_back, size: 24, color: Colors.grey[700]),
                  ),
                ),
                SizedBox(width: 20),
                Expanded(
                  child: Text(
                    'My Memories',
                    style: TextStyle(
                      fontSize: isLargeMode ? 24 : 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
                // "Heute"-Button (nur visuell, kein Scrollen)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.teal[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.teal[300]!, width: 1),
                  ),
                  child: Text(
                    'Today',
                    style: TextStyle(
                      fontSize: isLargeMode ? 16 : 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.teal[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Scrollbarer Kalender
          Expanded(
            child: ListView.builder(
              controller: _calendarScrollController,
              padding: EdgeInsets.all(20),
              itemCount: months.length,
              itemBuilder: (context, monthIndex) {
                final month = months[monthIndex];
                final monthEntries = _getEntriesForMonth(month);
                final daysInMonthCount = _getDaysInMonth(month);
                
                return Container(
                  margin: EdgeInsets.only(bottom: 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Monats-Header
                      Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                          '${monthNames[month.month - 1]} ${month.year}',
                          style: TextStyle(
                            fontSize: isLargeMode ? 22 : 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                      
                            // Kalender-Grid für diesen Monat - nur vergangene Tage, umgekehrt sortiert
                            _buildPastDaysGrid(month, monthEntries),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayView() {
    final dayEntries = _getEntriesForDay(selectedDay!);
    final dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Header mit Zurück-Button
          Container(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _goBackToCalendar,
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.arrow_back, size: 24, color: Colors.grey[700]),
                  ),
                ),
                SizedBox(width: 20),
                // Linker Pfeil (vorheriger Tag)
                GestureDetector(
                  onTap: _goToPreviousDay,
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.teal[100],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chevron_left,
                      size: isLargeMode ? 28 : 24,
                      color: Colors.teal[600],
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Text(
                    '${dayNames[selectedDay!.weekday - 1]}, ${selectedDay!.day}. ${monthNames[selectedDay!.month - 1]} ${selectedDay!.year}',
                    style: TextStyle(
                      fontSize: isLargeMode ? 24 : 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[400],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(width: 16),
                // Rechter Pfeil (nächster Tag)
                GestureDetector(
                  onTap: _goToNextDay,
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _canGoToNextDay() ? Colors.teal[100] : Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.chevron_right,
                      size: isLargeMode ? 28 : 24,
                      color: _canGoToNextDay() ? Colors.teal[600] : Colors.grey[400],
                    ),
                  ),
                ),
                SizedBox(width: 20),
                // Tageszusammenfassung-Button
                GestureDetector(
                  onTap: () => fetchDailySummaryForDate(selectedDay!),
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.auto_stories,
                      size: isLargeMode ? 24 : 20,
                      color: Colors.blue[600],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Einträge des Tages
          Expanded(
            child: dayEntries.isEmpty
                ? Center(
                    child: Text(
                      'No entries for this day',
                      style: TextStyle(
                        fontSize: isLargeMode ? 20 : 18,
                        color: Colors.grey[600],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.all(20),
                    itemCount: dayEntries.length,
                    itemBuilder: (context, index) {
                      final entry = dayEntries[index];
                      final time = entry['timestamp'] as DateTime;
                      final hasMedia = entry['media_files'] != null && (entry['media_files'] as List).isNotEmpty;
                      
                      return GestureDetector(
                        onTap: () => openEntryDetail(entry),
                        child: Container(
                          margin: EdgeInsets.only(bottom: 12),
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        child: Row(
                          children: [
                            // Zeitstempel
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.teal[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  fontSize: isLargeMode ? 16 : 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal[700],
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            // Inhalt (Vorschau)
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Titel oder Anfang des Inhalts
                                  Text(
                                    entry['title'] != null && entry['title'].toString().isNotEmpty
                                        ? entry['title']
                                        : entry['content'].length > 50
                                            ? '${entry['content'].substring(0, 50)}...'
                                            : entry['content'],
                                    style: TextStyle(
                                      fontSize: isLargeMode ? 16 : 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[800],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (entry['title'] != null && entry['title'].toString().isNotEmpty)
                                    Text(
                                      entry['content'].length > 30
                                          ? '${entry['content'].substring(0, 30)}...'
                                          : entry['content'],
                                      style: TextStyle(
                                        fontSize: isLargeMode ? 14 : 12,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            // Media-Indikatoren und Likes
                            if (hasMedia) ...[
                              SizedBox(width: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.attach_file,
                                    size: isLargeMode ? 20 : 16,
                                    color: Colors.teal[600],
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    '${(entry['media_files'] as List).length}',
                                    style: TextStyle(
                                      fontSize: isLargeMode ? 14 : 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal[600],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            // Like-Indikator
                            if (entry['id'] != null && memoryLikeCounts.containsKey(entry['id']) && memoryLikeCounts[entry['id']]! > 0) ...[
                              SizedBox(width: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.favorite,
                                    size: isLargeMode ? 18 : 16,
                                    color: Colors.red[500],
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    '${memoryLikeCounts[entry['id']]}',
                                    style: TextStyle(
                                      fontSize: isLargeMode ? 14 : 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red[500],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            // Pfeil-Icon
                            SizedBox(width: 8),
                            Icon(
                              Icons.chevron_right,
                              size: isLargeMode ? 24 : 20,
                              color: Colors.grey[400],
                            ),
                          ],
                        ),
                      ));
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostEditor() {
    return Column(
      children: [
        // Abstand von oben - mehr Platz für Icons
        SizedBox(height: 120),
        
        // Text-Eingabe-Bubble (tiefer positioniert)
        Container(
          margin: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              // Header mit X-Button
              Row(
                children: [
                  Expanded(
                    child: Text(
                      isListening ? 'Listening...' : 'New Post...',
                      style: TextStyle(
                        fontSize: isLargeMode ? 20 : 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal[400],
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _cancelPost,
                    child: Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        size: isLargeMode ? 28 : 24,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 15),
              // Text-Eingabe mit Mikrofon
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _speechController,
                      maxLines: 3,
                      onTap: () {
                        if (isListening) {
                          _stopListening();
                        }
                      },
                      decoration: InputDecoration(
                        hintText: isListening 
                            ? 'Gesprochener Text erscheint hier...' 
                            : 'Text eingeben...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey[300]!),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.teal[400]!),
                        ),
                      ),
                      style: TextStyle(fontSize: isLargeMode ? 20 : 18),
                    ),
                  ),
                  SizedBox(width: 12),
                  // Mikrofon-Icon (nur wenn nicht zuhörend)
                  if (!isListening)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          isListening = true;
                          _pulseController.repeat();
                          _pulseController2.repeat();
                        });
                        _simulateListening();
                      },
                      child: Container(
                        padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                        decoration: BoxDecoration(
                          color: Colors.teal[100],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.teal[300]!,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.mic,
                          size: isLargeMode ? 28 : 24,
                          color: Colors.teal[600],
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 15),
              // Media-Anhänge und Senden-Button in einer Zeile
              Row(
                children: [
                  // +-Button für Anhänge (links unten)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showMediaExpanded = !_showMediaExpanded;
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                      decoration: BoxDecoration(
                        color: Colors.teal[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal[200]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showMediaExpanded ? Icons.remove : Icons.add,
                            size: isLargeMode ? 24 : 20,
                            color: Colors.teal[600],
                          ),
                          if (_selectedMediaFiles.isNotEmpty) ...[
                            SizedBox(width: 8),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.teal[600],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_selectedMediaFiles.length}',
                                style: TextStyle(
                                  fontSize: isLargeMode ? 14 : 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  // Senden-Button (rechts)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _sendPost,
                      icon: Icon(Icons.send, size: 24),
                      label: Text('Send', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal[400],
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        minimumSize: Size(0, 56),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              // Aufklappbare Media-Buttons (wenn erweitert)
              if (_showMediaExpanded) ...[
                SizedBox(height: 16),
                _buildExpandedMediaSection(),
              ],
              
              // Angehängte Media-Dateien (wenn vorhanden)
              if (_selectedMediaFiles.isNotEmpty) ...[
                SizedBox(height: 16),
                _buildSelectedMediaFiles(),
              ],
              
              // Simulierte Media-Dateien (wenn vorhanden)
              if (_simulatedMediaFiles.isNotEmpty) ...[
                SizedBox(height: 16),
                _buildSimulatedMediaFiles(),
              ],
            ],
          ),
        ),
        
        // Mikrofon-Animation (unten)
        if (isListening) _buildMicrophoneAnimation(),
      ],
    );
  }

  Widget _buildMicrophoneAnimation() {
    return Expanded(
      child: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Pulsing Ring Animation
            if (isListening)
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  double baseSize = isLargeMode ? 280 : 200;
                  double pulseSize = isLargeMode ? 70 : 50;
                  return Container(
                    width: baseSize + (_pulseController.value * pulseSize),
                    height: baseSize + (_pulseController.value * pulseSize),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.teal[400]!.withOpacity(0.3 - (_pulseController.value * 0.3)),
                      border: Border.all(
                        color: Colors.teal[400]!.withOpacity(0.6 - (_pulseController.value * 0.6)),
                        width: isLargeMode ? 3 : 2,
                      ),
                    ),
                  );
                },
              ),
            // Zweiter Pulsing Ring
            if (isListening)
              AnimatedBuilder(
                animation: _pulseController2,
                builder: (context, child) {
                  double baseSize = isLargeMode ? 280 : 200;
                  double pulseSize = isLargeMode ? 70 : 50;
                  return Container(
                    width: baseSize + ((_pulseController2.value + 0.5) * pulseSize),
                    height: baseSize + ((_pulseController2.value + 0.5) * pulseSize),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.teal[400]!.withOpacity(0.2 - (_pulseController2.value * 0.2)),
                      border: Border.all(
                        color: Colors.teal[400]!.withOpacity(0.4 - (_pulseController2.value * 0.4)),
                        width: isLargeMode ? 2 : 1,
                      ),
                    ),
                  );
                },
              ),
            // Mikrofon-Button
            GestureDetector(
              onTap: _stopListening,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.red[400],
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red[400]!.withOpacity(0.4),
                      blurRadius: isLargeMode ? 25 : 15,
                      spreadRadius: isLargeMode ? 8 : 5,
                    ),
                  ],
                ),
                padding: EdgeInsets.all(isLargeMode ? 60 : 40),
                child: Icon(
                  Icons.mic,
                  color: Colors.white,
                  size: isLargeMode ? 72 : 48,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildMainInterface() {
    return Center(
      child: GestureDetector(
        onTap: startMicrophonePost,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Hauptmikrofon-Container - größer
            Container(
              decoration: BoxDecoration(
                color: Colors.teal[400],
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.teal[400]!.withOpacity(0.3),
                    blurRadius: isLargeMode ? 20 : 15,
                    spreadRadius: isLargeMode ? 5 : 3,
                  ),
                ],
              ),
              padding: EdgeInsets.all(isLargeMode ? 60 : 40),
              child: Icon(
                Icons.mic_none,
                color: Colors.white,
                size: isLargeMode ? 72 : 48,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryDetailView() {
    if (selectedEntry == null) return SizedBox.shrink();
    
    final time = selectedEntry!['timestamp'] as DateTime;
    final hasMedia = selectedEntry!['media_files'] != null && (selectedEntry!['media_files'] as List).isNotEmpty;
    
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Header mit Zurück-Button
          Container(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: closeEntryDetail,
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.arrow_back, size: 24, color: Colors.grey[700]),
                  ),
                ),
                SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Beitrag Details',
                        style: TextStyle(
                          fontSize: isLargeMode ? 24 : 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[800],
                        ),
                      ),
                      Text(
                        '${time.day}.${time.month}.${time.year} um ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: isLargeMode ? 16 : 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // Lösch-Button
                GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: Text(
                            'Eintrag löschen?',
                            style: TextStyle(
                              fontSize: isLargeMode ? 20 : 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          content: Text(
                            'Möchten Sie diesen Eintrag wirklich löschen? Diese Aktion kann nicht rückgängig gemacht werden.',
                            style: TextStyle(
                              fontSize: isLargeMode ? 16 : 14,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: isLargeMode ? 16 : 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop();
                                deleteMemory(selectedEntry!['id']);
                                closeEntryDetail();
                              },
                              child: Text(
                                'Delete',
                                style: TextStyle(
                                  fontSize: isLargeMode ? 16 : 14,
                                  color: Colors.red[600],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.delete_outline,
                      color: Colors.red[600],
                      size: isLargeMode ? 24 : 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Inhalt
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titel
                  if (selectedEntry!['title'] != null && selectedEntry!['title'].toString().isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.teal[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal[200]!, width: 1),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              selectedEntry!['title'],
                              style: TextStyle(
                                fontSize: isLargeMode ? 22 : 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal[800],
                              ),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.only(left: 12),
                            child: _buildAISymbol(size: isLargeMode ? 24 : 20),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                  ],
                  
                  // Inhalt
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Text(
                      selectedEntry!['content'],
                      style: TextStyle(
                        fontSize: isLargeMode ? 18 : 16,
                        color: Colors.grey[800],
                        height: 1.5,
                      ),
                    ),
                  ),
                  
                  // Like-Indikator
                  if (selectedEntry!['id'] != null && memoryLikeCounts.containsKey(selectedEntry!['id']) && memoryLikeCounts[selectedEntry!['id']]! > 0) ...[
                    SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red[200]!, width: 1),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.favorite,
                            size: isLargeMode ? 24 : 20,
                            color: Colors.red[500],
                          ),
                          SizedBox(width: 12),
                          Text(
                            '${memoryLikeCounts[selectedEntry!['id']]} family member${memoryLikeCounts[selectedEntry!['id']] == 1 ? '' : 's'} liked this memory',
                            style: TextStyle(
                              fontSize: isLargeMode ? 16 : 14,
                              color: Colors.red[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  
                  // Media-Anhänge
                  if (hasMedia) ...[
                    SizedBox(height: 20),
                    Text(
                      'Anhänge:',
                      style: TextStyle(
                        fontSize: isLargeMode ? 20 : 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    SizedBox(height: 12),
                    ...(selectedEntry!['media_files'] as List).map<Widget>((media) {
                      return Container(
                        margin: EdgeInsets.only(bottom: 12),
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _getMediaColor(media['file_type']).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _getMediaIcon(media['file_type']),
                                size: isLargeMode ? 32 : 28,
                                color: _getMediaColor(media['file_type']),
                              ),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    media['filename'],
                                    style: TextStyle(
                                      fontSize: isLargeMode ? 16 : 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey[800],
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    _getMediaTypeDescription(media['file_type']),
                                    style: TextStyle(
                                      fontSize: isLargeMode ? 14 : 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (media['duration'] != null) ...[
                                    SizedBox(height: 4),
                                    Text(
                                      'Dauer: ${_formatDuration(media['duration'])}',
                                      style: TextStyle(
                                        fontSize: isLargeMode ? 12 : 10,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Icon(
                              Icons.download,
                              size: isLargeMode ? 24 : 20,
                              color: Colors.grey[400],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getMediaTypeDescription(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'image':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'audio':
        return 'Voice Message';
      default:
        return 'File';
    }
  }

  Widget _buildMainInterfaceWithKeyboard() {
    return Stack(
      children: [
        // Hauptmikrofon-Button (zentriert)
        Center(
          child: GestureDetector(
            onTap: startMicrophonePost,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Hauptmikrofon-Container - größer
                Container(
                  decoration: BoxDecoration(
                    color: Colors.teal[400],
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.teal[400]!.withOpacity(0.3),
                        blurRadius: isLargeMode ? 20 : 15,
                        spreadRadius: isLargeMode ? 5 : 3,
                      ),
                    ],
                  ),
                  padding: EdgeInsets.all(isLargeMode ? 60 : 40),
                  child: Icon(
                    Icons.mic_none,
                    color: Colors.white,
                    size: isLargeMode ? 72 : 48,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        // Tastatur-Icon - rechts positioniert
        Positioned(
          right: 40,
          top: MediaQuery.of(context).size.height * 0.5 - 40,
          child: GestureDetector(
            onTap: () {
              setState(() {
                showPostEditor = true;
              });
            },
            child: Container(
              padding: EdgeInsets.all(isLargeMode ? 16 : 12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: isLargeMode ? 8 : 6,
                    spreadRadius: isLargeMode ? 2 : 1,
                  ),
                ],
              ),
              child: Icon(
                Icons.keyboard_alt,
                size: isLargeMode ? 48 : 36,
                color: Colors.grey[700],
              ),
            ),
          ),
        ),
        
        // Untere Navigationsleiste
        _buildBottomNavigation(),
      ],
    );
  }

  Widget _buildExpandedMediaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Media auswählen:',
          style: TextStyle(
            fontSize: isLargeMode ? 16 : 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 12),
        // Media-Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Foto aus Galerie
            GestureDetector(
              onTap: _simulatePhotoCapture,
              child: Container(
                padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                decoration: BoxDecoration(
                  color: Colors.blue[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(Icons.photo_library, size: isLargeMode ? 32 : 24, color: Colors.blue[600]),
                    SizedBox(height: 4),
                    Text('Photo', style: TextStyle(fontSize: isLargeMode ? 14 : 12, color: Colors.blue[600])),
                  ],
                ),
              ),
            ),
            // Video aus Galerie
            GestureDetector(
              onTap: _simulateVideoCapture,
              child: Container(
                padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                decoration: BoxDecoration(
                  color: Colors.purple[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(Icons.video_library, size: isLargeMode ? 32 : 24, color: Colors.purple[600]),
                    SizedBox(height: 4),
                    Text('Video', style: TextStyle(fontSize: isLargeMode ? 14 : 12, color: Colors.purple[600])),
                  ],
                ),
              ),
            ),
            // Sprachnachricht
            GestureDetector(
              onTap: _isRecording ? _stopRecording : _startRecording,
              child: Container(
                padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                decoration: BoxDecoration(
                  color: _isRecording ? Colors.red[100] : Colors.green[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      size: isLargeMode ? 32 : 24,
                      color: _isRecording ? Colors.red[600] : Colors.green[600],
                    ),
                    SizedBox(height: 4),
                    Text(
                      _isRecording ? 'Stop' : 'Audio',
                      style: TextStyle(
                        fontSize: isLargeMode ? 14 : 12,
                        color: _isRecording ? Colors.red[600] : Colors.green[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectedMediaFiles() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Angehängte Dateien:',
          style: TextStyle(
            fontSize: isLargeMode ? 16 : 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _selectedMediaFiles.asMap().entries.map((entry) {
            final index = entry.key;
            final mediaFile = entry.value;
            return Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _getMediaColor(mediaFile.fileType).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _getMediaColor(mediaFile.fileType).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getMediaIcon(mediaFile.fileType),
                    size: isLargeMode ? 20 : 16,
                    color: _getMediaColor(mediaFile.fileType),
                  ),
                  SizedBox(width: 6),
                  Text(
                    mediaFile.filename,
                    style: TextStyle(
                      fontSize: isLargeMode ? 14 : 12,
                      color: _getMediaColor(mediaFile.fileType),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _removeMediaFile(index),
                    child: Icon(
                      Icons.close,
                      size: isLargeMode ? 18 : 14,
                      color: Colors.red[600],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSimulatedMediaFiles() {
    if (_simulatedMediaFiles.isEmpty) return SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Simulierte Anhänge:',
          style: TextStyle(
            fontSize: isLargeMode ? 16 : 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _simulatedMediaFiles.asMap().entries.map((entry) {
            final index = entry.key;
            final mediaFile = entry.value;
            return Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _getMediaColor(mediaFile['file_type']).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _getMediaColor(mediaFile['file_type']).withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getMediaIcon(mediaFile['file_type']),
                    size: isLargeMode ? 20 : 16,
                    color: _getMediaColor(mediaFile['file_type']),
                  ),
                  SizedBox(width: 6),
                  Text(
                    mediaFile['filename'],
                    style: TextStyle(
                      fontSize: isLargeMode ? 14 : 12,
                      color: _getMediaColor(mediaFile['file_type']),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (mediaFile['duration'] != null) ...[
                    SizedBox(width: 4),
                    Text(
                      '(${_formatDuration(mediaFile['duration'])})',
                      style: TextStyle(
                        fontSize: isLargeMode ? 12 : 10,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                  SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _removeSimulatedMediaFile(index),
                    child: Icon(
                      Icons.close,
                      size: isLargeMode ? 18 : 14,
                      color: Colors.red[600],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _removeSimulatedMediaFile(int index) {
    setState(() {
      _simulatedMediaFiles.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    print('Build called - hasSelectedUserType: $hasSelectedUserType, isFamilyView: $isFamilyView, isOmaView: $isOmaView');
    return Scaffold(
      body: Stack(
        children: [
          // Hauptinhalt
          if (!hasSelectedUserType)
            _buildUserTypeSelection()
          else if (isLifeChaptersView)
            _buildLifeChaptersView()
          else if (isFamilyMembersView)
            _buildFamilyMembersView()
          else if (isFamilyView)
            _buildFamilyView()
          else if (isOmaView)
            _buildOmaView()
          else if (showDailySummariesList)
            _buildDailySummariesListView()
          else if (showChatView)
            _buildChatView()
          else if (showDailySummary)
            _buildDailySummaryView()
          else if (showSeamlessScrollView)
            _buildSeamlessScrollView()
          else ...[
          // App Name oben mittig
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Memory Keeper',
                style: TextStyle(
                    fontSize: isLargeMode ? 32 : 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal[400],
                ),
              ),
            ),
          ),

            // Home Button oben links - führt zurück zur Startseite
          Positioned(
            top: 40,
            left: 20,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    hasSelectedUserType = false;
                    isFamilyView = false;
                    isOmaView = false;
                    isLifeChaptersView = false; // Ensure life chapters view is off
                isFamilyMembersView = false; // Ensure family members view is off
                    isFamilyMembersView = false; // Ensure family members view is off
                    previousView = null; // Reset previous view
                    isHistoryView = false;
                    showDetailView = false;
                    showDailySummary = false;
                    showPostEditor = false;
                    showSeamlessScrollView = false;
                    showDailySummariesList = false;
                    showChatView = false;
                    seamlessScrollStartDay = null;
                    hasScrolledToStartDay = false;
                  });
                },
                child: Container(
                  padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: isLargeMode ? 12 : 8,
                        spreadRadius: isLargeMode ? 3 : 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.home,
                    size: isLargeMode ? 40 : 32,
                    color: Colors.teal[400],
                  ),
                ),
              ),
            ),

            // Fragenvorschläge zwischen Überschrift und Mikrofon (mittig)
            if (!isHistoryView && !showPostEditor)
              Positioned(
                top: MediaQuery.of(context).size.height * 0.3, // 30% von oben - zwischen Titel und Mikrofon
                left: 0,
                right: 0,
                child: _buildQuestionSuggestions(),
              ),

            // History Icon oben rechts - größer (nur in normaler Ansicht)
            if (!isHistoryView)
              Positioned(
                top: 40,
                right: 20,
            child: GestureDetector(
              onTap: toggleHistory,
                  child: Container(
                    padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: isLargeMode ? 12 : 8,
                          spreadRadius: isLargeMode ? 3 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.calendar_month, 
                      size: isLargeMode ? 40 : 32, 
                      color: Colors.teal[400]
                    ),
                  ),
                ),
              ),

            // Streak-Anzeige zwischen Home-Button und App-Titel (nur in normaler Ansicht)
            if (!isHistoryView)
            Positioned(
                top: 40,
                left: 100, // Rechts vom Home-Button
                child: Container(
                  height: isLargeMode ? 64 : 56, // Gleiche Höhe wie Home-Button
                  padding: EdgeInsets.symmetric(horizontal: isLargeMode ? 16 : 12, vertical: isLargeMode ? 8 : 6),
                  decoration: BoxDecoration(
                    color: Colors.orange[100],
                    borderRadius: BorderRadius.circular(isLargeMode ? 32 : 28), // Kreisförmig wie Home-Button
                    border: Border.all(color: Colors.orange[300]!, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.orange[200]!,
                        blurRadius: isLargeMode ? 12 : 8,
                        spreadRadius: isLargeMode ? 3 : 2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        size: isLargeMode ? 24 : 20,
                        color: Colors.orange[600],
                      ),
                      SizedBox(width: 6),
                      Text(
                        '$currentStreak',
                        style: TextStyle(
                          fontSize: isLargeMode ? 18 : 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[800],
                        ),
                      ),
                      SizedBox(width: 2),
                      Text(
                        'Days',
                        style: TextStyle(
                          fontSize: isLargeMode ? 14 : 12,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ),


            // History View - Kalender oder Tagesansicht
            if (isHistoryView)
              _buildHistoryView(),

            // Detail-Ansicht (kann sowohl in Historie als auch außerhalb angezeigt werden)
            if (showDetailView)
              _buildEntryDetailView(),
            
            
            // Post-Editor oder Hauptmikrofon-Button (nur außerhalb der Historie)
            if (!isHistoryView && !showDetailView && !showDailySummary)
              showPostEditor 
                ? _buildPostEditor() 
                : _buildMainInterfaceWithKeyboard(),


            // Alte Speech-to-Text Oberfläche (entfernt - wird durch Post-Editor ersetzt)
            if (false && !isHistoryView)
              Positioned(
              bottom: 100,
              left: 20,
              right: 20,
              child: GestureDetector(
                onTap: _stopListening,
                child: Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 15,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
              child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                      Row(
                        children: [
                          if (isListening) ...[
                            Icon(Icons.mic, color: Colors.blue[600], size: 24),
                            SizedBox(width: 10),
                            Text(
                              'Listening...',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[600],
                              ),
                            ),
                            Spacer(),
                GestureDetector(
                            onTap: _stopListening,
                    child: Container(
                              padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                        shape: BoxShape.circle,
                      ),
                              child: Icon(Icons.stop, color: Colors.grey[600], size: 32),
                            ),
                          ),
                          ] else ...[
                            Icon(Icons.edit, color: Colors.grey[600], size: 24),
                            SizedBox(width: 10),
                            Text(
                              'Edit Text',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[600],
                              ),
                            ),
                            Spacer(),
                GestureDetector(
                              onTap: _cancelPost,
                              child: Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.close, color: Colors.grey[600], size: 32),
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: 15),
                      // Titel-Eingabe
                      TextField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          hintText: 'Titel (optional)...',
                          border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.teal[400]!),
                          ),
                        ),
                        style: TextStyle(fontSize: isLargeMode ? 18 : 16),
                      ),
                      SizedBox(height: 15),
                      // Text-Eingabe
                      TextField(
                        controller: _speechController,
                        maxLines: 3,
                        onTap: () {
                          // Stoppt das Zuhören wenn in das Textfeld getippt wird
                          if (isListening) {
                            _stopListening();
                          }
                        },
                        decoration: InputDecoration(
                          hintText: 'Gesprochener Text erscheint hier...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.teal[400]!),
                          ),
                        ),
                        style: TextStyle(fontSize: isLargeMode ? 18 : 16),
                      ),
                      SizedBox(height: 15),
                      // Media-Anhänge (entfernt - wird durch neue Struktur ersetzt)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _cancelPost,
                            icon: Icon(Icons.close, size: 28),
                            label: Text('Cancel', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[300],
                              foregroundColor: Colors.grey[700],
                              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                              minimumSize: Size(160, 68),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _sendPost,
                            icon: Icon(Icons.send, size: 28),
                            label: Text('Send', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal[400],
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                              minimumSize: Size(160, 68),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Altes Pop-up Textfeld (entfernt - wird durch Post-Editor ersetzt)
            if (false && !isHistoryView)
          Center(
                child: Container(
                  width: 600,
                  padding: EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 20,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
            child: Row(
              children: [
                      // Kleines Mikrofon-Icon links
                GestureDetector(
                        onTap: () {
                          // Text aus dem Textfeld in die Speech-Textbubble übertragen
                          if (_controller.text.isNotEmpty) {
                            _speechController.text = _controller.text;
                            _recognizedText = _controller.text;
                          }
                          // Schließt das Textfeld und startet Speech-to-Text
                          setState(() {
                            showPostEditor = true;
                            isListening = true;
                            _pulseController.repeat();
                            Future.delayed(Duration(milliseconds: 500), () {
                              if (isListening) {
                                _pulseController2.repeat();
                              }
                            });
                            _simulateListening();
                          });
                    },
                    child: Container(
                          padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                            color: Colors.grey[300],
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.mic,
                            color: Colors.grey[600],
                            size: 40,
                    ),
                  ),
                ),
                SizedBox(width: 20),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          style: TextStyle(fontSize: 22),
                          decoration: InputDecoration(
                            hintText: 'Neue Erinnerung...',
                            hintStyle: TextStyle(fontSize: 22, color: Colors.grey[500]),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      SizedBox(width: 12),
                GestureDetector(
                        onTap: () {
                          addMemory(_speechController.text);
                          _cancelPost();
                        },
                        child: Container(
                          padding: EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.teal[400],
                            shape: BoxShape.circle,
                          ),
                  child: Icon(
                            Icons.send,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          
          // Lupe Icon - funktioniert nur auf Einstiegsscreen und Hauptseite (nicht auf anderen Seiten)
          if (!isFamilyView && !isOmaView && !isLifeChaptersView && !isFamilyMembersView && !showSeamlessScrollView && !showChatView && !showDailySummariesList)
            Positioned(
              bottom: 40,
              right: 20,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    isLargeMode = !isLargeMode;
                  });
                },
                child: Container(
                  padding: EdgeInsets.all(isLargeMode ? 20 : 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: isLargeMode ? 12 : 8,
                        spreadRadius: isLargeMode ? 3 : 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    isLargeMode ? Icons.zoom_out : Icons.zoom_in,
                    size: isLargeMode ? 40 : 32,
                    color: Colors.grey[600],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuestionSuggestions() {
    if (questions.isEmpty) {
      return SizedBox.shrink();
    }

    // Zeige nur 1 zufällige Frage
    final shuffledQuestions = List<Question>.from(questions)..shuffle();
    final randomQuestion = shuffledQuestions.first;

    return Container(
      height: 100,
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          padding: EdgeInsets.all(20),
          child: GestureDetector(
            onTap: () {
              // Frage in den Post-Editor übertragen
              _speechController.text = randomQuestion.questionText;
              setState(() {
                showPostEditor = true;
              });
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildAISymbol(size: isLargeMode ? 20 : 16),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    randomQuestion.questionText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isLargeMode ? 24 : 16,
                    color: Colors.grey[700],
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Apple-ähnliche Benutzertyp-Auswahl
  Widget _buildUserTypeSelection() {
    return Container(
      color: Colors.grey[50],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App Name oben mittig
            Text(
              'Memory Keeper',
              style: TextStyle(
                fontSize: isLargeMode ? 40 : 32,
                fontWeight: FontWeight.bold,
                color: Colors.teal[400],
                letterSpacing: 0.5,
              ),
            ),
            
            SizedBox(height: isLargeMode ? 80 : 60),
            
            // Untertitel
            Text(
              'Choose your role',
              style: TextStyle(
                fontSize: isLargeMode ? 24 : 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w400,
              ),
            ),
            
            SizedBox(height: isLargeMode ? 100 : 80),
            
            // Zwei Blasen zur Auswahl - deutlich größer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
              // Linke Blase - Eingabende Person
              GestureDetector(
                onTap: () {
                  setState(() {
                    hasSelectedUserType = true;
                    isFamilyView = false;
                    isOmaView = false;
                    isLifeChaptersView = false; // Ensure life chapters view is off
                isFamilyMembersView = false; // Ensure family members view is off
                    isFamilyMembersView = false; // Ensure family members view is off
                    previousView = null; // Reset previous view
                  });
                    },
                    child: Container(
                    width: isLargeMode ? 200 : 160,
                    height: isLargeMode ? 200 : 160,
                      decoration: BoxDecoration(
                        color: Colors.teal[400],
                        shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.teal[400]!.withOpacity(0.3),
                          blurRadius: isLargeMode ? 30 : 20,
                          spreadRadius: isLargeMode ? 8 : 5,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.elderly,
                          size: isLargeMode ? 80 : 64,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
                
              // Rechte Blase - Familienangehörige
              GestureDetector(
                onTap: () {
                  setState(() {
                    hasSelectedUserType = true;
                    isFamilyView = true;
                    hasVisitedFamilyView = true;
                    // Markiere alle aktuellen Memories als "gesehen" nach kurzer Zeit
                    Future.delayed(Duration(seconds: 2), () {
                      if (mounted) {
                        setState(() {
                          _markAllMemoriesAsViewed();
                        });
                      }
                    });
                  });
                },
                  child: Container(
                    width: isLargeMode ? 200 : 160,
                    height: isLargeMode ? 200 : 160,
                    decoration: BoxDecoration(
                      color: Colors.blue[400],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue[400]!.withOpacity(0.3),
                          blurRadius: isLargeMode ? 30 : 20,
                          spreadRadius: isLargeMode ? 8 : 5,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.family_restroom,
                          size: isLargeMode ? 80 : 64,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Familienmitglieder-Ansicht
  Widget _buildFamilyView() {
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Header mit Home-Button
          Container(
            padding: EdgeInsets.only(top: 40, left: 20, right: 20, bottom: 20),
            child: Row(
              children: [
                // Home Button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      hasSelectedUserType = false;
                      isFamilyView = false;
                      isOmaView = false;
                    isLifeChaptersView = false; // Ensure life chapters view is off
                isFamilyMembersView = false; // Ensure family members view is off
                    isFamilyMembersView = false; // Ensure family members view is off
                    previousView = null; // Reset previous view
                      // Markiere alle aktuellen Memories als "gesehen" beim Verlassen
                      _markAllMemoriesAsViewed();
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: isLargeMode ? 12 : 8,
                          spreadRadius: isLargeMode ? 3 : 2,
                        ),
                      ],
                    ),
                      child: Icon(
                      Icons.home,
                      size: isLargeMode ? 40 : 32,
                      color: Colors.teal[400],
                    ),
                  ),
                ),
                SizedBox(width: 20),
                // Titel
                Expanded(
                  child: Text(
                    'Family Members',
                    style: TextStyle(
                      fontSize: isLargeMode ? 32 : 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[400],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Familienmitglieder-Grid
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Oma
                  InkWell(
                    onTap: () {
                      print('Oma button clicked!');
                      setState(() {
                        isFamilyView = false;
                        isOmaView = true;
                    isLifeChaptersView = false; // Ensure life chapters view is off
                isFamilyMembersView = false; // Ensure family members view is off
                    isFamilyMembersView = false; // Ensure family members view is off
                    previousView = null; // Reset previous view
                      });
                      print('isFamilyView set to: $isFamilyView, isOmaView set to: $isOmaView');
                    },
                    borderRadius: BorderRadius.circular(isLargeMode ? 100 : 80),
                    child: Container(
                      width: isLargeMode ? 200 : 160,
                      height: isLargeMode ? 200 : 160,
                      margin: EdgeInsets.only(bottom: 40),
                      decoration: BoxDecoration(
                        color: Colors.pink[100],
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.pink[200]!,
                            blurRadius: isLargeMode ? 20 : 15,
                            spreadRadius: isLargeMode ? 5 : 3,
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Haupt-Icon
                          Center(
                            child: Icon(
                              Icons.elderly_woman,
                              size: isLargeMode ? 80 : 64,
                              color: Colors.pink[600],
                            ),
                          ),
                          // Benachrichtigungs-Badge (wie iPhone)
                          Positioned(
                            top: isLargeMode ? 20 : 16,
                            right: isLargeMode ? 20 : 16,
                            child: Container(
                              width: isLargeMode ? 24 : 20,
                              height: isLargeMode ? 24 : 20,
                              decoration: BoxDecoration(
                                color: Colors.red[500],
                                shape: BoxShape.circle,
                                border: Border.all(
                        color: Colors.white,
                                  width: isLargeMode ? 3 : 2,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '3',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: isLargeMode ? 12 : 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Opa
                  GestureDetector(
                    onTap: () {
                      // TODO: Opa-Seite implementieren
                      print('Opa - Coming Soon');
                    },
                    child: Container(
                      width: isLargeMode ? 200 : 160,
                      height: isLargeMode ? 200 : 160,
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue[200]!,
                            blurRadius: isLargeMode ? 20 : 15,
                            spreadRadius: isLargeMode ? 5 : 3,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Icon(
                          Icons.elderly,
                          size: isLargeMode ? 80 : 64,
                          color: Colors.blue[600],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Hilfsfunktionen für Datum/Zeit-Formatierung
  String _formatDateForFamily(DateTime? createdAt) {
    if (createdAt == null) return 'Recent';
    
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    
    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${createdAt.day}/${createdAt.month}';
    }
  }

  String _formatTimeForFamily(DateTime? createdAt) {
    if (createdAt == null) return '';
    return '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
  }

  // Markiert alle aktuellen Memories als "gesehen"
  void _markAllMemoriesAsViewed() {
    for (final memory in memories) {
      if (memory.id != null) {
        viewedMemoryIds.add(memory.id!);
      }
    }
  }

  void _toggleLike(int memoryId) async {
    try {
      final response = await http.post(
        Uri.parse('${apiUrl.replaceAll('/memories', '')}/likes'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'memory_id': memoryId,
          'user_type': 'family_member'
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          if (data['is_liked']) {
            likedMemories.add(memoryId);
          } else {
            likedMemories.remove(memoryId);
          }
          memoryLikeCounts[memoryId] = data['like_count'];
        });
      }
    } catch (e) {
      print('Error toggling like: $e');
    }
  }

  // Like-Status für alle Memories laden
  Future<void> _loadLikes() async {
    try {
      final response = await http.get(
        Uri.parse('${apiUrl.replaceAll('/memories', '')}/likes/user/family_member'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          likedMemories = Set<int>.from(data['liked_memory_ids']);
        });
      }
    } catch (e) {
      print('Error loading likes: $e');
    }
  }

  // Like-Counts für alle Memories laden
  Future<void> _loadLikeCounts() async {
    try {
      for (final memory in memories) {
        if (memory.id != null) {
          final response = await http.get(
            Uri.parse('${apiUrl.replaceAll('/memories', '')}/likes/${memory.id}'),
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            setState(() {
              memoryLikeCounts[memory.id!] = data['like_count'];
            });
          }
        }
      }
    } catch (e) {
      print('Error loading like counts: $e');
    }
  }

  // Angehörige der Eingabenden Person - Ansicht
  Widget _buildFamilyMembersView() {
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Header mit Navigation
          Container(
            padding: EdgeInsets.only(top: 40, left: 20, right: 20, bottom: 20),
            child: Row(
              children: [
                // Home Button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      hasSelectedUserType = false;
                      isFamilyView = false;
                      isOmaView = false;
                      isLifeChaptersView = false;
                      isFamilyMembersView = false;
                      previousView = null;
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: isLargeMode ? 12 : 8,
                          spreadRadius: isLargeMode ? 3 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.home,
                      size: isLargeMode ? 40 : 32,
                      color: Colors.teal[400],
                    ),
                  ),
                ),
                SizedBox(width: 20),
                // Zurück-Button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      isFamilyMembersView = false;
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: isLargeMode ? 12 : 8,
                          spreadRadius: isLargeMode ? 3 : 2,
                        ),
                      ],
                    ),
                  child: Icon(
                      Icons.arrow_back,
                      size: isLargeMode ? 40 : 32,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                SizedBox(width: 20),
                // Titel
                Expanded(
                  child: Text(
                    'My Family',
                    style: TextStyle(
                      fontSize: isLargeMode ? 32 : 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.green[400],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Angehörige-Grid
          Expanded(
            child: GridView.builder(
              padding: EdgeInsets.symmetric(horizontal: 20),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.0,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: familyMembers.length,
              itemBuilder: (context, index) {
                final member = familyMembers[index];
                final hasNewContent = member['hasNewContent'] as bool;
                
                return GestureDetector(
                  onTap: () {
                    // TODO: Einzelne Angehörige-Seite implementieren
                    print('${member['name']} - Coming Soon');
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: hasNewContent ? member['color'] as Color : Colors.grey[300]!,
                        width: hasNewContent ? 3 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: hasNewContent 
                              ? (member['color'] as Color).withOpacity(0.2)
                              : Colors.black.withOpacity(0.05),
                          blurRadius: hasNewContent ? 15 : 8,
                          spreadRadius: hasNewContent ? 2 : 1,
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Hauptinhalt
            Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Icon
                              Container(
                                width: isLargeMode ? 60 : 50,
                                height: isLargeMode ? 60 : 50,
                                decoration: BoxDecoration(
                                  color: (member['color'] as Color).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  member['icon'] as IconData,
                                  size: isLargeMode ? 30 : 24,
                                  color: member['color'] as Color,
                                ),
                              ),
                              SizedBox(height: 12),
                              // Name
                              Text(
                                member['name'] as String,
                                style: TextStyle(
                                  fontSize: isLargeMode ? 18 : 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              SizedBox(height: 4),
                              // Relation
                              Text(
                                member['relation'] as String,
                                style: TextStyle(
                                  fontSize: isLargeMode ? 14 : 12,
                                  color: Colors.grey[600],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        // Benachrichtigungs-Badge (wie iPhone)
                        if (hasNewContent)
                          Positioned(
                            top: 8,
                            right: 8,
              child: Container(
                              width: isLargeMode ? 20 : 16,
                              height: isLargeMode ? 20 : 16,
                              decoration: BoxDecoration(
                                color: Colors.red[500],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: isLargeMode ? 2 : 1,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Kapitel des Lebens - Ansicht
  Widget _buildLifeChaptersView() {
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Header mit Navigation
          Container(
            padding: EdgeInsets.only(top: 40, left: 20, right: 20, bottom: 20),
            child: Row(
              children: [
                // Home Button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      hasSelectedUserType = false;
                      isFamilyView = false;
                      isOmaView = false;
                      isLifeChaptersView = false;
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: isLargeMode ? 12 : 8,
                          spreadRadius: isLargeMode ? 3 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.home,
                      size: isLargeMode ? 40 : 32,
                      color: Colors.teal[400],
                    ),
                  ),
                ),
                SizedBox(width: 20),
                // Zurück-Button (nur wenn nicht von Startseite)
                if (hasSelectedUserType)
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        isLifeChaptersView = false;
                        // Return to the previous view
                        if (previousView == 'oma') {
                          isOmaView = true;
                        } else if (previousView == 'main') {
                          // Stay on main page (default state)
                        }
                        previousView = null; // Reset previous view
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: isLargeMode ? 12 : 8,
                            spreadRadius: isLargeMode ? 3 : 2,
                          ),
                        ],
                      ),
                  child: Icon(
                        Icons.arrow_back,
                        size: isLargeMode ? 40 : 32,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                if (hasSelectedUserType) SizedBox(width: 20),
                // Titel
                Expanded(
                  child: Text(
                    'Life Chapters',
                    style: TextStyle(
                      fontSize: isLargeMode ? 32 : 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[400],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Lebensabschnitte-Liste
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: 20),
              itemCount: lifeChapters.length,
              itemBuilder: (context, index) {
                final chapter = lifeChapters[index];
                final isCompleted = chapter['completed'] as bool;
                
                return Container(
                  margin: EdgeInsets.only(bottom: 16),
              child: Container(
                    padding: EdgeInsets.all(isLargeMode ? 24 : 20),
                    decoration: BoxDecoration(
                      color: isCompleted ? Colors.white : Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isCompleted ? chapter['color'] as Color : Colors.grey[300]!,
                        width: isCompleted ? 3 : 1,
                      ),
                  boxShadow: [
                    BoxShadow(
                          color: isCompleted 
                              ? (chapter['color'] as Color).withOpacity(0.2)
                              : Colors.black.withOpacity(0.05),
                          blurRadius: isCompleted ? 15 : 8,
                          spreadRadius: isCompleted ? 2 : 1,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Icon
                        Container(
                          width: isLargeMode ? 60 : 50,
                          height: isLargeMode ? 60 : 50,
                          decoration: BoxDecoration(
                            color: isCompleted 
                                ? (chapter['color'] as Color).withOpacity(0.1)
                                : Colors.grey[200],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            chapter['icon'] as IconData,
                            size: isLargeMode ? 30 : 24,
                            color: isCompleted 
                                ? chapter['color'] as Color
                                : Colors.grey[500],
                          ),
                        ),
                        SizedBox(width: 16),
                        // Text
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                chapter['title'] as String,
                                style: TextStyle(
                                  fontSize: isLargeMode ? 20 : 18,
                                  fontWeight: FontWeight.bold,
                                  color: isCompleted ? Colors.grey[800] : Colors.grey[500],
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                chapter['subtitle'] as String,
                                style: TextStyle(
                                  fontSize: isLargeMode ? 16 : 14,
                                  color: isCompleted ? Colors.grey[600] : Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Status
                        if (isCompleted)
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: chapter['color'] as Color,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check,
                              color: Colors.white,
                              size: isLargeMode ? 20 : 16,
                            ),
                          )
                        else
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.lock,
                              color: Colors.grey[500],
                              size: isLargeMode ? 20 : 16,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Seamless Scroll-Ansicht für alle Posts
  Widget _buildSeamlessScrollView() {
    // Gruppiere Memories nach Tagen
    Map<String, List<Memory>> memoriesByDay = {};
    for (final memory in memories) {
      if (memory.createdAt != null) {
        final dayKey = '${memory.createdAt!.year}-${memory.createdAt!.month.toString().padLeft(2, '0')}-${memory.createdAt!.day.toString().padLeft(2, '0')}';
        if (!memoriesByDay.containsKey(dayKey)) {
          memoriesByDay[dayKey] = [];
        }
        memoriesByDay[dayKey]!.add(memory);
      }
    }

    // Sortiere Tage (neueste zuerst)
    final sortedDays = memoriesByDay.keys.toList()..sort((a, b) => b.compareTo(a));
    
    // Finde den Index des Start-Tages
    int startIndex = 0;
    if (seamlessScrollStartDay != null) {
      final startDayKey = '${seamlessScrollStartDay!.year}-${seamlessScrollStartDay!.month.toString().padLeft(2, '0')}-${seamlessScrollStartDay!.day.toString().padLeft(2, '0')}';
      startIndex = sortedDays.indexOf(startDayKey);
      if (startIndex == -1) startIndex = 0; // Fallback falls Tag nicht gefunden
    }
    
    // Scroll zum Start-Tag nur einmal nach dem ersten Build
    if (!hasScrolledToStartDay && seamlessScrollStartDay != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (seamlessScrollController != null && seamlessScrollController!.hasClients) {
          // Schätze die Höhe pro Tag (ca. 200px pro Tag + 24px Abstand)
          final estimatedHeightPerDay = 224.0;
          final targetOffset = startIndex * estimatedHeightPerDay;
          seamlessScrollController!.animateTo(
            targetOffset,
            duration: Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
          hasScrolledToStartDay = true; // Markiere als gescrollt
        }
      });
    }

    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Header mit Navigation
          Container(
            padding: EdgeInsets.only(top: 40, left: 20, right: 20, bottom: 20),
            child: Row(
              children: [
                // Zurück-Button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      showSeamlessScrollView = false;
                      showDetailView = false;
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: isLargeMode ? 12 : 8,
                          spreadRadius: isLargeMode ? 3 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.arrow_back,
                      size: isLargeMode ? 40 : 32,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
                SizedBox(width: 20),
                // Titel
                Expanded(
                  child: Text(
                    'All Memories',
                    style: TextStyle(
                      fontSize: isLargeMode ? 32 : 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[400],
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Seamless Scroll-Liste
          Expanded(
            child: ListView.builder(
              controller: seamlessScrollController,
              padding: EdgeInsets.symmetric(horizontal: 20),
              itemCount: sortedDays.length,
              itemBuilder: (context, dayIndex) {
                final dayKey = sortedDays[dayIndex];
                final dayMemories = memoriesByDay[dayKey]!;
                final dayDate = DateTime.parse(dayKey);
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tages-Header
                    Container(
                      margin: EdgeInsets.only(top: dayIndex > 0 ? 24 : 0, bottom: 16),
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.teal[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.teal[200]!,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: isLargeMode ? 20 : 18,
                            color: Colors.teal[600],
                          ),
                          SizedBox(width: 8),
                          Text(
                            _formatDateForDisplay(dayDate),
                            style: TextStyle(
                              fontSize: isLargeMode ? 18 : 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal[700],
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.teal[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${dayMemories.length} ${dayMemories.length == 1 ? 'memory' : 'memories'}',
                              style: TextStyle(
                                fontSize: isLargeMode ? 14 : 12,
                                color: Colors.teal[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Spacer(),
                          // Tageszusammenfassungs-Button für diesen Tag
                          GestureDetector(
                            onTap: () {
                              fetchDailySummaryForDate(dayDate);
                            },
                            child: Container(
                              padding: EdgeInsets.all(isLargeMode ? 8 : 6),
                              decoration: BoxDecoration(
                                color: Colors.blue[100],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.blue[200]!,
                                  width: 1,
                                ),
                              ),
                              child: Icon(
                                Icons.auto_stories,
                                size: isLargeMode ? 18 : 16,
                                color: Colors.blue[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Posts für diesen Tag
                    ...dayMemories.map((memory) {
                      return GestureDetector(
                        onTap: () {
                          // Konvertiere Memory zu Entry-Format für Detail-Ansicht
                          final entry = {
                            'id': memory.id,
                            'title': memory.title,
                            'content': memory.content,
                            'timestamp': memory.createdAt,
                            'media_files': memory.mediaFiles.map((f) => {
                              'filename': f.filename,
                              'file_type': f.fileType,
                              'file_size': f.fileSize,
                              'duration': f.duration,
                              'created_at': DateTime.now().toIso8601String(),
                            }).toList(),
                          };
                          openEntryDetail(entry);
                        },
                        child: Container(
                          margin: EdgeInsets.only(bottom: 12),
                          padding: EdgeInsets.all(isLargeMode ? 20 : 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                                spreadRadius: 2,
                    ),
                  ],
                ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Titel
                            Text(
                              memory.title.isNotEmpty 
                                  ? memory.title 
                                  : 'Memory',
                              style: TextStyle(
                                fontSize: isLargeMode ? 18 : 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                            SizedBox(height: 8),
                            // Content
                            Text(
                              memory.content,
                              style: TextStyle(
                                fontSize: isLargeMode ? 16 : 14,
                                color: Colors.grey[600],
                                height: 1.4,
                              ),
                            ),
                            SizedBox(height: 12),
                            // Zeit, Media-Indikatoren und Likes
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: isLargeMode ? 16 : 14,
                                  color: Colors.grey[500],
                                ),
                                SizedBox(width: 6),
                                Text(
                                  _formatTimeForDisplay(memory.createdAt),
                                  style: TextStyle(
                                    fontSize: isLargeMode ? 14 : 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                                if (memory.mediaFiles.isNotEmpty) ...[
                                  SizedBox(width: 16),
                                  Icon(
                                    Icons.attach_file,
                                    size: isLargeMode ? 16 : 14,
                                    color: Colors.grey[500],
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    '${memory.mediaFiles.length} attachment${memory.mediaFiles.length == 1 ? '' : 's'}',
                                    style: TextStyle(
                                      fontSize: isLargeMode ? 14 : 12,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                                if (memory.id != null && memoryLikeCounts.containsKey(memory.id) && memoryLikeCounts[memory.id]! > 0) ...[
                                  SizedBox(width: 16),
                                  Icon(
                                    Icons.favorite,
                                    size: isLargeMode ? 16 : 14,
                                    color: Colors.red[500],
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    '${memoryLikeCounts[memory.id]} like${memoryLikeCounts[memory.id] == 1 ? '' : 's'}',
                                    style: TextStyle(
                                      fontSize: isLargeMode ? 14 : 12,
                                      color: Colors.red[500],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        ),
                      );
                    }).toList(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // Helper-Funktionen für Datum/Zeit-Formatierung
  String _formatDateForDisplay(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    
    if (dateOnly == today) {
      return 'Today';
    } else if (dateOnly == yesterday) {
      return 'Yesterday';
    } else {
      return '${date.day}.${date.month}.${date.year}';
    }
  }

  String _formatTimeForDisplay(DateTime? dateTime) {
    if (dateTime == null) return '';
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  // Oma-Ansicht
  Widget _buildOmaView() {
    // Lade Likes beim ersten Öffnen der Oma-Ansicht
    if (!hasLoadedLikesForOma) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadLikes();
        hasLoadedLikesForOma = true;
      });
    }
    
    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Header mit Navigation
          Container(
            padding: EdgeInsets.only(top: 40, left: 20, right: 20, bottom: 20),
                child: Row(
                  children: [
                // Home Button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      hasSelectedUserType = false;
                      isFamilyView = false;
                      isOmaView = false;
                    isLifeChaptersView = false; // Ensure life chapters view is off
                isFamilyMembersView = false; // Ensure family members view is off
                    isFamilyMembersView = false; // Ensure family members view is off
                    previousView = null; // Reset previous view
                    hasLoadedLikesForOma = false; // Reset likes loading flag
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: isLargeMode ? 12 : 8,
                          spreadRadius: isLargeMode ? 3 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.home,
                      size: isLargeMode ? 40 : 32,
                      color: Colors.teal[400],
                    ),
                  ),
                ),
                SizedBox(width: 20),
                // Familien-Button (wie auf der Eingabe-Seite)
                GestureDetector(
                        onTap: () {
                          setState(() {
                            isOmaView = false;
                            isFamilyView = true;
                            hasLoadedLikesForOma = false; // Reset likes loading flag
                    isLifeChaptersView = false; // Ensure life chapters view is off
                isFamilyMembersView = false; // Ensure family members view is off
                    isFamilyMembersView = false; // Ensure family members view is off
                    previousView = null; // Reset previous view
                          });
                        },
                  child: Container(
                    padding: EdgeInsets.all(isLargeMode ? 16 : 12),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green[200]!,
                          blurRadius: isLargeMode ? 12 : 8,
                          spreadRadius: isLargeMode ? 3 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.family_restroom,
                      size: isLargeMode ? 40 : 32,
                      color: Colors.green[600],
                    ),
                  ),
                ),
                SizedBox(width: 20),
                // Titel
                    Expanded(
                  child: Text(
                    'Grandma\'s Memories',
                    style: TextStyle(
                      fontSize: isLargeMode ? 32 : 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.pink[400],
                        ),
                      ),
                    ),
              ],
            ),
          ),
          
          // Neueste 3 Beiträge
          Expanded(
            child: memories.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.elderly_woman,
                          size: isLargeMode ? 80 : 64,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: 20),
                        Text(
                          'No memories yet',
                          style: TextStyle(
                            fontSize: isLargeMode ? 24 : 20,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Memories will appear here',
                          style: TextStyle(
                            fontSize: isLargeMode ? 18 : 16,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    itemCount: memories.length > 3 ? 3 : memories.length, // Nur die neuesten 3
                    itemBuilder: (context, index) {
                      final memory = memories[index];
                      return Container(
                        margin: EdgeInsets.only(bottom: 16),
                        padding: EdgeInsets.all(isLargeMode ? 20 : 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                              spreadRadius: 2,
                    ),
                  ],
                ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Titel
                            Text(
                              memory.title.isNotEmpty 
                                  ? memory.title 
                                  : 'New Memory',
                              style: TextStyle(
                                fontSize: isLargeMode ? 18 : 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[800],
                              ),
                            ),
                            SizedBox(height: 8),
                            // Content Preview
                            Text(
                              memory.content.length > 100 
                                  ? '${memory.content.substring(0, 100)}...'
                                  : memory.content,
                              style: TextStyle(
                                fontSize: isLargeMode ? 16 : 14,
                                color: Colors.grey[600],
                                height: 1.4,
                              ),
                            ),
                            SizedBox(height: 12),
                            // Datum und Like-Button
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: isLargeMode ? 16 : 14,
                                  color: Colors.grey[500],
                                ),
                                SizedBox(width: 6),
                                Text(
                                  _formatDateForFamily(memory.createdAt),
                                  style: TextStyle(
                                    fontSize: isLargeMode ? 14 : 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                                Spacer(),
                                // Like-Button
                                GestureDetector(
                                  onTap: () {
                                    if (memory.id != null) {
                                      _toggleLike(memory.id!);
                                    }
                                  },
                                  child: Container(
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: memory.id != null && likedMemories.contains(memory.id)
                                          ? Colors.red[50]
                                          : Colors.grey[50],
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: memory.id != null && likedMemories.contains(memory.id)
                                            ? Colors.red[200]!
                                            : Colors.grey[200]!,
                                        width: 1,
                                      ),
                                    ),
                                    child: Icon(
                                      memory.id != null && likedMemories.contains(memory.id)
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      size: isLargeMode ? 20 : 18,
                                      color: memory.id != null && likedMemories.contains(memory.id)
                                          ? Colors.red[500]
                                          : Colors.grey[500],
                                    ),
                                  ),
                    ),
                  ],
                ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          
          // Bottom Navigation
          Container(
            padding: EdgeInsets.all(20),
                child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                      // Buch-Button (links)
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            previousView = 'oma'; // Remember we came from Oma page
                            isLifeChaptersView = true;
                            isOmaView = false; // Exit Oma view when going to life chapters
                          });
                        },
                  child: Container(
                    padding: EdgeInsets.all(isLargeMode ? 20 : 16),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue[200]!,
                          blurRadius: isLargeMode ? 12 : 8,
                          spreadRadius: isLargeMode ? 3 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.menu_book,
                      size: isLargeMode ? 40 : 32,
                      color: Colors.blue[600],
                    ),
                  ),
                ),
                
                // Chat-Button (mitte)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      showChatView = true;
                      isOmaView = false;
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.all(isLargeMode ? 24 : 20),
                    decoration: BoxDecoration(
                      color: Colors.pink[100],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.pink[200]!,
                          blurRadius: isLargeMode ? 12 : 8,
                          spreadRadius: isLargeMode ? 3 : 2,
                    ),
                  ],
                ),
                    child: Icon(
                      Icons.chat,
                      size: isLargeMode ? 40 : 32,
                      color: Colors.pink[600],
                    ),
                  ),
                ),
                
                // Kalender-Button (rechts)
                GestureDetector(
                  onTap: () {
                    setState(() {
                      showDailySummariesList = true;
                      isOmaView = false;
                    });
                  },
                  child: Container(
                    padding: EdgeInsets.all(isLargeMode ? 20 : 16),
                    decoration: BoxDecoration(
                      color: Colors.teal[100],
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.teal[200]!,
                          blurRadius: isLargeMode ? 12 : 8,
                          spreadRadius: isLargeMode ? 3 : 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.calendar_month,
                      size: isLargeMode ? 40 : 32,
                      color: Colors.teal[600],
                    ),
                  ),
                ),
              ],
              ),
            ),
        ],
      ),
    );
  }
}
