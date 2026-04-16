import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';

class VpnStatus {
  final bool isConnected;
  final String ip;
  final String profile;
  final String peers;
  final String management;
  final String signal;
  final String lastError;

  VpnStatus({
    this.isConnected = false,
    this.ip = 'N/A',
    this.profile = 'N/A',
    this.peers = '0/0',
    this.management = 'Disconnected',
    this.signal = 'Disconnected',
    this.lastError = '',
  });
}

class VpnProvider extends ChangeNotifier {
  VpnStatus _status = VpnStatus();
  Timer? _timer;
  bool _isToggling = false;

  VpnStatus get status => _status;
  bool get isToggling => _isToggling;

  final String _netbirdPath = '/usr/local/bin/netbird';

  VpnProvider() {
    startPolling();
  }

  void startPolling() {
    _timer?.cancel();
    updateStatus();
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      updateStatus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> updateStatus() async {
    try {
      final result = await Process.run(_netbirdPath, ['status']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        _status = _parseStatus(output);
      } else {
        _status = VpnStatus(lastError: 'Netbird CLI error: ${result.stderr}');
      }
    } catch (e) {
      _status = VpnStatus(lastError: 'Failed to run netbird: $e');
    }
    notifyListeners();
  }

  VpnStatus _parseStatus(String output) {
    bool connected = false;
    String ip = 'N/A';
    String profile = 'N/A';
    String peers = '0/0';
    String mgmt = 'Disconnected';
    String signal = 'Disconnected';

    final lines = output.split('\n');
    for (var line in lines) {
      if (line.contains('Management:')) {
        mgmt = line.split(':')[1].trim();
      } else if (line.contains('Signal:')) {
        signal = line.split(':')[1].trim();
      } else if (line.contains('NetBird IP:')) {
        ip = line.split(':')[1].trim();
      } else if (line.contains('Profile:')) {
        profile = line.split(':')[1].trim();
      } else if (line.contains('Peers count:')) {
        peers = line.split(':')[1].trim();
      }
    }

    connected = mgmt == 'Connected' && signal == 'Connected';

    return VpnStatus(
      isConnected: connected,
      ip: ip,
      profile: profile,
      peers: peers,
      management: mgmt,
      signal: signal,
    );
  }

  Future<void> toggleVpn() async {
    if (_isToggling) return;
    _isToggling = true;
    notifyListeners();

    try {
      final command = _status.isConnected ? 'down' : 'up';
      // Note: This may prompt for password in the background on some systems
      // or fail if it requires interactive sudo.
      final result = await Process.run(_netbirdPath, [command]);
      
      if (result.exitCode != 0) {
        debugPrint('VPN Toggle Error: ${result.stderr}');
      }
      
      await updateStatus();
    } catch (e) {
      debugPrint('VPN Toggle Failed: $e');
    } finally {
      _isToggling = false;
      notifyListeners();
    }
  }
}
