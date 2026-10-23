import 'package:flutter/material.dart';

/// Reads the notices bundled by Flutter's build from its license registry. The
/// page inherits Collect's semantic theme and works without a provider request.
class CollectLicensesPage extends StatelessWidget {
  const CollectLicensesPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const LicensePage(applicationName: 'Collect');
}
