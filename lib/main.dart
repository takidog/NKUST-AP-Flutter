import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ap_common/models/course_data.dart';
import 'package:ap_common/models/score_data.dart';
import 'package:ap_common/models/user_info.dart';
import 'package:ap_common/resources/ap_icon.dart';
import 'package:ap_common/resources/ap_theme.dart';
import 'package:ap_common/utils/preferences.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nkust_ap/app.dart';
import 'package:nkust_ap/config/constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  bool isInDebugMode = Constants.isInDebugMode;
  HttpClient.enableTimelineLogging = isInDebugMode;
  await Preferences.init(key: Constants.key, iv: Constants.iv);
  var currentVersion =
      Preferences.getString(Constants.PREF_CURRENT_VERSION, '0');
  if (int.parse(currentVersion) < 30400) _preference340Migrate();
  ApIcon.code =
      Preferences.getString(Constants.PREF_ICON_STYLE_CODE, ApIcon.OUTLINED);
  _setTargetPlatformForDesktop();
  if (isInDebugMode || kIsWeb || !(Platform.isIOS || Platform.isAndroid)) {
    runApp(MyApp());
  } else if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    Crashlytics.instance.enableInDevMode = isInDebugMode;
    // Pass all uncaught errors from the framework to Crashlytics.
    FlutterError.onError = Crashlytics.instance.recordFlutterError;
    runZonedGuarded(() async {
      runApp(MyApp());
    }, Crashlytics.instance.recordError);
  }
}

//v3.4.0 preference migrate
void _preference340Migrate() async {
  String themeCode = Preferences.getString(Constants.PREF_THEME_CODE, null);
  if (themeCode != null) {
    int index;
    switch (themeCode) {
      case ApTheme.DARK:
        index = 2;
        break;
      case ApTheme.LIGHT:
        index = 1;
        break;
      default:
        index = 0;
        break;
    }
    await Preferences.setInt(Constants.PREF_THEME_MODE_INDEX, index);
    Preferences.setString(Constants.PREF_THEME_CODE, null);
  }
  Preferences.prefs.getKeys()?.forEach((key) {
    if (key.contains(Constants.PREF_COURSE_DATA)) {
      debugPrint(key);
      var data = Preferences.getString(key, null);
      var courseData = CourseData.fromRawJson(data);
      courseData.save(
        key.replaceAll('${Constants.PREF_COURSE_DATA}_', ''),
      );
      Preferences.setString(key, null);
    } else if (key.contains(Constants.PREF_SCORE_DATA)) {
      print(key);
      var data = Preferences.getString(key, null);
      var courseData = ScoreData.fromRawJson(data);
      courseData.save(
        key.replaceAll('${Constants.PREF_SCORE_DATA}_', ''),
      );
      Preferences.setString(key, null);
    } else if (key.contains(Constants.PREF_USER_INFO)) {
      print(key);
      var data = Preferences.getString(key, null);
      var courseData = UserInfo.fromRawJson(data);
      courseData.save(
        key.replaceAll('${Constants.PREF_USER_INFO}_', ''),
      );
      Preferences.setString(key, null);
    }
  });
}

void _setTargetPlatformForDesktop() {
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows)) {
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
  }
}
