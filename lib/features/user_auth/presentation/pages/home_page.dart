import 'dart:async';
import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_firebase/global/common/toast.dart';
import 'package:intl/intl.dart';

import 'package:http/http.dart' as http;
import 'camera_page.dart';
import 'login_page.dart';
import 'setting_page.dart';
import 'history_page.dart';
import 'package:fl_chart/fl_chart.dart';
import 'recent_emotion_card.dart'; // path apne project ke hisab se update karein
import 'emotion_pie_chart.dart'; // Pie chart widget import

class HomePage extends StatefulWidget {
  final User? user;
  const HomePage({super.key, required this.user});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const String _apiUrl = 'https://9fe08568a31e.ngrok-free.app';
  final DatabaseReference _databaseReference = FirebaseDatabase.instance.ref();

  bool _loading = true;
  String? firstName;
  String? _dominantCombineEmotion; // <-- Added to fix undefined name error

  Timer? emotionTimer;
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  String? _lastNotifiedEmotion;
  String? _lastNotificationTitle;
  String? _lastNotificationBody;

  Map<String, dynamic>? _latestEmotion;
  StreamSubscription<DatabaseEvent>? _emotionStream;

  bool _showPieChart = false; // Pie chart toggle (not used now)
  Map<String, double> _combineEmotionTotals = {};

  final ScrollController _legendScrollController = ScrollController();

  String? _lastDominantEmotion; // Add this variable to your _HomePageState

  @override
  void initState() {
    super.initState();
    _fetchUserDetails();
    _initializeNotification();
    _startEmotionMonitoring(); // <-- Bas isko uncomment kar dein
    _listenToLatestEmotion();
    _fetchCombineEmotionTotals();
    _fetchLatestEmotion();
    _loading = true;
  }

  @override
  void dispose() {
    _legendScrollController.dispose();
    emotionTimer?.cancel();
    _emotionStream?.cancel();
    super.dispose();
  }

