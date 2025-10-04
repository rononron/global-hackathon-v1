// lib/main.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
        primaryColor: Colors.teal[300],
        scaffoldBackgroundColor: Color(0xFFF0F4F8),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          hintStyle: TextStyle(color: Colors.grey[400]),
        ),
        textTheme: TextTheme(
          bodyMedium: TextStyle(color: Colors.grey[800]),
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

class _MemoryPageState extends State<MemoryPage> {
  final TextEditingController _controller = TextEditingController();

  // Null-sichere Variablen
  List memories = [];
  bool? showHistory = false;

  final apiUrl = 'http://localhost:8000/memories';
  //final apiUrl = 'https://faucial-joel-gingelly.ngrok-free.dev/memories';

  @override
  void initState() {
    super.initState();
    fetchMemories();
  }

  Future<void> fetchMemories() async {
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          memories = data ?? [];
        });
      }
    } catch (e) {
      print('Error fetching memories: $e');
      setState(() {
        memories = [];
      });
    }
  }

  Future<void> addMemory(String content) async {
    if (content.trim().isEmpty) return;
    try {
      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'content': content}),
      );
      if (response.statusCode == 200) {
        _controller.clear();
        fetchMemories();
      }
    } catch (e) {
      print('Error adding memory: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // App-Name
                Text(
                  'Memory Keeper',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal[300],
                  ),
                ),
                SizedBox(height: 40),

                // Input-Feld
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: 'Neue Erinnerung...',
                            border: InputBorder.none,
                          ),
                          onSubmitted: addMemory,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.send, color: Colors.teal[300]),
                        onPressed: () => addMemory(_controller.text),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 24),

                // Button zum Anzeigen/Verstecken der Historie
                if ((memories ?? []).isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        showHistory = !(showHistory ?? false);
                      });
                    },
                    child: Text(
                      (showHistory ?? false)
                          ? 'Historie ausblenden'
                          : 'Historie anzeigen',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),

                // Memory-Historie (optional)
                if (showHistory ?? false)
                  Container(
                    margin: EdgeInsets.only(top: 12),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      itemCount: memories.length,
                      itemBuilder: (context, index) {
                        final memory = memories[index];
                        return Container(
                          margin: EdgeInsets.symmetric(vertical: 6),
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            memory?['content'] ?? '',
                            style: TextStyle(fontSize: 16),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
