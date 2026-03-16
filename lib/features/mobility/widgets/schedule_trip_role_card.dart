part of '../screens/schedule_trip_screen.dart';

// _ScheduleTripProgressCard and _ScheduleTripRolePill removed —
// replaced by _ScheduleTripRoleRow in the main screen file.

class _ScheduleTripRoleSheet extends StatelessWidget {
  const _ScheduleTripRoleSheet({
    required this.selectedRole,
    required this.canScheduleAsDriver,
  });

  final ScheduleTripPostingRole selectedRole;
  final bool canScheduleAsDriver;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Choose role',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: palette.text,
                ),
              ),
              const SizedBox(height: 18),
              _ScheduleTripRoleSheetOption(
                label: 'Passenger',
                subtitle: 'Default mode',
                selected: selectedRole == ScheduleTripPostingRole.passenger,
                onTap: () => Navigator.of(
                  context,
                ).pop(ScheduleTripPostingRole.passenger),
              ),
              Divider(color: palette.border),
              _ScheduleTripRoleSheetOption(
                label: 'Driver',
                subtitle: canScheduleAsDriver
                    ? 'Post as driver'
                    : 'Setup required',
                selected: selectedRole == ScheduleTripPostingRole.driver,
                onTap: () =>
                    Navigator.of(context).pop(ScheduleTripPostingRole.driver),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScheduleTripRoleSheetOption extends StatelessWidget {
  const _ScheduleTripRoleSheetOption({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_off_rounded,
        color: selected ? palette.accent : palette.text3,
      ),
      title: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: palette.text,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: palette.text2,
        ),
      ),
      onTap: onTap,
    );
  }
}
