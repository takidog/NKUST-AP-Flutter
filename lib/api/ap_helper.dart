//dio
import 'package:dio/adapter.dart';
import 'package:dio/dio.dart';
import 'package:dio_http_cache/dio_http_cache.dart';
import 'package:nkust_ap/api/parser/api_tool.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:flutter/cupertino.dart';

//overwrite origin Cookie Manager.
import 'package:nkust_ap/api/private_cookie_manager.dart';

//parser
import 'package:nkust_ap/api/parser/ap_parser.dart';

//Config
import 'package:nkust_ap/config/constants.dart';

//Model
import 'package:ap_common/models/user_info.dart';
import 'package:ap_common/models/score_data.dart';
import 'package:ap_common/models/course_data.dart';
import 'package:nkust_ap/models/login_response.dart';
import 'package:nkust_ap/models/semester_data.dart';
import 'package:nkust_ap/models/midterm_alerts_data.dart';
import 'package:nkust_ap/models/reward_and_penalty_data.dart';
import 'package:nkust_ap/models/room_data.dart';

// callback
import 'package:ap_common/callback/general_callback.dart';

//Ap helper errorCode
import 'package:nkust_ap/api/ap_status_code.dart';

import 'helper.dart';

class WebApHelper {
  static Dio dio;
  static DioCacheManager _manager;
  static WebApHelper _instance;
  static CookieJar cookieJar;

  static int reLoginReTryCountsLimit = 3;
  static int reLoginReTryCounts = 0;

  bool isLogin = false;

  //cache key name
  static String get semesterCacheKey => "semesterCacheKey";

  static String get coursetableCacheKey =>
      "${Helper.username}_coursetableCacheKey";

  static String get scoresCacheKey => "${Helper.username}_scoresCacheKey";

  static String get userInfoCacheKey => "${Helper.username}_userInfoCacheKey";

  static WebApHelper get instance {
    if (_instance == null) {
      _instance = WebApHelper();
      dioInit();
    }
    return _instance;
  }

