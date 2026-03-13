part of '../screens/schedule_trip_screen.dart';

class _ScheduleTripRoleCard extends StatelessWidget {
  const _ScheduleTripRoleCard({
    required this.selectedRole,
    required this.canScheduleAsDriver,
    required this.onSelectRole,
    required this.onOpenDriverSetup,
  });

  final ScheduleTripPostingRole selectedRole;
  final bool canScheduleAsDriver;
  final ValueChanged<ScheduleTripPostingRole> onSelectRole;
  final VoidCallback onOpenDriverSetup;

  @override
  Widget build(BuildContext context) {
    final isDriverSelected = selectedRole == ScheduleTripPostingRole.driver;
    final summary = switch ((isDriverSelected, canScheduleAsDriver)) {
      (false, _) =>
        'Passenger is your default role. You can switch per trip whenever needed.',
      (true, true) =>
        'Driver trips are posted as return trips while you still keep passenger access.',
      (true, false) => 'Finish driver setup before posting a trip as a driver.',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Schedule as',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            summary,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AppColors.text2,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ScheduleTripSelectionChip(
                label: 'Passenger',
                selected: selectedRole == ScheduleTripPostingRole.passenger,
                onTap: () => onSelectRole(ScheduleTripPostingRole.passenger),
              ),
              ScheduleTripSelectionChip(
                label: 'Driver',
                selected: isDriverSelected,
                onTap: () => onSelectRole(ScheduleTripPostingRole.driver),
              ),
            ],
          ),
          if (isDriverSelected && !canScheduleAsDriver) ...[
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: onOpenDriverSetup,
              icon: const Icon(Icons.directions_car_outlined, size: 18),
              label: const Text('Become a driver'),
            ),
          ],
        ],
      ),
    );
  }
}
