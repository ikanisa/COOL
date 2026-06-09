import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../shared/repositories/collect_repository.dart';
import '../../shared/providers/collect_app_state.dart';
import '../../shared/widgets/collect_components.dart';
import '../../shared/widgets/screen_scaffold.dart';
import 'group_link_screen.dart';

class GroupQrScannerScreen extends ConsumerStatefulWidget {
  const GroupQrScannerScreen({super.key});

  @override
  ConsumerState<GroupQrScannerScreen> createState() =>
      _GroupQrScannerScreenState();
}

class _GroupQrScannerScreenState extends ConsumerState<GroupQrScannerScreen> {
  late final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
    autoZoom: true,
    autoStart: false,
  );
  bool _joining = false;
  bool _scanning = false;
  bool _starting = false;
  String? _error;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenScaffold(
      title: 'Scan QR',
      bottomAction: BottomActionSurface(
        children: [
          CollectButton(
            label: _joining
                ? 'Opening'
                : _starting
                ? 'Starting'
                : 'Scan',
            icon: CollectIcons.qr,
            onPressed: _joining || _starting || _scanning
                ? null
                : _startScanning,
            expand: true,
          ),
        ],
      ),
      children: [
        CollectCard(
          padding: EdgeInsets.zero,
          emphasis: CollectCardEmphasis.glow,
          child: AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: CollectRadius.cardLargeBorder,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    controller: _scanner,
                    fit: BoxFit.cover,
                    tapToFocus: true,
                    onDetect: _onDetect,
                    errorBuilder: (context, error) =>
                        _ScannerUnavailable(error: error.errorDetails?.message),
                  ),
                  const _ScanGuide(),
                  if (!_scanning && !_starting && !_joining)
                    const _ScannerIdleOverlay(),
                  if (_starting)
                    ColoredBox(
                      color: context.collectColors.cameraScrim,
                      child: const Center(
                        child: LoadingStatePanel(
                          title: 'Starting camera',
                          message: '',
                          icon: CollectIcons.qr,
                          lines: 1,
                        ),
                      ),
                    ),
                  if (_joining)
                    ColoredBox(
                      color: context.collectColors.cameraScrim,
                      child: const Center(
                        child: LoadingStatePanel(
                          title: 'Opening group',
                          message: 'Checking QR code.',
                          icon: CollectIcons.qr,
                          lines: 1,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_error != null)
          InfoSecurityBanner(
            title: 'QR code failed',
            message: _error!,
            tone: CollectStatusTone.danger,
          ),
      ],
    );
  }

  Future<void> _startScanning() async {
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      await _scanner.start();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _scanning = true;
      });
    } catch (error) {
      if (!mounted) return;
      ref.read(cameraPermissionStatusProvider.notifier).state =
          CollectDevicePermissionStatus.denied;
      setState(() {
        _starting = false;
        _scanning = false;
        _error = error.toString();
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_joining || !_scanning) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _openValue(value);
        return;
      }
    }
  }

  Future<void> _openValue(String value) async {
    final slug = collectGroupSlugFromInput(value);
    if (slug.isEmpty) {
      setState(() => _error = 'Use a Collect group QR code.');
      return;
    }
    setState(() {
      _joining = true;
      _error = null;
    });
    await _scanner.stop();
    try {
      final collection = await ref
          .read(collectRepositoryProvider.notifier)
          .joinGroupBySlug(slug);
      if (!mounted) return;
      context.go('/groups/${collection.id}/joined');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _joining = false;
        _scanning = false;
        _error = error.toString();
      });
    }
  }
}

class _ScannerIdleOverlay extends StatelessWidget {
  const _ScannerIdleOverlay();

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return ColoredBox(
      color: colors.cameraScrimStrong,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.glassPanelStrong,
            borderRadius: CollectRadius.panelBorder,
            border: Border.all(color: colors.glassBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(CollectSpacing.x4),
            child: Icon(CollectIcons.qr, color: colors.actionColor, size: 42),
          ),
        ),
      ),
    );
  }
}

class _ScanGuide extends StatelessWidget {
  const _ScanGuide();

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.all(CollectSpacing.x8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: colors.actionColor.withValues(alpha: 0.9),
              width: 3,
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(CollectSpacing.x4),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.glassPanelStrong,
                  borderRadius: CollectRadius.pillBorder,
                  border: Border.all(color: colors.glassBorder),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CollectSpacing.x4,
                    vertical: CollectSpacing.x2,
                  ),
                  child: Text(
                    'Align QR code',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScannerUnavailable extends StatelessWidget {
  const _ScannerUnavailable({this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = context.collectColors;
    return ColoredBox(
      color: colors.shadowPaint,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(CollectSpacing.x4),
          child: CollectCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InfoSecurityBanner(
                  title: 'Camera unavailable',
                  message: error ?? 'Tap Scan to request camera access.',
                  tone: CollectStatusTone.warning,
                ),
                CollectSpacing.gap16,
                CollectButton(
                  label: 'Recover camera access',
                  icon: CollectIcons.qr,
                  onPressed: () => context.go('/permissions/camera-denied'),
                  expand: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
