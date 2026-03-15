import '../models/trip.dart';

String tripTypeLabel({required bool isDriverReturn}) {
  return isDriverReturn ? 'Driver return' : 'Passenger trip';
}

String tripCollectionLabel({required bool isDriverReturn}) {
  return isDriverReturn ? 'Driver returns' : 'Passenger trips';
}

String tripTypeLabelForTrip(Trip trip) {
  return tripTypeLabel(isDriverReturn: trip.isDriverReturnTrip);
}

String tripSeatAvailabilityLabel(int seats) {
  return '$seats seat${seats == 1 ? '' : 's'} available';
}

String tripReturnChipLabel(Trip trip) {
  if (trip.isDriverReturnTrip) {
    return 'Driver return';
  }
  if (trip.isReturn) {
    return 'Return trip';
  }
  return '';
}

String tripListingTitle(Trip trip) {
  return tripTypeLabelForTrip(trip);
}

String tripPostedByLabel(Trip trip) {
  return trip.isDriverReturnTrip ? 'Driver' : 'Posted by';
}

String tripNoteLabel(Trip trip) {
  return trip.isDriverReturnTrip ? 'Rider note' : 'Price note';
}

String tripChatFlowLabel(Trip trip) {
  return trip.isDriverReturnTrip
      ? 'Pickup, fare, and timing are confirmed with the driver in WhatsApp.'
      : 'Pickup, fare, and timing are confirmed after you connect in WhatsApp.';
}

String tripMarketplaceHint(Trip trip) {
  return trip.isDriverReturnTrip
      ? 'COOL introduces riders to drivers. Final fare, pickup, and timing are confirmed in WhatsApp.'
      : 'COOL introduces both sides. Final fare, pickup, and timing are confirmed in WhatsApp.';
}

String tripShareTitle(Trip trip) {
  return trip.isDriverReturnTrip
      ? 'Share this driver return'
      : 'Share this trip';
}

String tripShareText(Trip trip) {
  final route = '${trip.fromLocation} to ${trip.toLocation}';
  return trip.isDriverReturnTrip
      ? 'Check out this driver return from $route on Cool!'
      : 'Check out this trip from $route on Cool!';
}
