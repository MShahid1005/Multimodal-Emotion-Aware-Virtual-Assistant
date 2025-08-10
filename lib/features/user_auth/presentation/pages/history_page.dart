import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'emotion_pie_chart.dart'; // path update karein

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  Timer? _emotionTimer;

  List<Map<dynamic, dynamic>> _history = [];
  bool _loading = true;

  // Chart and filter controls
  int _selectedPeriodIndex = 0; // 0 = Daily, 1 = Weekly, 2 = Monthly

  // Unique color for each emotion (all different)
  final Map<String, Color> emotionColors = {
    'neutral': const Color(0xFFBDBDBD),    // Grey
    'fearful': const Color(0xFF00B8D4),    // Cyan
    'surprise': const Color(0xFFFFEA00),   // Yellow
    'sad': const Color(0xFF2979FF),        // Blue
    'angry': const Color(0xFFD50000),      // Red
    'happy': const Color(0xFFFFD600),      // Amber
    'disgust': const Color(0xFF43A047),    // Green
    'surprised': const Color(0xFFFF6D00),  // Orange
    'calm': const Color(0xFF8E24AA),       // Purple
  };

  Map<String, double> _emotionTotals = {};

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    _startEmotionNotificationTimer();
  }

  @override
  void dispose() {
    _emotionTimer?.cancel();
    super.dispose();
  }

  void _startEmotionNotificationTimer() {
    _emotionTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final ref = FirebaseDatabase.instance
          .ref()
          .child('emotion_logs')
          .child('history')
          .child(user.uid);

      final snapshot = await ref.get();

      if (snapshot.exists && snapshot.value != null) {
        final data = Map<dynamic, dynamic>.from(snapshot.value as Map);

        Map<String, double> emotionTotals = {};
        data.forEach((key, value) {
          final entry = Map<dynamic, dynamic>.from(value);
          if (entry.containsKey('combined_emotion')) {
            final combined = Map<String, dynamic>.from(entry['combined_emotion']);
            combined.forEach((emotion, score) {
              double value = (score is int) ? score.toDouble() : score;
              emotionTotals[emotion] = (emotionTotals[emotion] ?? 0) + value;
            });
          }
        });

        if (emotionTotals.isNotEmpty) {
          final dominant = emotionTotals.entries
              .reduce((a, b) => a.value > b.value ? a : b)
              .key;

          String recommendation = '';
          data.forEach((key, value) {
            final entry = Map<dynamic, dynamic>.from(value);
            if (entry.containsKey('emotion') &&
                entry['emotion'] == dominant &&
                entry['recommendation'] != null) {
              recommendation = entry['recommendation'];
            }
          });

          _showDominantEmotionNotification(dominant, recommendation);
        }
      }
    });
  }

  void _showDominantEmotionNotification(String emotion, String recommendation) async {
    // Notification logic here (omitted for brevity)
  }

  void _fetchHistory() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseDatabase.instance
        .ref()
        .child('emotion_logs')
        .child('history')
        .child(user.uid);

    final snapshot = await ref.get();

    final List<Map<dynamic, dynamic>> history = [];
    Map<String, double> emotionTotals = {};
    if (snapshot.exists && snapshot.value != null) {
      final data = snapshot.value;
      if (data is Map) {
        data.forEach((key, value) {
          if (value is! Map) return; // <-- Skip if not a Map
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
              // For chart: sum all emotions
              combined.forEach((emo, score) {
                double value = (score is int) ? score.toDouble() : (score is double) ? score : 0.0;
                emotionTotals[emo] = (emotionTotals[emo] ?? 0) + value;
              });
            }
          }
        });
      }
    }

    setState(() {
      _history = history.reversed.toList(); // latest first
      _emotionTotals = emotionTotals;
      _loading = false;
    });
  }

  // Filter history by period (daily, weekly, monthly)
  Map<String, double> _getFilteredEmotionTotals() {
    final now = DateTime.now();
    Map<String, double> filteredTotals = {};

    for (var item in _history) {
      final dateStr = item['date'] ?? '';
      print('History date: $dateStr');
      DateTime? date;
      try {
        date = DateTime.parse(dateStr);
      } catch (_) {
        continue;
      }
      bool include = false;
      if (_selectedPeriodIndex == 0) {
        // Daily
        include = date.year == now.year && date.month == now.month && date.day == now.day;
      } else if (_selectedPeriodIndex == 1) {
        // Weekly
        final weekAgo = now.subtract(const Duration(days: 7));
        include = date.isAfter(weekAgo);
      } else {
        // Monthly
        include = date.year == now.year && date.month == now.month;
      }
      if (include) {
        final emo = item['emotion'];
        final score = (item['score'] ?? 0.0).toDouble();
        filteredTotals[emo] = (filteredTotals[emo] ?? 0) + score;
      }
    }
    return filteredTotals;
  }

  Widget _buildPieChart(Map<String, double> emotionTotals) {
    if (emotionTotals.isEmpty) {
      return const Center(child: Text('No data for pie chart.'));
    }
    final emotions = emotionTotals.keys.toList();
    final values = emotionTotals.values.toList();
    final total = values.fold(0.0, (a, b) => a + b);

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: AspectRatio(
        aspectRatio: 1.5,
        child: PieChart(
          PieChartData(
            sections: List.generate(
              emotions.length,
              (i) => PieChartSectionData(
                color: emotionColors[emotions[i]] ?? Colors.deepPurple,
                value: values[i],
                title: '${((values[i] / total) * 100).toStringAsFixed(1)}%',
                radius: 100,
                titleStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 12,
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
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmotionCard(Map<dynamic, dynamic> item) {
    final String emotion = item['emotion'] ?? 'Unknown';
    final double score = (item['score'] ?? 0.0).toDouble();
    final String date = item['date']?.toString() ?? 'No Date';
    final String recommendation = item['recommendation'] ?? 'No recommendation';

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.history, color: Color(0xFF283593)),
        title: Text(
          '$emotion (${(score * 100).toStringAsFixed(1)}%)',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📅 Date: $date'),
            const SizedBox(height: 4),
            Text('💡 $recommendation'),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredTotals = _getFilteredEmotionTotals();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emotion History'),
        backgroundColor: const Color(0xFF283593),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(child: Text('No emotion history found.'))
              : Column(
                children: [
                  EmotionPieChart(
                    emotionTotals: filteredTotals,
                    emotionColors: emotionColors,
                  ),
                  const Divider(height: 1, thickness: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _history.length,
                      itemBuilder: (context, index) {
                        return _buildEmotionCard(_history[index]);
                      },
                    ),
                  ),
                ],
              ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedPeriodIndex,
        selectedItemColor: const Color(0xFF6A1B9A),
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            _selectedPeriodIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_today),
            label: 'Daily',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_view_week),
            label: 'Weekly',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_view_month),
            label: 'Monthly',
          ),
        ],
      ),
    );
  }
}
