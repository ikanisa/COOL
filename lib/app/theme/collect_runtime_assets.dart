class CollectRuntimeAssets {
  const CollectRuntimeAssets._();

  static const usesRepoVisualAssets = false;
  static const brandLabel = 'Collect';
  static const assetPolicy =
      'Runtime visual assets are intentionally absent; DESIGN.md is the only design authority.';

  static const requiredBlockerKeys = <String>['universal_contract'];
}
