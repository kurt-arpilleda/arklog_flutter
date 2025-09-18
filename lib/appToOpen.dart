import 'package:flutter/services.dart';

class AppToOpen {
  static const platform = MethodChannel('app_launcher_channel');

  static const Map<int, String> appPackages = {
    1: 'com.example.tag_search',
    2: 'com.example.multi_search',
    3: 'com.example.workstart_finish',
    4: 'com.example.multimedia_software',
    6: 'com.example.cpar_input',
    7: 'com.example.ng_notification',
    8: 'com.example.batch_start',
    10: 'com.example.ark_log',
    11: 'com.example.paging',
    12: 'com.example.pms_dashboard',
    13: 'com.example.handling_software',
    14: 'com.example.lotimage',
    15: 'com.example.ark_filer',
    17: 'com.example.voice_recorder',
    18: 'com.example.group_unmerge',
  };

  static Future<bool> openApp(int appId) async {
    final packageName = appPackages[appId];
    if (packageName == null) return false;

    try {
      final result = await platform.invokeMethod('openApp', {'packageName': packageName});
      return result == true;
    } catch (e) {
      print('Failed to open app: $e');
      return false;
    }
  }
}