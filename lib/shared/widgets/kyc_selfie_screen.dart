import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import 'cool_button.dart';

class KycSelfieScreen extends StatefulWidget {
  const KycSelfieScreen({super.key});

  @override
  State<KycSelfieScreen> createState() => _KycSelfieScreenState();
}

class _KycSelfieScreenState extends State<KycSelfieScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCapturing = false;
  String? _capturedPath;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    if (_cameras == null || _cameras!.isEmpty) return;

    final frontCamera = _cameras!.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras!.first,
    );

    _controller = CameraController(
      frontCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (error) {
      debugPrint('Camera initialization failed: $error');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      final image = await _controller!.takePicture();
      setState(() {
        _capturedPath = image.path;
        _isCapturing = false;
      });
    } catch (error) {
      setState(() {
        _isCapturing = false;
      });
      debugPrint('Error taking picture: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: Text(
          'KYC Selfie',
          style: textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _capturedPath != null
          ? _buildPreview()
          : _isInitialized
          ? _buildCameraStack(colors, textTheme)
          : Center(child: CircularProgressIndicator(color: colors.accent)),
    );
  }

  Widget _buildCameraStack(CoolSemanticColors colors, TextTheme textTheme) {
    return Stack(
      children: [
        Positioned.fill(child: CameraPreview(_controller!)),
        Positioned.fill(
          child: CustomPaint(
            painter: _OvalOverlayPainter(accentColor: colors.accent),
          ),
        ),
        Positioned(
          bottom: 140,
          left: 0,
          right: 0,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: CoolSpace.x5,
                  vertical: CoolSpace.x2 + 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(CoolRadii.pill),
                  ),
                ),
                child: Text(
                  'Position your face inside',
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _takePicture,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                ),
                child: Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: _isCapturing
                        ? Center(
                            child: CircularProgressIndicator(
                              color: colors.info,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview() {
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(CoolSpace.x5),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(
                Radius.circular(CoolRadii.md - 2),
              ),
              image: DecorationImage(
                image: FileImage(File(_capturedPath!)),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CoolSpace.x5,
            0,
            CoolSpace.x5,
            CoolSpace.x8,
          ),
          child: Column(
            children: [
              CoolButton(
                label: 'Confirm & Continue',
                onTap: () {
                  Navigator.of(context).pop(_capturedPath);
                },
              ),
              const SizedBox(height: CoolSpace.x3),
              CoolButton(
                label: 'Retake',
                variant: CoolButtonVariant.secondary,
                onTap: () {
                  setState(() {
                    _capturedPath = null;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OvalOverlayPainter extends CustomPainter {
  _OvalOverlayPainter({required this.accentColor});

  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;

    final ovalWidth = size.width * 0.7;
    final ovalHeight = size.height * 0.5;
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 20),
      width: ovalWidth,
      height: ovalHeight,
    );

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addOval(ovalRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawOval(ovalRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
