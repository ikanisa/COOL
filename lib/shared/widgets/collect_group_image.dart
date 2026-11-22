import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/collect_group_cover.dart';

/// Uniform rendering for saved library references, uploaded bytes and URLs.
class CollectGroupImage extends StatelessWidget {
  const CollectGroupImage({
    super.key,
    required this.value,
    required this.fallback,
    this.thumbnail = false,
  });
  final String? value;
  final Widget fallback;
  final bool thumbnail;
  @override
  Widget build(BuildContext context) {
    final source = value?.trim();
    final cover = CollectGroupCover.resolve(source);
    if (cover != null) {
      return Image.asset(
        thumbnail ? cover.thumbnail : cover.asset,
        fit: BoxFit.cover,
        cacheWidth: thumbnail ? 192 : 768,
        alignment: Alignment(cover.focalX * 2 - 1, cover.focalY * 2 - 1),
        gaplessPlayback: true,
        errorBuilder: (_, error, stack) => fallback,
      );
    }
    if (source == null || source.isEmpty) return fallback;
    if (source.startsWith('data:image/')) {
      try {
        final bytes = base64Decode(source.substring(source.indexOf(',') + 1));
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          cacheWidth: thumbnail ? 192 : 768,
          gaplessPlayback: true,
          errorBuilder: (_, error, stack) => fallback,
        );
      } catch (_) {
        return fallback;
      }
    }
    final uri = Uri.tryParse(source);
    if (uri == null || !['https', 'http'].contains(uri.scheme)) return fallback;
    return Image.network(
      source,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : fallback,
      errorBuilder: (_, error, stack) => fallback,
    );
  }
}
