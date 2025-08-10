import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class EmotionPieChart extends StatelessWidget {
  final Map<String, double> emotionTotals;
  final Map<String, Color> emotionColors;

  const EmotionPieChart({
    super.key,
    required this.emotionTotals,
    required this.emotionColors,
  });

  @override
  Widget build(BuildContext context) {
    if (emotionTotals.isEmpty) {
      return const Center(child: Text('No data for pie chart.'));
    }
    final emotions = emotionTotals.keys.toList();
    final values = emotionTotals.values.toList();
    final total = values.fold(0.0, (a, b) => a + b);

    return Column(
      children: [
        // LEGEND FIRST
        buildLegend(emotionTotals, emotionColors),
        // PIE CHART
        Padding(
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
        ),
      ],
    );
  }

  // Legend Widget (use inside EmotionPieChart or anywhere)
  Widget buildLegend(Map<String, double> emotionTotals, Map<String, Color> emotionColors) {
    final emotions = emotionTotals.keys.toList();
    if (emotions.isEmpty) return const SizedBox();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Wrap(
        spacing: 18,
        runSpacing: 10,
        children: emotions.map((emo) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: (emotionColors[emo] ?? Colors.deepPurple).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: emotionColors[emo] ?? Colors.deepPurple,
                width: 1.2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: emotionColors[emo] ?? Colors.deepPurple,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  emo[0].toUpperCase() + emo.substring(1),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}