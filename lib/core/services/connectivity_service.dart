import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  return ConnectivityService();
});

final connectivityStatusProvider = StreamProvider<bool>((ref) {
  return ref.watch(connectivityServiceProvider).watchConnection();
});

class ConnectivityService {
  ConnectivityService([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<bool> watchConnection() async* {
    yield await currentStatus();

    try {
      await for (final results in _connectivity.onConnectivityChanged) {
        yield _isOnline(results);
      }
    } catch (_) {
      yield true;
    }
  }

  Future<bool> currentStatus() async {
    try {
      final results = await _connectivity.checkConnectivity();
      return _isOnline(results);
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  bool _isOnline(List<ConnectivityResult> results) {
    if (results.isEmpty) {
      return false;
    }

    return !results.contains(ConnectivityResult.none);
  }
}
