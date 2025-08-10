import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'recent_emotion_card.dart'; // path update karein

class EmotionResultScreen extends StatefulWidget {
  final Map<String, dynamic> emotions;

  const EmotionResultScreen({super.key, required this.emotions});

  @override
  State<EmotionResultScreen> createState() => _EmotionResultScreenState();
}

class _EmotionResultScreenState extends State<EmotionResultScreen> {
  @override
  void initState() {
    super.initState();
    _notifyDominantEmotion();
  }

  Future<void> _notifyDominantEmotion() async {
    final combined = widget.emotions['combined'] as Map<String, dynamic>?;

    if (combined != null && combined.isNotEmpty) {
      // Find dominant emotion
      final dominantEntry = combined.entries.reduce((a, b) => a.value > b.value ? a : b);
      final dominantEmotion = dominantEntry.key;

      // Get recommendation from API
      final user = FirebaseAuth.instance.currentUser;
      String recommendation = '';
      if (user != null) {
        final uri = Uri.parse("https://9fe08568a31e.ngrok-free.app/get_recommendation");
        final request = http.MultipartRequest('POST', uri)
          ..fields['emotion'] = dominantEmotion
          ..fields['uid'] = user.uid;
        final response = await request.send();
        final responseBody = await response.stream.bytesToString();
        final decoded = jsonDecode(responseBody);
        recommendation = decoded['recommendation'] ?? '';
      }

      // Show notification
      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      const androidDetails = AndroidNotificationDetails(
        'emotion_channel_id',
        'Emotion Alerts',
        importance: Importance.max,
        priority: Priority.high,
      );
      const notificationDetails = NotificationDetails(android: androidDetails);

      await flutterLocalNotificationsPlugin.show(
        0,
        'Detected Emotion',
        'Aap ka emotion hai: $dominantEmotion\nRecommendation: $recommendation',
        notificationDetails,
        payload: 'show_details',
      );
    }
  }

  MapEntry<String, double>? _getDominantEmotion() {
    // Find the first category with Map data
    for (var value in widget.emotions.values) {
      if (value is Map<String, dynamic> && value.isNotEmpty) {
        final entries = value.entries.map((e) => MapEntry(e.key, (e.value as num).toDouble())).toList();
        entries.sort((a, b) => b.value.compareTo(a.value));
        return entries.first;
      }
    }
    return null;
  }

  List<Widget> _buildEmotionWidgets() {
    final List<Widget> widgets = [];
    widget.emotions.forEach((category, data) {
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          category.replaceAll('_', ' ').toUpperCase(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ));
      if (data is Map<String, dynamic>) {
        data.forEach((emo, score) {
          widgets.add(ListTile(
            title: Text(emo),
            trailing: Text('${(score * 100).toStringAsFixed(2)}%'),
          ));
        });
      } else if (data is String) {
        widgets.add(ListTile(
          title: Text(data),
        ));
      }
    });
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final dominant = _getDominantEmotion();
    final emotion = dominant?.key ?? '';
    final score = dominant?.value ?? 0.0;

    // Optional: Get date/time now
    final date = DateTime.now().toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detected Emotions'),
        backgroundColor: const Color(0xFF6A1B9A),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (emotion.isNotEmpty)
              Column(
                children: [
                  Text(
                    "Aap ka last emotion yeh hai:",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF6A1B9A),
                    ),
                  ),
                  RecentEmotionCard(
                    emotionName: emotion, // Use the correct parameter name
                    score: score,
                    date: date,
                    recommendation: '', // If you have recommendation, pass here
                  ),
                ],
              ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                children: widget.emotions.entries.map((entry) {
                  if (entry.value is Map<String, dynamic>) {
                    final emotionMap = entry.value as Map<String, dynamic>;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.key.replaceAll('_', ' ').toUpperCase(),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        ...emotionMap.entries.map((e) => ListTile(
                              title: Text(e.key),
                              trailing: Text('${((e.value as num) * 100).toStringAsFixed(2)}%'),
                            )),
                        const Divider(),
                      ],
                    );
                  }
                  return const SizedBox();
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Notification detail screen
class NotificationDetailScreen extends StatelessWidget {
  final String title;
  final String body;

  const NotificationDetailScreen({super.key, required this.title, required this.body});

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
