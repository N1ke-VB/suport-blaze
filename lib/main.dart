import 'dart:io';
import 'dart:typed_data';

import 'package:face_detection_tflite/face_detection_tflite.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FaceMatchApp());
}

class FaceMatchApp extends StatelessWidget {
  const FaceMatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Face ID Match',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF4A7DFF),
        brightness: Brightness.dark,
      ),
      home: const FaceMatchPage(),
    );
  }
}

class FaceMatchPage extends StatefulWidget {
  const FaceMatchPage({super.key});

  @override
  State<FaceMatchPage> createState() => _FaceMatchPageState();
}

class _FaceMatchPageState extends State<FaceMatchPage> {
  final ImagePicker _picker = ImagePicker();
  FaceDetector? _detector;

  XFile? _documentImage;
  XFile? _selfieImage;
  Float32List? _documentEmbedding;
  Float32List? _selfieEmbedding;

  bool _loading = false;
  String _status = 'Scanează întâi permisul.';
  double? _similarity;

  static const double _matchThreshold = 0.60;

  Future<FaceDetector> _getDetector() async {
    if (_detector != null) return _detector!;

    _detector = await FaceDetector.create(
      model: FaceDetectionModel.backCamera,
      minScore: 0.65,
      minFaceSize: 0.08,
    );
    return _detector!;
  }

  Future<Float32List> _embeddingFor(
    XFile image, {
    required bool requireSingleFace,
  }) async {
    final detector = await _getDetector();
    final bytes = await image.readAsBytes();

    final faces = await detector.detectFacesFromBytes(
      bytes,
      mode: FaceDetectionMode.full,
    );

    if (faces.isEmpty) {
      throw Exception('Nu am detectat nicio față. Încearcă din nou cu lumină mai bună.');
    }

    if (requireSingleFace && faces.length != 1) {
      throw Exception('În selfie trebuie să fie vizibilă o singură persoană.');
    }

    faces.sort((a, b) {
      final areaA = a.boundingBox.width * a.boundingBox.height;
      final areaB = b.boundingBox.width * b.boundingBox.height;
      return areaB.compareTo(areaA);
    });

    return detector.getFaceEmbedding(faces.first, bytes);
  }

  Future<void> _scanDocument() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
      imageQuality: 92,
      maxWidth: 2400,
    );
    if (image == null) return;

    await _runBusy(() async {
      setState(() => _status = 'Detectez fotografia de pe permis...');
      final embedding = await _embeddingFor(image, requireSingleFace: false);

      setState(() {
        _documentImage = image;
        _documentEmbedding = embedding;
        _selfieImage = null;
        _selfieEmbedding = null;
        _similarity = null;
        _status = 'Permisul este pregătit. Acum fă selfie-ul.';
      });
    });
  }

  Future<void> _takeSelfie() async {
    if (_documentEmbedding == null) {
      _showMessage('Scanează întâi permisul.');
      return;
    }

    final image = await _picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      imageQuality: 92,
      maxWidth: 2000,
    );
    if (image == null) return;

    await _runBusy(() async {
      setState(() => _status = 'Analizez selfie-ul...');
      final embedding = await _embeddingFor(image, requireSingleFace: true);

      final similarity = FaceDetector.compareFaces(
        _documentEmbedding!,
        embedding,
      );

      setState(() {
        _selfieImage = image;
        _selfieEmbedding = embedding;
        _similarity = similarity;
        _status = similarity >= _matchThreshold
            ? 'Fața este compatibilă cu fotografia documentului.'
            : 'Fața nu trece pragul de similitudine.';
      });
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      await action();
    } catch (error) {
      final message = error.toString().replaceFirst('Exception: ', '');
      setState(() => _status = message);
      _showMessage(message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _reset() {
    setState(() {
      _documentImage = null;
      _selfieImage = null;
      _documentEmbedding = null;
      _selfieEmbedding = null;
      _similarity = null;
      _status = 'Scanează întâi permisul.';
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _detector?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rawScore = _similarity;
    final match = rawScore != null && rawScore >= _matchThreshold;
    final displayPercent = rawScore == null
        ? null
        : ((rawScore.clamp(0.0, 1.0)) * 100).toStringAsFixed(1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face ID Match'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Icon(Icons.verified_user_outlined, size: 72),
            const SizedBox(height: 10),
            const Text(
              'Verificare identitate',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Demo local: permis + selfie. Imaginile nu sunt încărcate pe un server.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _ImageCard(
              title: '1. Permis de conducere',
              image: _documentImage,
              icon: Icons.badge_outlined,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _loading ? null : _scanDocument,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scanează permisul'),
            ),
            const SizedBox(height: 24),
            _ImageCard(
              title: '2. Selfie',
              image: _selfieImage,
              icon: Icons.face_outlined,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _loading ? null : _takeSelfie,
              icon: const Icon(Icons.camera_front_outlined),
              label: const Text('Fă selfie'),
            ),
            const SizedBox(height: 22),
            if (_loading) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 12),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    if (rawScore != null) ...[
                      const SizedBox(height: 18),
                      Icon(
                        match ? Icons.verified : Icons.cancel_outlined,
                        size: 54,
                        color: match ? Colors.greenAccent : Colors.redAccent,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        match ? 'MATCH' : 'NO MATCH',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: match ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                      Text(
                        '$displayPercent%',
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text('Scor brut: ${rawScore.toStringAsFixed(4)}'),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _loading ? null : _reset,
              icon: const Icon(Icons.refresh),
              label: const Text('Resetează'),
            ),
            const SizedBox(height: 14),
            const Text(
              'Notă: acesta este un prototip, nu un sistem KYC certificat. Pentru utilizare reală trebuie adăugate liveness/anti-spoofing, validarea documentului și calibrarea pragurilor.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageCard extends StatelessWidget {
  const _ImageCard({
    required this.title,
    required this.image,
    required this.icon,
  });

  final String title;
  final XFile? image;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: image == null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 58, color: Colors.white54),
                const SizedBox(height: 12),
                Text(title),
              ],
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                Image.file(File(image!.path), fit: BoxFit.cover),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(title),
                  ),
                ),
              ],
            ),
    );
  }
}
