import 'package:intl/intl.dart';

import '../../auth/models/user_profile.dart';
import '../models/driver_info.dart';
import '../models/trip.dart';

class MobilityWhatsAppService {
  MobilityWhatsAppService._();

  static String buildTripInquiryMessage({
    required Trip trip,
    UserProfile? requester,
  }) {
    final requesterId = requester?.displayUserId;
    final contact = trip.contactName?.trim();
    final departure = DateFormat(
      'EEE d MMM • HH:mm',
    ).format(trip.departureTime);
    final buffer = StringBuffer()
      ..write('Hi')
      ..write(contact != null && contact.isNotEmpty ? ' $contact' : '')
      ..write(', ')
      ..write(requesterId != null ? "I'm $requesterId. " : '')
      ..write('I found your listing on COOL for ')
      ..write('${trip.fromLocation} to ${trip.toLocation}')
      ..write(' on $departure. ');

    if (trip.isDriverReturnTrip) {
      buffer.write('I am interested in joining that return trip. ');
    } else {
      buffer.write('Is it still available? ');
    }

    buffer.write(
      'If yes, can we agree on price and the exact pickup point here on WhatsApp?',
    );
    return buffer.toString();
  }

  static String buildDriverInquiryMessage({
    required DriverInfo driver,
    UserProfile? requester,
  }) {
    final requesterId = requester?.displayUserId;
    final contact = driver.displayName.trim();
    final distance = driver.distanceKm < 1
        ? '${(driver.distanceKm * 1000).round()} m'
        : '${driver.distanceKm.toStringAsFixed(1)} km';
    final buffer = StringBuffer()
      ..write('Hi')
      ..write(contact.isNotEmpty ? ' $contact' : '')
      ..write(', ')
      ..write(requesterId != null ? "I'm $requesterId. " : '')
      ..write('I found your ')
      ..write(driver.vehicleType)
      ..write(' profile on COOL');

    if (driver.scheduledRoute?.trim().isNotEmpty ?? false) {
      buffer
        ..write(' and noticed your route ')
        ..write(driver.scheduledRoute!.trim());
    }

    buffer
      ..write('. You appear to be about $distance away. ')
      ..write(
        'Are you available to discuss price and pickup here on WhatsApp?',
      );

    return buffer.toString();
  }
}
