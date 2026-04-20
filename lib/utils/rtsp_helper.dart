import 'package:intl/intl.dart';
import '../models/nvr_model.dart';
import '../providers/nvr_provider.dart';

class RtspHelper {
  /// Formats the Hikvision Live URL
  ///
  /// Optimized for Mandalay 4/5 hardware over Netbird VPN.
  /// Phase 12: Implements ONVIF bypass for Mandalay 5 encrypted streams.
  static String getLiveUrl({
    required NvrGroupModel nvr,
    required int channel,
    required StreamQuality quality,
  }) {
    // 1. Password Logic: 
    // For Mandalay 5 (identified by streamKey), we use the main password 
    // but we will use the ONVIF Profile bypass parameters.
    String rawPass = nvr.password;
    try {
      if (rawPass.contains('%')) rawPass = Uri.decodeComponent(rawPass);
    } catch (_) {}

    final safePass = Uri.encodeComponent(rawPass);
    final trackId = quality == StreamQuality.hd ? '${channel}01' : '${channel}02';

    // 2. Format the Base URL
    String url = 'rtsp://${nvr.username}:$safePass@${nvr.cleanHost}:${nvr.port}/Streaming/Channels/$trackId';
    
    // 3. Phase 12: ONVIF Profile Bypass for Mandalay 5
    // Appending profile=Profile_X targets the ONVIF media handler in the DVR, 
    // which frequently ignores Platform Access encryption.
    if (nvr.streamKey != null && nvr.streamKey!.isNotEmpty) {
      final profile = quality == StreamQuality.hd ? 'Profile_1' : 'Profile_2';
      url += '?transportmode=unicast&profile=$profile';
      // Fallback verificationCode if the profile bypass isn't supported by firmware
      url += '&verificationCode=${nvr.streamKey}';
    }
    
    return url;
  }

  /// Formats the Hikvision Playback URL
  static String getPlaybackUrl({
    required NvrGroupModel nvr,
    required int channel,
    required DateTime start,
    required DateTime end,
    bool useLocalTime = true,
  }) {
    final DateFormat formatter = DateFormat("yyyyMMdd'T'HHmmss");
    final startStr = '${formatter.format(useLocalTime ? start : start.toUtc())}Z';
    final endStr = '${formatter.format(useLocalTime ? end : end.toUtc())}Z';

    String rawPass = nvr.password;
    try {
      if (rawPass.contains('%')) rawPass = Uri.decodeComponent(rawPass);
    } catch (_) {}
    
    final safePass = Uri.encodeComponent(rawPass);
    final trackId = '${channel}01';

    String url = 'rtsp://${nvr.username}:$safePass@${nvr.cleanHost}:${nvr.port}/Streaming/tracks/$trackId/?starttime=$startStr&endtime=$endStr';
    
    if (nvr.streamKey != null && nvr.streamKey!.isNotEmpty) {
      url += '&profile=Profile_1'; // Force ONVIF mode for playback as well
    }

    return url;
  }

  static String formatDateTime(DateTime dt) => DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);

  static DateTime? parseNvrTime(String time) {
    try {
      return DateTime.parse(time.replaceAll('t', ' ')).toLocal();
    } catch (_) {
      return null;
    }
  }
}
