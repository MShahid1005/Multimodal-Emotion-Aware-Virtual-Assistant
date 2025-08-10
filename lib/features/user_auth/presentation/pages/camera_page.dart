import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CameraPage extends StatefulWidget {
  final String apiUrl;
  const CameraPage({super.key, required this.apiUrl});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  List<CameraDescription>? cameras;
  CameraController? controller;
  int selectedCameraIdx = 0;
  bool isCameraInitialized = false;
  bool _isRecording = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndInitCamera();
  }

  Future<void> _requestPermissionsAndInitCamera() async {
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();
    if (cameraStatus.isGranted && micStatus.isGranted) {
      _initCamera();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera and microphone permissions are required.')),
        );
      }
    }
  }

  Future<void> _initCamera() async {
    cameras = await availableCameras();
    if (cameras == null || cameras!.isEmpty) return;
    _onNewCameraSelected(cameras![selectedCameraIdx]);
  }

  Future<void> _onNewCameraSelected(CameraDescription cameraDescription) async {
    final prevController = controller;
    controller = CameraController(
      cameraDescription,
      ResolutionPreset.max,
      enableAudio: true,
    );
    await prevController?.dispose();
    try {
      await controller!.initialize();
      setState(() {
        isCameraInitialized = true;
      });
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  void _switchCamera() {
    if (cameras == null || cameras!.length < 2) return;
    selectedCameraIdx = (selectedCameraIdx + 1) % cameras!.length;
    _onNewCameraSelected(cameras![selectedCameraIdx]);
  }

  Future<void> _uploadVideo(String videoPath) async {
    setState(() => _isUploading = true);
    final uri = Uri.parse('${widget.apiUrl}/analyze');
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not signed in.')),
        );
        return;
      }
      final request = http.MultipartRequest('POST', uri)
        ..files.add(await http.MultipartFile.fromPath('video', videoPath))
        ..fields['uid'] = user.uid;
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      // Debug: Print server response
      debugPrint('Server response status: ${response.statusCode}');
      debugPrint('Server response body: $responseBody');

      if (response.statusCode == 200) {
        final decoded = jsonDecode(responseBody);
        // Debug: Print decoded emotions
        debugPrint('Decoded emotions: $decoded');
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EmotionResultScreen(emotions: decoded),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Server error: $responseBody')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e')),
      );
      debugPrint('Upload failed: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fullscreen camera preview
          controller != null && isCameraInitialized
              ? CameraPreview(controller!)
              : const Center(child: CircularProgressIndicator()),
          // Top-left back button
          Positioned(
            top: 36,
            left: 16,
            child: SafeArea(
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          // Bottom controls (record and switch)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Record/Stop button (centered)
                  GestureDetector(
                    onTap: !_isUploading && isCameraInitialized
                        ? () async {
                            if (_isRecording) {
                              final videoFile = await controller!.stopVideoRecording();
                              setState(() => _isRecording = false);
                              debugPrint('Video recorded at: ${videoFile.path}');
                              await _uploadVideo(videoFile.path);
                            } else {
                              await controller!.startVideoRecording();
                              setState(() => _isRecording = true);
                              debugPrint('Started video recording');
                            }
                          }
                        : null,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red : Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: _isRecording ? Colors.redAccent : Colors.white,
                          width: 4,
                        ),
                      ),
                      child: Center(
                        child: _isUploading
                            ? const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              )
                            : Icon(
                                _isRecording ? Icons.stop : Icons.videocam,
                                color: _isRecording ? Colors.white : Colors.black,
                                size: 36,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 32),
                  // Camera switch button (right)
                  FloatingActionButton(
                    heroTag: "switch_camera",
                    mini: true,
                    backgroundColor: Colors.white70,
                    child: const Icon(Icons.cameraswitch, color: Colors.black, size: 28),
                    onPressed: _switchCamera,
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

// ================== EmotionResultScreen  ==================

class EmotionResultScreen extends StatefulWidget {
  final Map<String, dynamic> emotions;

  const EmotionResultScreen({super.key, required this.emotions});

  @override
  State<EmotionResultScreen> createState() => _EmotionResultScreenState();
}

class _EmotionResultScreenState extends State<EmotionResultScreen> {
  List<Widget> _buildEmotionWidgets() {
    final List<Widget> widgets = [];
    debugPrint('Building emotion widgets for: ${widget.emotions}');
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
          debugPrint('Emotion: $emo, Score: $score');
          widgets.add(ListTile(
            title: Text(emo),
            trailing: Text('${(score * 100).toStringAsFixed(2)}%'),
          ));
        });
      } else {
        debugPrint('Category $category is not a Map: $data');
      }
    });
    return widgets;
  }

  String? _dominantEmotion;
  double? _dominantScore;

  @override
  void initState() {
    super.initState();
    _extractDominantEmotion();
  }

  void _extractDominantEmotion() {
    // "combined" category se dominant emotion nikaalna hai
    final combined = widget.emotions['combined'];
    if (combined is Map<String, dynamic>) {
      String? maxEmotion;
      double? maxScore;
      combined.forEach((emotion, score) {
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
        if (maxScore == null || scoreDouble > (maxScore ?? 0.0)) {
          maxScore = scoreDouble;
          maxEmotion = emotion;
        }
      });
      setState(() {
        _dominantEmotion = maxEmotion;
        _dominantScore = maxScore;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detected Emotions'),
        backgroundColor: const Color(0xFF6A1B9A),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            if (_dominantEmotion != null)
              Card(
                color: Colors.deepPurple.shade50,
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: const Icon(Icons.emoji_emotions, color: Colors.deepPurple, size: 36),
                  title: Text(
                    'Dominant Emotion: ${_dominantEmotion![0].toUpperCase()}${_dominantEmotion!.substring(1)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  subtitle: Text(
                    'Score: ${(_dominantScore! * 100).toStringAsFixed(2)}%',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ..._buildEmotionWidgets(),
          ],
        ),
      ),
    );
  }
}

// Example usage after emotion detection:
// await saveEmotionToFirebase(combinedEmotionMap, recommendationString);