  Future<void> _initializeNotification() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (_lastNotificationTitle != null && _lastNotificationBody != null) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => NotificationDetailScreen(
              title: _lastNotificationTitle!,
              body: _lastNotificationBody!,
            ),
          ));
        }
      },
    );

    // Request permission for Android 13+ (API 33+)
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  void _startEmotionMonitoring() {
    print('Starting emotion monitoring timer...');
    emotionTimer = Timer.periodic(const Duration(minutes: 7), (_) async {
      print('Timer tick: checking latest emotion...');
      await _checkLatestEmotion();
    });
  }

  void _listenToLatestEmotion() {
    if (widget.user == null) return;
    final ref = FirebaseDatabase.instance
        .ref()
        .child('emotion_logs')
        .child('history')
        .child(widget.user!.uid);

    _emotionStream =
        ref.orderByKey().limitToLast(1).onChildAdded.listen((event) async {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final latest = Map<String, dynamic>.from(event.snapshot.value as Map);
        final combined = latest['combined_emotion'] as Map?;
        if (combined != null && combined.isNotEmpty) {
          String? dominantEmotion;
          double maxScore = double.negativeInfinity;
          combined.forEach((emo, score) {
            double scoreDouble;
            if (score is int) {
              scoreDouble = score.toDouble();
            } else if (score is double) {
              scoreDouble = score;
            } else if (score is String) {
              scoreDouble = double.tryParse(score) ?? 0.0;
            } else {
              scoreDouble = 0.0;
            }
            if (scoreDouble > maxScore) {
              maxScore = scoreDouble;
              dominantEmotion = emo.toString();
            }
          });
          if (dominantEmotion != null) {
            // Har detection par notification bhejein
            final recommendation =
                await _getRecommendationForEmotion(dominantEmotion!);
            await _showEmotionNotification(dominantEmotion!, recommendation);
            _lastNotifiedEmotion = dominantEmotion;
          }
        }
      }
    });

    // Also listen to changes in the last child (for updates)
    ref.orderByKey().limitToLast(1).onValue.listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
        final latestEntry = data.entries
            .map((e) => Map<String, dynamic>.from(e.value))
            .toList();
        if (latestEntry.isNotEmpty) {
          setState(() {
            _latestEmotion = latestEntry.first;
          });
        }
      }
    });
  }

  Future<void> _checkLatestEmotion() async {
    if (widget.user == null) return;
    print('Running _checkLatestEmotion...');
    try {
      final snapshot = await _databaseReference
          .child('emotion_logs/history/${widget.user!.uid}')
          .get();

      if (snapshot.exists) {
        final Map<dynamic, dynamic> values = snapshot.value as Map;
        if (values.isEmpty) return;

        final Map<String, double> emotionTotals = {};

        for (var entry in values.entries) {
          final combined = entry.value['combined_emotion'];
          if (combined is Map) {
            combined.forEach((emo, score) {
              final emoStr = emo.toString().toLowerCase();
              final scoreDouble = (score as num).toDouble();
              emotionTotals[emoStr] =
                  (emotionTotals[emoStr] ?? 0) + scoreDouble;
            });
          } else {
            print('Skipping entry with non-Map combined_emotion: $entry');
            continue;
          }
        }

        if (emotionTotals.isNotEmpty) {
          final dominant = emotionTotals.entries
              .reduce((a, b) => a.value > b.value ? a : b)
              .key;

          // Always show notification, even if emotion is same
          final recommendation = await _getRecommendationForEmotion(dominant);
          await _showEmotionNotification(dominant, recommendation);
        }
      }
    } catch (e) {
      debugPrint('Emotion Check Error: $e');
    }
  }

  Future<void> _showEmotionNotification(
      String emotion, String recommendation) async {
    print('🔔 Showing notification for $emotion'); // <-- Add this line
    _lastNotifiedEmotion = emotion;
    _lastNotificationTitle = 'Detected Emotion';
    _lastNotificationBody = 'You seem to be $emotion\n$recommendation';

    LastNotificationState.update(
      emotion: emotion,
      score: 1.0, // Or use the actual score if available
      date: DateTime.now().toIso8601String(),
      recommendation: recommendation,
    );

    final BigTextStyleInformation bigTextStyle = BigTextStyleInformation(
      _lastNotificationBody!,
      contentTitle: _lastNotificationTitle!,
      summaryText: 'Tap to see details',
      htmlFormatContent: true,
      htmlFormatContentTitle: true,
    );

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'emotion_channel_id',
      'Emotion Alerts',
      channelDescription: 'Shows alerts based on your dominant emotion',
      importance: Importance.max,
      priority: Priority.high,
      styleInformation: bigTextStyle,
      color: const Color(0xFF6A1B9A),
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      icon: '@mipmap/ic_launcher',
      enableVibration: true,
      playSound: true,
      ticker: 'Emotion Notification',
    );

    final NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await flutterLocalNotificationsPlugin.show(
      0,
      _lastNotificationTitle!,
      _lastNotificationBody!,
      platformChannelSpecifics,
      payload: 'show_details',
    );
  }

  Future<String> _getRecommendationForEmotion(String emotion) async {
    if (widget.user == null) return '';
    try {
      final uri =
          Uri.parse("https://9fe08568a31e.ngrok-free.app/get_recommendation");
      final request = http.MultipartRequest('POST', uri)
        ..fields['emotion'] = emotion
        ..fields['uid'] = widget.user!.uid;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final decoded = jsonDecode(responseBody);

      final recommendation =
          decoded['recommendation'] ?? 'No recommendation available';
      return recommendation;
    } catch (e) {
      showToast(message: 'Recommendation error: $e');
      return 'Error fetching recommendation.';
    }
  }

  // Fetch first name from Firestore (call this in initState)
  Future<void> _fetchUserDetails() async {
    final uid = widget.user?.uid;
    if (uid == null) {
      print('❌ No user signed in');
      return;
    }

    print('🔍 Fetching details for UID: $uid');

    try {
      final userDoc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      if (userDoc.exists) {
        final data = userDoc.data();
        final fetchedName = data?['firstName'] ?? 'User';
        print('✅ Fetched name: $fetchedName');
        setState(() {
          firstName = fetchedName;
        });
      } else {
        print('❌ No document found for this UID');
      }
    } catch (e) {
      print('🔥 Firestore fetch error: $e');
    }
  }

  // Call this in initState or when you want to refresh combine emotion data
  Future<void> _fetchCombineEmotionTotals() async {
    if (widget.user == null) return;
    final ref = FirebaseDatabase.instance
        .ref()
        .child('emotion_logs')
        .child('history')
        .child(widget.user!.uid);
    final snapshot = await ref.get();
    if (!snapshot.exists || snapshot.value == null) {
      setState(() {
        _combineEmotionTotals = {};
        _dominantCombineEmotion = null;
      });
      return;
    }

    final data = snapshot.value;
    if (data is! Map) {
      setState(() {
        _combineEmotionTotals = {};
        _dominantCombineEmotion = null;
      });
      return;
    }

    final Map<dynamic, dynamic> mapData = Map<dynamic, dynamic>.from(data);
    final Map<String, double> emotionTotals = {};

    for (var entry in mapData.values) {
      if (entry is! Map) continue; // <-- skip if not a Map
      final combined = entry['combined_emotion'];
      if (combined is Map) {
        combined.forEach((emo, score) {
          final emoStr = emo.toString().toLowerCase();
          final scoreDouble = (score as num).toDouble();
          emotionTotals[emoStr] = (emotionTotals[emoStr] ?? 0) + scoreDouble;
        });
      }
    }

    // Find dominant emotion
    String? dominant;
    double maxScore = 0;
    emotionTotals.forEach((emo, score) {
      if (score > maxScore) {
        dominant = emo;
        maxScore = score;
      }
    });

    setState(() {
      _combineEmotionTotals = emotionTotals;
      _dominantCombineEmotion = dominant;
    });
  }

  void _fetchLatestEmotion() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseDatabase.instance
        .ref()
        .child('emotion_logs')
        .child('history')
        .child(user.uid);

    final snapshot = await ref.get();

    if (snapshot.exists && snapshot.value != null) {
      final data = snapshot.value;
      if (data is! Map) {
        setState(() {
          _latestEmotion = null;
          _loading = false;
        });
        return;
      }
      final Map<dynamic, dynamic> mapData = Map<dynamic, dynamic>.from(data);
      final List<Map<dynamic, dynamic>> history = [];
      mapData.forEach((key, value) {
        if (value is! Map) return; // <-- skip if not a Map
        final entry = Map<dynamic, dynamic>.from(value);
        if (entry.containsKey('combined_emotion')) {
          final combined = entry['combined_emotion'];
          if (combined is Map && combined.isNotEmpty) {
            final dominant =
                combined.entries.reduce((a, b) => a.value > b.value ? a : b);
            history.add({
              'emotion': dominant.key,
              'score': dominant.value,
              'date': entry['timestamp'] ?? entry['date'] ?? '',
              'recommendation': entry['recommendation'] ?? '',
            });
          }
        }
      });

      if (history.isNotEmpty) {
        setState(() {
          _latestEmotion =
              Map<String, dynamic>.from(history.reversed.first); // latest
          _loading = false;
        });
      } else {
        setState(() {
          _latestEmotion = null;
          _loading = false;
        });
      }
    } else {
      setState(() {
        _latestEmotion = null;
        _loading = false;
      });
    }
  }

  Widget _buildLatestEmotionCard() {
    if (_latestEmotion == null) return const SizedBox();
    final emotion = _latestEmotion?['emotion'] ?? '';
    final suggestion = _latestEmotion?['recommendation'] ?? '';
    final timestamp = _latestEmotion?['timestamp'] ?? '';
    String timeStr = '';
    if (timestamp.isNotEmpty) {
      try {
        final dt = DateTime.parse(timestamp);
        timeStr = DateFormat('hh:mm a').format(dt);
      } catch (_) {
        timeStr = timestamp;
      }
    }
    final emoji = _emotionEmoji(emotion);
    String emotionText = '';
    if (emotion.isNotEmpty) {
      emotionText = '${emotion[0].toUpperCase()}${emotion.substring(1)}';
    }

    return Card(
      elevation: 8,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: const Color(0xFF6A1B9A).withOpacity(0.13),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (emotionText.isNotEmpty)
              Text(
                'Detected Emotion: $emoji $emotionText',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            if (timeStr.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Time: $timeStr', style: const TextStyle(fontSize: 15)),
            ],
            if (suggestion.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Suggestion: $suggestion',
                  style: const TextStyle(fontSize: 15)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLatestDetectionCard() {
    if (_latestEmotion == null ||
        (_latestEmotion?['timestamp'] ?? '').toString().isEmpty) {
      return const SizedBox();
    }
    final emotion = _latestEmotion?['emotion'] ?? '';
    final suggestion = _latestEmotion?['recommendation'] ?? '';
    final timestamp = _latestEmotion?['timestamp'] ?? '';
    final emoji = _emotionEmoji(emotion);
    String timeStr = '';
    if (timestamp.isNotEmpty) {
      try {
        final dt = DateTime.parse(timestamp);
        timeStr = DateFormat('hh:mm a').format(dt);
      } catch (_) {
        timeStr = timestamp;
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detected Emotion: $emoji ${emotion.isNotEmpty ? emotion[0].toUpperCase() + emotion.substring(1) : ''}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF283593),
              ),
            ),
            const SizedBox(height: 8),
            if (timeStr.isNotEmpty)
              Text(
                'Time: $timeStr',
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
            const SizedBox(height: 8),
            // Always show Suggestion, even if empty
            Text(
              'Suggestion: ${suggestion.isNotEmpty ? '“$suggestion”' : 'No suggestion available.'}',
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF6A1B9A),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openRecentEmotionScreen(BuildContext context) {
    final emotion = LastNotificationState.emotion ?? '';
    final recommendation = LastNotificationState.recommendation ?? '';
    final emoji = _emotionEmoji(emotion);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecentEmotionScreen(
          emotion: emotion,
          suggestion: recommendation,
          emoji: emoji,
        ),
      ),
    );
  }

  Widget _buildRecentEmotionCard() {
    final emotion = LastNotificationState.emotion ?? '';
    final score = LastNotificationState.score ?? 0.0;
    final date = LastNotificationState.date ?? '';
    final recommendation = LastNotificationState.recommendation ?? '';

    if (emotion.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            children: [
              Text(
                "How are you feeling today?",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "No emotion detected yet.",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    final emoji = _emotionEmoji(emotion);

    return RecentEmotionCard(
      emotionName: emotion,
      score: score,
      date: date,
      recommendation: recommendation,
    );
  }

  Widget _buildPieChart(Map<String, double> emotionTotals) {
    if (emotionTotals.isEmpty) {
      return const Center(child: Text('No emotion data for chart.'));
    }
    final emotions = emotionTotals.keys.toList();
    final values = emotionTotals.values.toList();
    final total = values.fold(0.0, (a, b) => a + b);

    // Define emotion colors (reuse your map or define here)
    final Map<String, Color> emotionColors = {
      'neutral': const Color(0xFFBDBDBD),
      'fearful': const Color(0xFF00B8D4),
      'surprise': const Color(0xFFFFEA00),
      'sad': const Color(0xFF2979FF),
      'angry': const Color(0xFFD50000),
      'happy': const Color(0xFFFFD600),
      'disgust': const Color(0xFF43A047),
      'surprised': const Color(0xFFFF6D00),
      'calm': const Color(0xFF8E24AA),
    };

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: AspectRatio(
        aspectRatio: 1.4,
        child: PieChart(
          PieChartData(
            sections: List.generate(
              emotions.length,
              (i) => PieChartSectionData(
                color: emotionColors[emotions[i]] ?? Colors.deepPurple,
                value: values[i],
                title: '${((values[i] / total) * 100).toStringAsFixed(1)}%',
                radius: 90,
                titleStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
            sectionsSpace: 2,
            centerSpaceRadius: 36,
          ),
        ),
      ),
    );
  }

  Widget _buildLegend(Map<String, double> emotionTotals) {
    final Map<String, Color> emotionColors = {
      'neutral': const Color(0xFFBDBDBD),
      'fearful': const Color(0xFF00B8D4),
      'surprise': const Color(0xFFFFEA00),
      'sad': const Color(0xFF2979FF),
      'angry': const Color(0xFFD50000),
      'happy': const Color(0xFFFFD600),
      'disgust': const Color(0xFF43A047),
      'surprised': const Color(0xFFFF6D00),
      'calm': const Color(0xFF8E24AA),
    };
    final emotions = emotionTotals.keys.toList();
    if (emotions.isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: emotions.map((emo) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: emotionColors[emo] ?? Colors.deepPurple,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.black12),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                emo[0].toUpperCase() + emo.substring(1),
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.home, size: 30, color: Colors.white),
            SizedBox(width: 10),
            Text('Home', style: TextStyle(fontSize: 22, color: Colors.white)),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF283593)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      drawer: _buildDrawer(),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: EdgeInsets.zero,
                children: [
                  _buildUserCard(),
                  const SizedBox(height: 24),
                  // Always show the pie chart
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'Last Day Summary',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF283593),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  EmotionPieChart(
                    emotionTotals: _combineEmotionTotals,
                    emotionColors: const {
                      'neutral': Color(0xFFBDBDBD),
                      'fearful': Color(0xFF00B8D4),
                      'surprise': Color(0xFFFFEA00),
                      'sad': Color(0xFF2979FF),
                      'angry': Color(0xFFD50000),
                      'happy': Color(0xFFFFD600),
                      'disgust': Color(0xFF43A047),
                      'surprised': Color(0xFFFF6D00),
                      'calm': Color(0xFF8E24AA),
                    },
                  ),
                  const SizedBox(height: 16),
                  if (_latestEmotion != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12.0, vertical: 8.0),
                      child: RecentEmotionCard(
                        emotionName: _latestEmotion!['emotion'] ?? '',
                        score: (_latestEmotion!['score'] ?? 0.0) as double,
                        date: _latestEmotion!['date'] ?? '',
                        recommendation: _latestEmotion!['recommendation'] ?? '',
                      ),
                    ),
                  // ...other widgets...
                ],
              ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        elevation: 12,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: const Icon(Icons.show_chart,
                    size: 30, color: Color(0xFF6A1B9A)),
                onPressed: () {
                  setState(() {
                    _showPieChart = !_showPieChart;
                    if (_showPieChart) {
                      _fetchCombineEmotionTotals(); // this will fetch weekly totals
                    }
                  });
                },
                tooltip: "Show/Hide Weekly Emotion Graph",
              ),
              Container(
                height: 56,
                width: 56,
                margin: const EdgeInsets.only(bottom: 8),
                child: FloatingActionButton(
                  backgroundColor: const Color(0xFF6A1B9A),
                  elevation: 6,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => CameraPage(apiUrl: _apiUrl)),
                    );
                  },
                  child: const Icon(Icons.camera_alt,
                      size: 32, color: Colors.white),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.emoji_emotions,
                    size: 30, color: Color(0xFF6A1B9A)),
                onPressed: () => _openRecentEmotionScreen(context),
                tooltip: "Recent Emotion",
              ),
            ],
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: null,
    );
  }

  String _emotionEmoji(String emotion) {
    switch (emotion.toLowerCase()) {
      case 'happy':
        return '😊';
      case 'sad':
        return '😢';
      case 'angry':
        return '😠';
      case 'neutral':
        return '😐';
      case 'fearful':
        return '😨';
      case 'surprise':
      case 'surprised':
        return '😲';
      case 'disgust':
        return '🤢';
      case 'calm':
        return '😌';
      default:
        return '';
    }
  }

  Drawer _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6A1B9A), Color(0xFF283593)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(radius: 30),
                const SizedBox(height: 10),
                Text(
                  'Welcome, ${firstName ?? "Loading..."}!',
                  style: const TextStyle(color: Colors.white, fontSize: 20),
                ),
              ],
            ),
          ),
          _buildDrawerTile(Icons.home, 'Home', () => Navigator.pop(context)),
          _buildDrawerTile(Icons.history, 'History', () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const HistoryPage()));
          }),
          _buildDrawerTile(Icons.settings, 'Settings', () {
            Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingPage()));
          }),
          _buildDrawerTile(Icons.logout, 'Logout', () async {
            await FirebaseAuth.instance.signOut();
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
              (route) => false,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDrawerTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF283593)),
      title: Text(title),
      onTap: onTap,
    );
  }

  Widget _buildUserCard() {
    return Card(
      elevation: 8,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: const Color(0xFF6A1B9A).withOpacity(0.07), // 👈 lighter purple
      child: Padding(
        padding: const EdgeInsets.symmetric(
            vertical: 32.0, horizontal: 20.0), // 👈 more padding
        child: Row(
          children: [
            const CircleAvatar(radius: 38), // 👈 bigger avatar
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                firstName == null ? 'Welcome...' : 'Welcome, $firstName!',
                style: const TextStyle(
                  fontSize: 26, // 👈 bigger text
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 69, 77, 135),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void testNotification() async {
    await _showEmotionNotification('Test', 'This is a test notification');
  }

  Future<void> saveEmotionToFirebase(Map<String, dynamic> combinedEmotion, String recommendation) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final ref = FirebaseDatabase.instance
      .ref()
      .child('emotion_logs')
      .child('history')
      .child(user.uid)
      .push(); // Har detection par nayi entry

  await ref.set({
    'combined_emotion': combinedEmotion,
    'timestamp': DateTime.now().toIso8601String(),
    'recommendation': recommendation,
  });
}
}

// Notification detail screen
class NotificationDetailScreen extends StatelessWidget {
  final String title;
  final String body;

  const NotificationDetailScreen(
      {super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Text(body, style: const TextStyle(fontSize: 18)),
      ),
    );
  }
}

class RecentEmotionScreen extends StatefulWidget {
  final String emotion;
  final String emoji;

  const RecentEmotionScreen({
    super.key,
    required this.emotion,
    required this.emoji,
    required suggestion,
  });

  @override
  State<RecentEmotionScreen> createState() => _RecentEmotionScreenState();
}

class _RecentEmotionScreenState extends State<RecentEmotionScreen> {
  String recommendation = 'Fetching recommendation...';

  @override
  void initState() {
    super.initState();
    _fetchRecommendation();
  }

  Future<void> _fetchRecommendation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        recommendation = 'User not signed in.';
      });
      return;
    }

    try {
      final uri =
          Uri.parse("https://9fe08568a31e.ngrok-free.app/get_recommendation");
      final request = http.MultipartRequest('POST', uri)
        ..fields['emotion'] = widget.emotion
        ..fields['uid'] = user.uid;

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      final decoded = jsonDecode(responseBody);

      setState(() {
        recommendation =
            decoded['recommendation'] ?? 'No recommendation available';
      });
    } catch (e) {
      setState(() {
        recommendation = 'Error fetching recommendation: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final capitalizedEmotion = widget.emotion.isNotEmpty
        ? '${widget.emotion[0].toUpperCase()}${widget.emotion.substring(1)}'
        : '';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Recent Emotion"),
        backgroundColor: const Color(0xFF6A1B9A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Emotion Card
            Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const Text(
                      "Recent Emotion",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.emoji.isNotEmpty
                          ? "${widget.emoji} $capitalizedEmotion"
                          : "No emotion detected.",
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),

            // Recommendation Card
            Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Recommended System",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6A1B9A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      recommendation,
                      style: const TextStyle(
                        fontSize: 16,
                        fontStyle: FontStyle.italic,
                        color: Colors.black87,
                      ),
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
}

// Combined emotion totals fetching
Future<Map<String, double>> fetchCombineEmotionTotals(String uid) async {
  final ref = FirebaseDatabase.instance
      .ref()
      .child('emotion_logs')
      .child('history')
      .child(uid);

  final snapshot = await ref.get();
  print('Snapshot exists: ${snapshot.exists}');
  print('Snapshot value: ${snapshot.value}');
  if (!snapshot.exists || snapshot.value == null) return {};

  final data = snapshot.value;
  if (data is! Map) return {};

  final Map<dynamic, dynamic> mapData = Map<dynamic, dynamic>.from(data);
  print('Data keys: ${mapData.keys}');
  final Map<String, double> emotionTotals = {};

  for (var entry in mapData.values) {
    if (entry is! Map) {
      print('Entry is not a Map, skipping: $entry');
      continue;
    }
    final entryMap = Map<dynamic, dynamic>.from(entry);
    print('EntryMap: $entryMap');
    if (entryMap.containsKey('combined_emotion')) {
      final combined = entryMap['combined_emotion'];
      if (combined is Map) {
        print('Combined: $combined');
        combined.forEach((emo, score) {
          double value = (score is int)
              ? score.toDouble()
              : (score is double)
                  ? score
                  : 0.0;
          emotionTotals[emo] = (emotionTotals[emo] ?? 0) + value;
        });
      }
    }
  }
  print('EmotionTotals: $emotionTotals');
  return emotionTotals;
}

Future<Map<String, double>> fetchFilteredCombineEmotionTotals(String uid,
    {String period = 'all'}) async {
  final ref = FirebaseDatabase.instance
      .ref()
      .child('emotion_logs')
      .child('history')
      .child(uid);

  final snapshot = await ref.get();
  if (!snapshot.exists || snapshot.value == null) return {};

  final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
  final Map<String, double> emotionTotals = {};

  final now = DateTime.now();

  for (var entry in data.values) {
    final combined = entry['combined_emotion'] as Map?;
    final timestampStr = entry['timestamp'] ?? entry['date'] ?? '';
    DateTime? date;
    try {
      date = DateTime.parse(timestampStr);
    } catch (_) {
      date = null;
    }

    bool include = true;
    if (period == 'daily' && date != null) {
      include = date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
    } else if (period == 'weekly' && date != null) {
      final weekAgo = now.subtract(const Duration(days: 7));
      include = date.isAfter(weekAgo);
    } else if (period == 'monthly' && date != null) {
      include = date.year == now.year && date.month == now.month;
    }

    if (combined != null && include) {
      combined.forEach((emo, score) {
        final emoStr = emo.toString().toLowerCase();
        final scoreDouble =
            (score is int) ? score.toDouble() : (score as double);
        emotionTotals[emoStr] = (emotionTotals[emoStr] ?? 0) + scoreDouble;
      });
    }
  }
  return emotionTotals;
}

Future<Map<String, double>> fetchHomeChartTotals(String uid) async {
  final ref = FirebaseDatabase.instance
      .ref()
      .child('emotion_logs')
      .child('history')
      .child(uid);

  final snapshot = await ref.get();
  print('Snapshot exists: ${snapshot.exists}');
  print('Snapshot value: ${snapshot.value}');
  if (!snapshot.exists || snapshot.value == null) return {};

  final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
  print('Data keys: ${data.keys}');
  final Map<String, double> emotionTotals = {};

  for (var entry in data.values) {
    final entryMap = Map<dynamic, dynamic>.from(entry);
    print('EntryMap: $entryMap');
    if (entryMap.containsKey('combined_emotion')) {
      final combined = Map<String, dynamic>.from(entryMap['combined_emotion']);
      print('Combined: $combined');
      combined.forEach((emo, score) {
        double value = (score is int) ? score.toDouble() : score;
        emotionTotals[emo] = (emotionTotals[emo] ?? 0) + value;
      });
    }
  }
  print('EmotionTotals: $emotionTotals');
  return emotionTotals;
}
