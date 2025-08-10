import 'package:flutter/material.dart';

/// Singleton to store the last notification values
class LastNotificationState {
  static String? emotion;
  static double? score;
  static String? date;
  static String? recommendation;

  static void update({
    required String emotion,
    required double score,
    required String date,
    required String recommendation,
  }) {
    LastNotificationState.emotion = emotion;
    LastNotificationState.score = score;
    LastNotificationState.date = date;
    LastNotificationState.recommendation = recommendation;
  }
}

class RecentEmotionCard extends StatelessWidget {
  const RecentEmotionCard({super.key, required emotionName, required double score, required date, required recommendation});

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

  @override
  Widget build(BuildContext context) {
    final emotion = LastNotificationState.emotion ?? '';
    final score = LastNotificationState.score ?? 0.0;
    final date = LastNotificationState.date ?? '';
    final recommendation = LastNotificationState.recommendation ?? '';

    if (emotion.isEmpty) return const SizedBox();
    final emoji = _emotionEmoji(emotion);

    return Card(
      elevation: 8,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: const Color(0xFF6A1B9A).withOpacity(0.13),
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your Lasts Emotion is: $emoji ${emotion[0].toUpperCase()}${emotion.substring(1)} (${(score * 100).toStringAsFixed(1)}%)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (date.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Date: $date', style: const TextStyle(fontSize: 15)),
            ],
            if (recommendation.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Suggestion: $recommendation', style: const TextStyle(fontSize: 15)),
            ],
          ],
        ),
      ),
    );
  }
}