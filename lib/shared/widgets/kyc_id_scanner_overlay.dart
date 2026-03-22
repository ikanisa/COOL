import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/cool_palette.dart';
import '../../core/utils/privacy_redactor.dart';
import '../../shared/widgets/cool_button.dart';

class KycIdScannerOverlay extends StatefulWidget {
  const KycIdScannerOverlay({
    required this.title,
    this.instruction = 'Align your ID within the frame',
    super.key,
  });

  final String title;
  final String instruction;

  @override
  State<KycIdScannerOverlay> createState() => _KycIdScannerOverlayState();
}

class _KycIdScannerOverlayState extends State<KycIdScannerOverlay> {
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

    // Use back camera for ID scanning
    final backCamera = _cameras!.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras!.first,
    );

    _controller = CameraController(
      backCamera,
      ResolutionPreset.max, // Optimum for OCR accuracy
      enableAudio: false,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('Camera initialization failed: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) {
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
    } catch (e) {
      setState(() {
        _isCapturing = false;
      });
      debugPrint('Error taking picture: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: Text(
          widget.title,
          style: GoogleFonts.dmSans(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _capturedPath != null
          ? _buildPreview(palette)
          : _isInitialized
              ? _buildCameraStack(palette)
              : Center(child: CircularProgressIndicator(color: palette.accent)),
    );
  }

  Widget _buildCameraStack(CoolPalette palette) {
    return Stack(
      children: [
        Positioned.fill(
          child: CameraPreview(_controller!),
        ),

        // Rectangular ID Overlay
        Positioned.fill(
          child: CustomPaint(
            painter: _IdOverlayPainter(accentColor: palette.accent),
          ),
        ),

        // Privacy Guard indicators
        Positioned.fill(
          child: CustomPaint(
            painter: _PrivacyRedactionPainter(),
          ),
        ),

        // Soft Liquid Glass Guidance
        Positioned(
          top: 60,
          left: 40,
          right: 40,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield_rounded, color: Colors.white, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'PRIVACY GUARD ACTIVE',
                      style: GoogleFonts.dmSans(
                        color: palette.accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.instruction,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Capture Button
        Positioned(
          bottom: 60,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _takePicture,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 3),
                    ),
                  ),
                  Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: _isCapturing 
                      ? Center(child: CircularProgressIndicator(color: palette.blue))
                      : const Icon(Icons.camera_alt, color: Colors.black),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(CoolPalette palette) {
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: palette.accent.withValues(alpha: 0.5), width: 2),
              image: DecorationImage(
                image: FileImage(File(_capturedPath!)),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 60),
          child: Column(
            children: [
              Text(
                'Is the information readable?',
                style: GoogleFonts.dmSans(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              CoolButton(
                label: 'Confirm & Extract',
                icon: Icons.auto_awesome,
                onTap: () {
                  Navigator.of(context).pop(XFile(_capturedPath!));
                },
              ),
              const SizedBox(height: 12),
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

class _IdOverlayPainter extends CustomPainter {
  _IdOverlayPainter({required this.accentColor});
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;

    // Standard ID card aspect ratio is 1.58
    const aspectRatio = 1.58;
    final rectWidth = size.width * 0.85;
    final rectHeight = rectWidth / aspectRatio;
    
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: rectWidth,
      height: rectHeight,
    );

    final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(20));

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(rRect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);

    // Liquid glass glowing border
    final borderPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRRect(rRect, borderPaint);

    // Corner guides
    final guidePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    const guideSize = 30.0;
    
    // Top Left
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top + guideSize)
        ..lineTo(rect.left, rect.top)
        ..lineTo(rect.left + guideSize, rect.top),
      guidePaint,
    );
    
    // Top Right
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - guideSize, rect.top)
        ..lineTo(rect.right, rect.top)
        ..lineTo(rect.right, rect.top + guideSize),
      guidePaint,
    );
    
    // Bottom Left
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.bottom - guideSize)
        ..lineTo(rect.left, rect.bottom)
        ..lineTo(rect.left + guideSize, rect.bottom),
      guidePaint,
    );
    
    // Bottom Right
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - guideSize, rect.bottom)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(rect.right, rect.bottom - guideSize),
      guidePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PrivacyRedactionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final regions = PrivacyRedactor.getSensitiveRegions(size.width, size.height);
    
    for (final region in regions) {
      final rect = Rect.fromLTWH(region.left, region.top, region.width, region.height);
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, borderPaint);
      
      // Draw text label "BLURRED"
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'LOCAL BLUR',
          style: TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(region.left + 4, region.top + 4));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
