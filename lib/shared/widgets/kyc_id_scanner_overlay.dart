import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../core/theme/cool_foundations.dart';
import '../../core/utils/privacy_redactor.dart';
import 'cool_button.dart';

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

    final backCamera = _cameras!.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => _cameras!.first,
    );

    _controller = CameraController(
      backCamera,
      ResolutionPreset.max,
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
          widget.title,
          style: textTheme.titleMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _capturedPath != null
          ? _buildPreview(context, colors, textTheme)
          : _isInitialized
          ? _buildCameraStack(context, colors, textTheme)
          : Center(child: CircularProgressIndicator(color: colors.accent)),
    );
  }

  Widget _buildCameraStack(
    BuildContext context,
    CoolSemanticColors colors,
    TextTheme textTheme,
  ) {
    return Stack(
      children: [
        Positioned.fill(child: CameraPreview(_controller!)),
        Positioned.fill(
          child: CustomPaint(
            painter: _IdOverlayPainter(accentColor: colors.accent),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(painter: _PrivacyRedactionPainter()),
        ),
        Positioned(
          top: 60,
          left: 40,
          right: 40,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: CoolSpace.x4,
              vertical: CoolSpace.x3,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.all(
                Radius.circular(CoolRadii.sm),
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shield_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'PRIVACY GUARD ACTIVE',
                      style: textTheme.labelMedium?.copyWith(
                        color: colors.accent,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CoolSpace.x1),
                Text(
                  widget.instruction,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
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
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 3,
                      ),
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
                        ? Center(
                            child: CircularProgressIndicator(
                              color: colors.info,
                            ),
                          )
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

  Widget _buildPreview(
    BuildContext context,
    CoolSemanticColors colors,
    TextTheme textTheme,
  ) {
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(CoolSpace.x6),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(
                Radius.circular(CoolRadii.lg - 4),
              ),
              border: Border.all(
                color: colors.accent.withValues(alpha: 0.5),
                width: 2,
              ),
              image: DecorationImage(
                image: FileImage(File(_capturedPath!)),
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            CoolSpace.x6,
            0,
            CoolSpace.x6,
            CoolSpace.x10 - 4,
          ),
          child: Column(
            children: [
              Text(
                'Is the information readable?',
                style: textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: CoolSpace.x6),
              CoolButton(
                label: 'Confirm & Extract',
                icon: Icons.auto_awesome,
                onTap: () {
                  Navigator.of(context).pop(XFile(_capturedPath!));
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

class _IdOverlayPainter extends CustomPainter {
  _IdOverlayPainter({required this.accentColor});

  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.65)
      ..style = PaintingStyle.fill;

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

    final borderPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(rRect, borderPaint);

    final guidePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    const guideSize = 30.0;

    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top + guideSize)
        ..lineTo(rect.left, rect.top)
        ..lineTo(rect.left + guideSize, rect.top),
      guidePaint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(rect.right - guideSize, rect.top)
        ..lineTo(rect.right, rect.top)
        ..lineTo(rect.right, rect.top + guideSize),
      guidePaint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.bottom - guideSize)
        ..lineTo(rect.left, rect.bottom)
        ..lineTo(rect.left + guideSize, rect.bottom),
      guidePaint,
    );

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

    final regions = PrivacyRedactor.getSensitiveRegions(
      size.width,
      size.height,
    );

    for (final region in regions) {
      final rect = Rect.fromLTWH(
        region.left,
        region.top,
        region.width,
        region.height,
      );
      canvas.drawRect(rect, paint);
      canvas.drawRect(rect, borderPaint);

      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'LOCAL BLUR',
          style: TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w900,
          ),
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
