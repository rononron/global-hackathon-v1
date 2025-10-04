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
    fileSize: json['file_size'],
    duration: json['duration'],
  );
}

class Memory {
  final int? id;
  final String title;
  final String content;
  final List<MediaFile> mediaFiles;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  Memory({
    this.id,
    required this.title,
    required this.content,
    this.mediaFiles = const [],
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'media_files': mediaFiles.map((f) => f.toJson()).toList(),
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
  final apiUrl = AppConfig.apiUrl;
  bool showPostEditor = false;
  bool isListening = false;
  bool showHistory = false;
  late bool isLargeMode = true; // Standard: vergrößerter Modus
  late AnimationController _pulseController;
  late AnimationController _pulseController2;
  String _recognizedText = '';
  bool _isAvailable = true; // Simuliert verfügbare Spracherkennung
  
  // History View States
  late bool isHistoryView = false;
  DateTime currentMonth = DateTime.now();
  DateTime? selectedDay;
  List<Map<String, dynamic>> historyEntries = [];
  
  // Media States
  List<MediaFile> _selectedMediaFiles = [];
  final ImagePicker _imagePicker = ImagePicker();
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _recordingPath;
  bool _showMediaExpanded = false;

  @override
  void initState() {
    super.initState();
    fetchMemories();
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseController2 = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    );
    _initializeSampleData();
    // Speech-to-Text wird später implementiert
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
    super.dispose();
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
        });
      }
    } catch (e) {
      print('Error fetching memories: $e');
    }
  }

  void _syncHistoryEntries() {
    // Konvertiere Memory-Objekte zu historyEntries-Format
    historyEntries = memories.map((memory) {
      return {
        'id': memory.id,
        'title': memory.title,
        'content': memory.content,
        'media_files': memory.mediaFiles.map((f) => f.toJson()).toList(),
        'timestamp': memory.createdAt ?? DateTime.now(),
        'date': memory.createdAt ?? DateTime.now(),
      };
    }).toList();
  }

  Future<void> addMemory(String content, {String? title, List<MediaFile>? mediaFiles}) async {
    if (content.trim().isEmpty) return;
    
    final memory = Memory(
      title: title ?? _generateTitle(content),
      content: content,
      mediaFiles: mediaFiles ?? _selectedMediaFiles,
    );
    
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(memory.toJson()),
      );
      if (response.statusCode == 200) {
        _controller.clear();
        _titleController.clear();
        _selectedMediaFiles.clear();
        // Lade die Daten neu, damit sie in der Kalender-Ansicht erscheinen
        await fetchMemories();
      }
    } catch (e) {
      print('Error adding memory: $e');
    }
  }

  String _generateTitle(String content) {
    // Erste 30 Zeichen als Titel verwenden
    if (content.length <= 30) return content;
    return content.substring(0, 30) + '...';
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

  void startKeyboardPost() {
    setState(() {
      showPostEditor = true;
      isListening = false;
      _pulseController.stop();
      _pulseController2.stop();
      // Übertrage vorhandenen Text vom Controller
      if (_controller.text.isNotEmpty) {
        _speechController.text = _controller.text;
        _recognizedText = _controller.text;
      }
    });
  }

  void _simulateListening() async {
    // Simuliert Spracherkennung für Demo-Zwecke - wortweise
    final demoText = "Das ist ein simulierter Text für die Demo.";
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
      addMemory(
        _speechController.text,
        title: _generateTitle(_speechController.text),
        mediaFiles: _selectedMediaFiles,
      );
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
    });
  }

  void _navigateToMonth(int direction) {
    setState(() {
      currentMonth = DateTime(currentMonth.year, currentMonth.month + direction);
      selectedDay = null;
    });
  }

  void _selectDay(DateTime day) {
    setState(() {
      selectedDay = day;
    });
  }

  void _goBackToCalendar() {
    setState(() {
      selectedDay = null;
    });
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

  List<DateTime> _getDaysInMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);
    final daysInMonth = lastDay.day;
    
    List<DateTime> days = [];
    for (int i = 1; i <= daysInMonth; i++) {
      days.add(DateTime(month.year, month.month, i));
    }
    return days;
  }

  void toggleSizeMode() {
    setState(() {
      isLargeMode = !isLargeMode;
    });
  }

  Widget _buildHistoryView() {
    if (selectedDay != null) {
      return _buildDayView();
    } else {
      return _buildCalendarView();
    }
  }

  Widget _buildCalendarView() {
    final monthEntries = _getEntriesForMonth(currentMonth);
    final daysInMonth = _getDaysInMonth(currentMonth);
    final monthNames = [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
    ];

    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          // Header mit Zurück-Button und Monats-Navigation
          Container(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
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
                    '${monthNames[currentMonth.month - 1]} ${currentMonth.year}',
                    style: TextStyle(
                      fontSize: isLargeMode ? 24 : 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[400],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                GestureDetector(
                  onTap: () => _navigateToMonth(-1),
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.chevron_left, size: 24, color: Colors.grey[700]),
                  ),
                ),
                SizedBox(width: 10),
                GestureDetector(
                  onTap: () => _navigateToMonth(1),
                  child: Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.chevron_right, size: 24, color: Colors.grey[700]),
                  ),
                ),
              ],
            ),
          ),
          // Kalender-Grid
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: daysInMonth.length,
                itemBuilder: (context, index) {
                  final day = daysInMonth[index];
                  final hasEntries = monthEntries.any((entry) => 
                      entry['date'].day == day.day);
                  final isToday = day.day == DateTime.now().day && 
                                 day.month == DateTime.now().month && 
                                 day.year == DateTime.now().year;
                  
                  return GestureDetector(
                    onTap: () => _selectDay(day),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isToday 
                            ? Colors.orange[200]  // Heute: Orange Hintergrund
                            : hasEntries 
                                ? Colors.teal[100] 
                                : Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isToday 
                              ? Colors.orange[600]!  // Heute: Orange Border
                              : hasEntries 
                                  ? Colors.teal[300]! 
                                  : Colors.grey[300]!,
                          width: isToday ? 3 : 1,  // Heute: Dickerer Border
                        ),
                        boxShadow: isToday ? [
                          BoxShadow(
                            color: Colors.orange[300]!.withOpacity(0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ] : null,
                      ),
                      child: Center(
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: isLargeMode ? 18 : 16,
                            fontWeight: isToday ? FontWeight.bold : (hasEntries ? FontWeight.w600 : FontWeight.normal),
                            color: isToday 
                                ? Colors.orange[800]!  // Heute: Dunkelorange Text
                                : hasEntries 
                                    ? Colors.teal[700] 
                                    : Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayView() {
    final dayEntries = _getEntriesForDay(selectedDay!);
    final dayNames = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
    final monthNames = [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
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
              ],
            ),
          ),
          // Einträge des Tages
          Expanded(
            child: dayEntries.isEmpty
                ? Center(
                    child: Text(
                      'Keine Einträge für diesen Tag',
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
                      
                      return Container(
                        margin: EdgeInsets.only(bottom: 16),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Zeitstempel
                            Text(
                              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: isLargeMode ? 18 : 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.teal[600],
                              ),
                            ),
                            SizedBox(height: 8),
                            // Titel
                            if (entry['title'] != null && entry['title'].toString().isNotEmpty)
                              Text(
                                entry['title'],
                                style: TextStyle(
                                  fontSize: isLargeMode ? 20 : 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[800],
                                ),
                              ),
                            if (entry['title'] != null && entry['title'].toString().isNotEmpty)
                              SizedBox(height: 8),
                            // Inhalt
                            Text(
                              entry['content'],
                              style: TextStyle(
                                fontSize: isLargeMode ? 18 : 16,
                                color: Colors.grey[800],
                              ),
                            ),
                            // Media-Anhänge
                            if (entry['media_files'] != null && (entry['media_files'] as List).isNotEmpty) ...[
                              SizedBox(height: 12),
                              Text(
                                'Anhänge:',
                                style: TextStyle(
                                  fontSize: isLargeMode ? 16 : 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[600],
                                ),
                              ),
                              SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: (entry['media_files'] as List).map<Widget>((media) {
                                  return Container(
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: _getMediaColor(media['file_type']).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _getMediaColor(media['file_type']).withOpacity(0.3),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          _getMediaIcon(media['file_type']),
                                          size: isLargeMode ? 20 : 16,
                                          color: _getMediaColor(media['file_type']),
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          media['filename'],
                                          style: TextStyle(
                                            fontSize: isLargeMode ? 14 : 12,
                                            color: _getMediaColor(media['file_type']),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (media['duration'] != null) ...[
                                          SizedBox(width: 4),
                                          Text(
                                            '(${_formatDuration(media['duration'])})',
                                            style: TextStyle(
                                              fontSize: isLargeMode ? 12 : 10,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
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
                      isListening ? 'Zuhören...' : 'Neuen Post erstellen',
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
              // Text-Eingabe
              TextField(
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
                      label: Text('Senden', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
            ],
          ),
        ),
        
        // Mikrofon-Animation oder Tastatur (unten)
        if (isListening) _buildMicrophoneAnimation(),
        if (!isListening) _buildSimulatedKeyboard(),
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

  Widget _buildSimulatedKeyboard() {
    return Expanded(
      child: Container(
        margin: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey[200],
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
          children: [
            // Tastatur-Header
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tastatur',
                    style: TextStyle(
                      fontSize: isLargeMode ? 18 : 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Simulation',
                      style: TextStyle(
                        fontSize: isLargeMode ? 12 : 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Tastatur-Body
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Erste Reihe: Q W E R T Z U I O P
                    _buildKeyboardRow(['Q', 'W', 'E', 'R', 'T', 'Z', 'U', 'I', 'O', 'P']),
                    SizedBox(height: 8),
                    
                    // Zweite Reihe: A S D F G H J K L
                    _buildKeyboardRow(['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'], isOffset: true),
                    SizedBox(height: 8),
                    
                    // Dritte Reihe: Y X C V B N M
                    _buildKeyboardRow(['Y', 'X', 'C', 'V', 'B', 'N', 'M'], isOffset: true),
                    SizedBox(height: 12),
                    
                    // Vierte Reihe: Leertaste und Funktionstasten
                    Row(
                      children: [
                        // 123-Taste
                        _buildSpecialKey('123', isWide: true),
                        SizedBox(width: 8),
                        
                        // Leertaste
                        Expanded(
                          child: Container(
                            height: isLargeMode ? 50 : 40,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[400]!, width: 1),
                            ),
                            child: Center(
                              child: Text(
                                'Leertaste',
                                style: TextStyle(
                                  fontSize: isLargeMode ? 16 : 14,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8),
                        
                        // Return-Taste
                        _buildSpecialKey('Return', isWide: true),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyboardRow(List<String> keys, {bool isOffset = false}) {
    return Row(
      children: [
        if (isOffset) SizedBox(width: 20), // Offset für zweite und dritte Reihe
        ...keys.map((key) => Expanded(
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 2),
            height: isLargeMode ? 50 : 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: Text(
                key,
                style: TextStyle(
                  fontSize: isLargeMode ? 18 : 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
            ),
          ),
        )).toList(),
        if (isOffset) SizedBox(width: 20), // Offset für zweite und dritte Reihe
      ],
    );
  }

  Widget _buildSpecialKey(String text, {bool isWide = false}) {
    return Container(
      width: isWide ? (isLargeMode ? 80 : 60) : (isLargeMode ? 50 : 40),
      height: isLargeMode ? 50 : 40,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[400]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: isLargeMode ? 14 : 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey[600],
          ),
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
            onTap: startKeyboardPost,
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
              onTap: () => _pickImage(ImageSource.gallery),
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
                    Text('Foto', style: TextStyle(fontSize: isLargeMode ? 14 : 12, color: Colors.blue[600])),
                  ],
                ),
              ),
            ),
            // Video aus Galerie
            GestureDetector(
              onTap: () => _pickVideo(ImageSource.gallery),
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
                      _isRecording ? 'Stopp' : 'Audio',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // App Name oben mittig
          Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Memory Keeper',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal[400],
                ),
              ),
            ),
          ),

          // History Icon oben links - größer (nur in normaler Ansicht)
          if (!isHistoryView)
            Positioned(
              top: 40,
              left: 20,
              child: GestureDetector(
                onTap: toggleHistory,
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(Icons.history, size: 40, color: Colors.teal[400]),
                ),
              ),
            ),

          // Größen-Toggle Icon oben rechts (nur in normaler Ansicht)
          if (!isHistoryView)
            Positioned(
              top: 40,
              right: 20,
              child: GestureDetector(
                onTap: toggleSizeMode,
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    isLargeMode ? Icons.zoom_out : Icons.zoom_in,
                    size: 40,
                    color: Colors.teal[400],
                  ),
                ),
              ),
            ),

          // History View - Kalender oder Tagesansicht
          if (isHistoryView)
            _buildHistoryView(),

          // Post-Editor oder Hauptmikrofon-Button
          if (!isHistoryView)
            showPostEditor ? _buildPostEditor() : _buildMainInterfaceWithKeyboard(),


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
                              'Zuhören...',
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
                              'Text bearbeiten',
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
                            label: Text('Abbrechen', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                            label: Text('Senden', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                        addMemory(_controller.text);
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
      ),
    );
  }
}
