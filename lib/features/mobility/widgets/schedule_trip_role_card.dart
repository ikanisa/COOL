part of '../screens/schedule_trip_screen.dart';

class _ScheduleTripProgressCard extends StatelessWidget {
  const _ScheduleTripProgressCard({
    required this.activeStep,
    required this.stepTitle,
    required this.stepSubtitle,
    required this.contextLabel,
    required this.selectedRole,
    required this.canScheduleAsDriver,
    required this.onOpenRoleSheet,
    required this.onOpenDriverSetup,
  });

  final ScheduleTripStep activeStep;
  final String stepTitle;
  final String stepSubtitle;
  final String contextLabel;
  final ScheduleTripPostingRole selectedRole;
  final bool canScheduleAsDriver;
  final VoidCallback onOpenRoleSheet;
  final VoidCallback onOpenDriverSetup;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    final isDriverSelected = selectedRole == ScheduleTripPostingRole.driver;
    final roleLabel = isDriverSelected ? 'Driver' : 'Passenger';
    final roleSummary = switch ((isDriverSelected, canScheduleAsDriver)) {
      (false, _) => 'Passenger is your default role.',
      (true, true) => 'Driver trips post as return trips.',
      (true, false) => 'Finish driver setup before posting as a driver.',
    };
    final activeIndex = ScheduleTripStep.values.indexOf(activeStep);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Step ${activeIndex + 1} of ${ScheduleTripStep.values.length}',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            stepTitle,
            style: GoogleFonts.dmSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            stepSubtitle,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: palette.text2,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            contextLabel,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ScheduleTripRolePill(
                  label: 'Posting as $roleLabel',
                  subtitle: roleSummary,
                ),
              ),
              const SizedBox(width: 12),
              CoolButton(
                label: 'Role',
                variant: CoolButtonVariant.secondary,
                fullWidth: false,
                onTap: onOpenRoleSheet,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (
                var index = 0;
                index < ScheduleTripStep.values.length;
                index++
              ) ...[
                Expanded(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      color: index <= activeIndex
                          ? palette.accent
                          : palette.surface3,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                if (index != ScheduleTripStep.values.length - 1)
                  const SizedBox(width: 8),
              ],
            ],
          ),
          if (isDriverSelected && !canScheduleAsDriver) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onOpenDriverSetup,
                icon: const Icon(Icons.directions_car_outlined, size: 18),
                label: const Text('Become a driver'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleTripRolePill extends StatelessWidget {
  const _ScheduleTripRolePill({required this.label, required this.subtitle});

  final String label;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.coolPalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: palette.text2,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

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
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
              const SizedBox(height: 6),
              Text(
                'Pick the role for this trip without crowding the main form.',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  color: palette.text2,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              _ScheduleTripRoleSheetOption(
                label: 'Passenger',
                subtitle:
                    'Default trip posting mode with no extra driver setup required.',
                selected: selectedRole == ScheduleTripPostingRole.passenger,
                onTap: () => Navigator.of(
                  context,
                ).pop(ScheduleTripPostingRole.passenger),
              ),
              Divider(color: palette.border),
              _ScheduleTripRoleSheetOption(
                label: 'Driver',
                subtitle: canScheduleAsDriver
                    ? 'Post return trips while keeping passenger access.'
                    : 'Driver posting is locked until setup is complete.',
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
