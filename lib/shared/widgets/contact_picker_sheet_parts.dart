part of 'contact_picker_sheet.dart';

class _ContactTile extends StatelessWidget {
  const _ContactTile({
    required this.contact,
    required this.isSelected,
    required this.showCheckbox,
    required this.onTap,
  });

  final SimpleContact contact;
  final bool isSelected;
  final bool showCheckbox;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;
    final text = context.coolText;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: space.x2 + 2,
          horizontal: space.x1,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.border, width: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.accent.withValues(alpha: 0.15)
                    : colors.inputSurface,
                borderRadius: BorderRadius.circular(21),
              ),
              alignment: Alignment.center,
              child: Text(
                contact.initials,
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isSelected ? colors.accent : colors.secondaryText,
                ),
              ),
            ),
            SizedBox(width: space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.displayName,
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.primaryText,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: space.x1 / 4),
                  Text(
                    contact.phones.first,
                    style: text.mono(
                      textTheme.labelSmall,
                      fontWeight: FontWeight.w500,
                      color: colors.tertiaryText,
                    ),
                  ),
                ],
              ),
            ),
            if (showCheckbox)
              AnimatedContainer(
                duration: CoolMotion.quick,
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? colors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(radii.sm / 2.5),
                  border: Border.all(
                    color: isSelected ? colors.accent : colors.borderStrong,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Colors.white,
                      )
                    : null,
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                color: colors.tertiaryText,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}

class _PermissionState extends StatelessWidget {
  const _PermissionState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback action;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: space.x8,
        horizontal: space.x7 - 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: colors.secondaryText),
          SizedBox(height: space.x3 + 2),
          Text(
            title,
            style: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          SizedBox(height: space.x2),
          Text(
            message,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              color: colors.tertiaryText,
              height: 1.5,
            ),
          ),
          SizedBox(height: space.x5),
          GestureDetector(
            onTap: action,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: space.x6,
                vertical: space.x3,
              ),
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(radii.sm),
              ),
              child: Text(
                actionLabel,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.accentForeground,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.coolSemanticColors;
    final textTheme = Theme.of(context).textTheme;
    final space = context.coolSpace;
    final radii = context.coolRadii;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: space.x4, vertical: space.x2),
        decoration: BoxDecoration(
          color: colors.accent,
          borderRadius: BorderRadius.circular(radii.pill),
        ),
        child: Text(
          context.l10n.contactPickerDoneCount(count),
          style: textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: colors.accentForeground,
          ),
        ),
      ),
    );
  }
}
