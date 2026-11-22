import 'contribution_command_storage_contract.dart';
import 'contribution_command_storage_native.dart'
    if (dart.library.js_interop) 'contribution_command_storage_web.dart'
    as platform;
export 'contribution_command_storage_contract.dart';

ContributionCommandProtectedStorage createContributionCommandStorage() =>
    platform.createStore();
