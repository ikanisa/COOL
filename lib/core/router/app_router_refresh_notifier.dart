import 'package:flutter/material.dart';

class AppRouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}
