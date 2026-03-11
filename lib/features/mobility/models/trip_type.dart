enum TripType { passenger, driverReturn }

extension TripTypeX on TripType {
  bool get isDriverReturn => this == TripType.driverReturn;
}
