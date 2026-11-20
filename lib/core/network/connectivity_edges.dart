// lib/core/network/connectivity_edges.dart
//
// `Connectivity().onConnectivityChanged`, minus a Linux crash-report source.
// On Linux connectivity_plus talks to NetworkManager over the system D-Bus;
// without NetworkManager its async setup throws an UNCAUGHT SocketException
// (verified on Debian with the system bus unreachable), which this app's zone
// handler would upload as a crash on every launch. Every consumer only uses
// the stream as an "online again -> retry now" edge trigger (real reachability
// comes from ConnectivityService's HTTP probe and the sync timers), so with no
// NetworkManager an empty stream is the correct degradation.
import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;

/// NetworkManager keeps `/run/NetworkManager` while it runs.
@visibleForTesting
bool linuxHasNetworkManager({String runDir = '/run/NetworkManager'}) =>
    Directory(runDir).existsSync();

Stream<List<ConnectivityResult>> connectivityChanges({bool? linuxHasNm}) {
  if (!kIsWeb && Platform.isLinux && !(linuxHasNm ?? linuxHasNetworkManager())) {
    return const Stream<List<ConnectivityResult>>.empty();
  }
  return Connectivity().onConnectivityChanged;
}
