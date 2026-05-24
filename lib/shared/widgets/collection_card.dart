import 'package:flutter/material.dart';

import '../models/collect_models.dart';
import 'collect_components.dart';

class CollectionCard extends StatelessWidget {
  const CollectionCard({
    required this.collection,
    required this.summary,
    this.onTap,
    super.key,
  });

  final CollectCollection collection;
  final CollectionSummary summary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return CollectionSummaryCard(
      collection: collection,
      summary: summary,
      onTap: onTap,
    );
  }
}
