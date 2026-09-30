import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin/admin_app.dart';
import 'admin/core/admin_evidence_mode.dart';
import 'core/supabase/supabase_module.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supabase = await createSupabaseClientFromEnvironment();
  runApp(
    ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(supabase),
        ...adminEvidenceOverrides(),
      ],
      child: adminPwaEvidenceMode
          ? Semantics(
              container: true,
              label: 'Collect admin evidence mode marker',
              child: const CollectAdminApp(),
            )
          : const CollectAdminApp(),
    ),
  );
}