  void setProxy(String proxyIP) {
    (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate =
        (client) {
      client.findProxy = (uri) {
        return "PROXY " + proxyIP;
      };
    };
  }

  Future<void> logout() async {
    try {
      await dio.post("https://webap.nkust.edu.tw/nkust/reclear.jsp");
    } catch (e) {}
  }

  static dioInit() {
    // Use PrivateCookieManager to overwrite origin CookieManager, because
    // Cookie name of the NKUST ap system not follow the RFC6265. :(
    dio = Dio();
    cookieJar = CookieJar();
    if (Helper.isSupportCacheData) {
      _manager =
          DioCacheManager(CacheConfig(baseUrl: "https://webap.nkust.edu.tw"));
      dio.interceptors.add(_manager.interceptor);
    }
    dio.interceptors.add(PrivateCookieManager(cookieJar));
    dio.options.headers['user-agent'] =
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/84.0.4147.89 Safari/537.36';
    dio.options.headers['Connection'] = 'close';
    dio.options.connectTimeout = Constants.TIMEOUT_MS;
    dio.options.receiveTimeout = Constants.TIMEOUT_MS;
  }

  Future<LoginResponse> apLogin({
    @required String username,
    @required String password,
  }) async {
    //
    /*
    Retrun type Int
    0 : Login Success
    1 : Password error or not found user
    2 : Relogin
    3 : Not found login message
    */

    Response res = await dio.post(
      "https://webap.nkust.edu.tw/nkust/perchk.jsp",
      data: {"uid": username, "pwd": password},
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    Helper.username = username;
    Helper.password = password;
    switch (apLoginParser(res.data)) {
      case 0:
        return LoginResponse(
          expireTime: DateTime.now().add(Duration(hours: 6)),
          isAdmin: false,
        );
        break;
      case 1:
      default:
        throw GeneralResponse(
          statusCode: ApStatusCode.USER_DATA_ERROR,
          message: 'username or password error',
        );
        break;
    }
  }

  Future<Response> apQuery(
    String queryQid,
    Map<String, String> queryData, {
    String cacheKey,
    Duration cacheExpiredTime,
    bool bytesResponse,
  }) async {
    /*
    Retrun type Response <Dio>
    */
    if (reLoginReTryCounts > reLoginReTryCountsLimit) {
      throw GeneralResponse(
          statusCode: ApStatusCode.NETWORK_CONNECT_FAIL,
          message: "Login exceeded retry limit");
    }
    if (isLogin != true) {
      await apLogin(username: Helper.username, password: Helper.password);
    }
    String url =
        "https://webap.nkust.edu.tw/nkust/${queryQid.substring(0, 2)}_pro/${queryQid}.jsp";
    Options _options;
    dynamic requestData;
    if (cacheKey == null) {
      _options = Options(contentType: Headers.formUrlEncodedContentType);
      if (bytesResponse != null) {
        _options.responseType = ResponseType.bytes;
      }
      requestData = queryData;
    } else {
      dio.options.headers["Content-Type"] = "application/x-www-form-urlencoded";
      Options other_options;
      if (bytesResponse != null) {
        other_options = Options(responseType: ResponseType.bytes);
      }
      _options = buildConfigurableCacheOptions(
        options: other_options,
        maxAge: cacheExpiredTime ?? Duration(seconds: 60),
        primaryKey: cacheKey,
      );
      requestData = formUrlEncoded(queryData);
    }
    Response<dynamic> request;

    if (bytesResponse != null) {
      request = await dio.post<List<int>>(
        url,
        data: requestData,
        options: _options,
      );
    } else {
      request = await dio.post(
        url,
        data: requestData,
        options: _options,
      );
    }

    if (apLoginParser(request.data) == 2) {
      if (Helper.isSupportCacheData) _manager.delete(cacheKey);
      reLoginReTryCounts += 1;
      await apLogin(username: Helper.username, password: Helper.password);
      return apQuery(queryQid, queryData, bytesResponse: bytesResponse);
    }
    reLoginReTryCounts = 0;
    return request;
  }

  Future<UserInfo> userInfoCrawler() async {
    if (!Helper.isSupportCacheData) {
      var query = await apQuery("ag003", null);
      return UserInfo.fromJson(
        apUserInfoParser(query.data),
      );
    }
    var query = await apQuery(
      "ag003",
      null,
      cacheKey: userInfoCacheKey,
      cacheExpiredTime: Duration(hours: 6),
    );

    var parsedData = apUserInfoParser(query.data);
    if (parsedData["id"] == null) {
      _manager.delete(userInfoCacheKey);
    }

    return UserInfo.fromJson(
      apUserInfoParser(query.data),
    );
  }

  Future<SemesterData> semesters() async {
    if (!Helper.isSupportCacheData) {
      var query = await apQuery("ag304_01", null);
      return SemesterData.fromJson(semestersParser(query.data));
    }
    var query = await apQuery(
      "ag304_01",
      null,
      cacheKey: semesterCacheKey,
      cacheExpiredTime: Duration(hours: 3),
    );
    var parsedData = semestersParser(query.data);
    if (parsedData["data"].length < 1) {
      //data error delete cache
      _manager.delete(semesterCacheKey);
    }

    return SemesterData.fromJson(parsedData);
  }

  Future<ScoreData> scores(String years, String semesterValue) async {
    if (!Helper.isSupportCacheData) {
      var query = await apQuery(
        "ag008",
        {"arg01": years, "arg02": semesterValue},
      );
      return ScoreData.fromJson(semestersParser(query.data));
    }
    var query = await apQuery(
      "ag008",
      {"arg01": years, "arg02": semesterValue},
      cacheKey: "${scoresCacheKey}_${years}_${semesterValue}",
      cacheExpiredTime: Duration(hours: 6),
    );

    var parsedData = scoresParser(query.data);
    if (parsedData["scores"].length == 0) {
      _manager.delete("${scoresCacheKey}_${years}_${semesterValue}");
    }

    return ScoreData.fromJson(
      parsedData,
    );
  }

  Future<CourseData> coursetable(String years, String semesterValue) async {
    if (!Helper.isSupportCacheData) {
      ;
      var query = await apQuery(
        "ag222",
        {"arg01": years, "arg02": semesterValue},
        bytesResponse: true,
      );
      return CourseData.fromJson(coursetableParser(query.data));
    }
    var query = await apQuery(
      "ag222",
      {"arg01": years, "arg02": semesterValue},
      cacheKey: "${coursetableCacheKey}_${years}_${semesterValue}",
      cacheExpiredTime: Duration(hours: 6),
      bytesResponse: true,
    );
    var parsedData = coursetableParser(query.data);
    if (parsedData["courses"].length == 0) {
      _manager.delete("${coursetableCacheKey}_${years}_${semesterValue}");
    }
    return CourseData.fromJson(
      parsedData,
    );
  }

  Future<MidtermAlertsData> midtermAlerts(
      String years, String semesterValue) async {
    var query = await apQuery(
      "ag009",
      {"arg01": years, "arg02": semesterValue},
    );

    return MidtermAlertsData.fromJson(
      midtermAlertsParser(query.data),
    );
  }

  Future<RewardAndPenaltyData> rewardAndPenalty(
      String years, String semesterValue) async {
    var query = await apQuery(
      "ak010",
      {"arg01": years, "arg02": semesterValue},
    );

    return RewardAndPenaltyData.fromJson(
      rewardAndPenaltyParser(query.data),
    );
  }

  Future<RoomData> roomList(String cmpAreaId) async {
    /*
    cmpAreaId
    1=建工/2=燕巢/3=第一/4=楠梓/5=旗津
    */
    var query = await apQuery(
      "ag302_01",
      {"cmp_area_id": cmpAreaId},
    );

    return RoomData.fromJson(
      roomListParser(query.data),
    );
  }

  Future<CourseData> roomCourseTableQuery(
      String roomId, String years, String semesterValue) async {
    var query = await apQuery(
      "ag302_02",
      {"room_id": roomId, "yms_yms": "${years}#${semesterValue}"},
    );

    return CourseData.fromJson(
      roomCourseTableQueryParser(query.data),
    );
  }
}
