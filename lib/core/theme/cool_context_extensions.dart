part of 'cool_foundations.dart';

extension CoolSemanticColorsBuildContext on BuildContext {
  CoolSemanticColors get coolSemanticColors {
    return Theme.of(this).extension<CoolSemanticColors>() ??
        (Theme.of(this).brightness == Brightness.dark
            ? CoolSemanticColors.dark
            : CoolSemanticColors.light);
  }

  CoolTextStyles get coolText => CoolTextStyles._(
    textTheme: Theme.of(this).textTheme,
    defaultColor: coolSemanticColors.primaryText,
  );

  CoolSpaceTokens get coolSpace => const CoolSpaceTokens._();

  CoolRadiiTokens get coolRadii => const CoolRadiiTokens._();

  CoolInsetsTokens get coolInsets => const CoolInsetsTokens._();
}
