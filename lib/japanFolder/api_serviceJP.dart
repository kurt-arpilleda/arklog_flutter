import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiServiceJP {
  // API URLs
  static const List<String> apiUrls = [
    "http://192.168.1.213/",
    "http://220.157.175.232/"
  ];

  // Timeout and retry settings
  static const Duration requestTimeout = Duration(seconds: 2);
  static const int maxRetries = 3;
  static const Duration initialRetryDelay = Duration(milliseconds: 500);

  // Track API health status
  static final Map<String, bool> _apiHealthStatus = {
    "http://192.168.1.213/": true,
    "http://220.157.175.232/": true,
  };

  // Cache the last successful API URL to prioritize it
  static String? _lastSuccessfulUrl;

  // Prioritize APIs based on health status and past success
  List<String> _getPrioritizedUrls() {
    final urls = List<String>.from(apiUrls);

    // If we have a last successful URL and it's still considered healthy, prioritize it
    if (_lastSuccessfulUrl != null && _apiHealthStatus[_lastSuccessfulUrl] == true) {
      urls.remove(_lastSuccessfulUrl);
      urls.insert(0, _lastSuccessfulUrl!);
    } else {
      // Otherwise, prioritize based on health status
      urls.sort((a, b) {
        final aHealthy = _apiHealthStatus[a] ?? false;
        final bHealthy = _apiHealthStatus[b] ?? false;
        if (aHealthy && !bHealthy) return -1;
        if (!aHealthy && bHealthy) return 1;
        return 0;
      });
    }

    return urls;
  }

  // Make parallel requests to all APIs and return the first successful response
  Future<Map<String, dynamic>> _makeParallelRequests({
    required String endpoint,
    Map<String, String>? body,
    bool isGet = false,
    Duration? customTimeout,
  }) async {
    final timeout = customTimeout ?? requestTimeout;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      // Get prioritized URLs based on health status
      final prioritizedUrls = _getPrioritizedUrls();

      // Create a list of futures for parallel requests
      final List<Future<Map<String, dynamic>>> requests = [];

      for (String apiUrl in prioritizedUrls) {
        requests.add(_makeRequest(
          apiUrl: apiUrl,
          endpoint: endpoint,
          body: body,
          isGet: isGet,
          timeout: timeout,
        ).then((result) {
          // Mark the API as healthy and remember it was successful
          _apiHealthStatus[apiUrl] = true;
          _lastSuccessfulUrl = apiUrl;
          return result;
        }).catchError((e) {
          // Mark the API as unhealthy
          _apiHealthStatus[apiUrl] = false;
          throw e;
        }));
      }

      try {
        // Wait for the first successful response or for all to fail
        return await Future.any(requests);
      } catch (e) {
        // All requests failed in this attempt
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        } else {
          rethrow;
        }
      }
    }

    throw Exception("All API URLs are unreachable after $maxRetries attempts");
  }

  // Helper method to make a single request to a specific API URL
  Future<Map<String, dynamic>> _makeRequest({
    required String apiUrl,
    required String endpoint,
    Map<String, String>? body,
    bool isGet = false,
    required Duration timeout,
  }) async {
    final uri = Uri.parse("$apiUrl$endpoint");

    late http.Response response;

    try {
      if (isGet) {
        response = await http.get(uri).timeout(timeout);
      } else {
        response = await http.post(uri, body: body).timeout(timeout);
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      } else {
        throw Exception("Request failed with status: ${response.statusCode}");
      }
    } catch (e) {
      throw Exception("Error accessing $apiUrl: $e");
    }
  }

  // Fetch profile data
  Future<Map<String, dynamic>> fetchProfile(String idNumber) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_fetchProfile.php?idNumber=$idNumber";
    return _makeParallelRequests(endpoint: endpoint, isGet: true);
  }

  // Get last ID number
  Future<String?> getLastIdNumber(String deviceId) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_getLastId.php?deviceId=$deviceId";

    try {
      final data = await _makeParallelRequests(endpoint: endpoint, isGet: true);

      if (data["success"] == true) {
        return data["idNumber"];
      }
      return null;
    } catch (e) {
      // Device has no last ID number
      return null;
    }
  }

  // Logout from device
  Future<void> logout(String deviceId) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_logout.php";

    final data = await _makeParallelRequests(
      endpoint: endpoint,
      body: {'deviceId': deviceId},
    );

    if (data["success"] != true) {
      throw Exception(data["message"] ?? "Logout failed");
    }
  }

  // Confirm logout WTR
  Future<Map<String, dynamic>> confirmLogoutWTR(String idNumber) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_confirmLogoutWTR.php";

    final data = await _makeParallelRequests(
      endpoint: endpoint,
      body: {'idNumber': idNumber},
    );

    if (data["success"] != true) {
      throw Exception(data["message"] ?? "Confirm logout WTR failed");
    }

    return data;
  }

  // Check DTR record
  Future<bool> _checkDTRRecord(String idNumber) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_checkDTR.php?idNumber=$idNumber";

    final data = await _makeParallelRequests(endpoint: endpoint, isGet: true);
    return data["hasDTRRecord"] == true;
  }

  // Insert WTR
  Future<Map<String, dynamic>> insertWTR(String idNumber, {required String deviceId, String phoneCondition = 'Good'}) async {
    // First check if there's an existing active WTR record
    final checkEndpoint = "V4/Others/Kurt/ArkLogAPI/kurt_checkActiveWTR.php";

    try {
      final checkData = await _makeParallelRequests(
        endpoint: checkEndpoint,
        body: {'idNumber': idNumber},
      );

      if (checkData["success"] == true && checkData["hasActiveSessions"] == true) {
        // Update the existing WTR record
        final updateEndpoint = "V4/Others/Kurt/ArkLogAPI/kurt_existingInsert.php";

        final updateData = await _makeParallelRequests(
          endpoint: updateEndpoint,
          body: {
            'idNumber': idNumber,
            'deviceId': deviceId,
            'phoneCondition': phoneCondition,
          },
        );

        if (updateData["success"] == true) {
          return {
            "success": true,
            "message": "Existing WTR login found and updated",
            "hasActiveLogin": true,
            "updated": true
          };
        }
      }
    } catch (e) {
      // Continue to normal insertion if check or update fails
    }

    // Normal insertion
    final insertEndpoint = "V4/Others/Kurt/ArkLogAPI/kurt_insertWTR.php";

    final data = await _makeParallelRequests(
      endpoint: insertEndpoint,
      body: {
        'idNumber': idNumber,
        'deviceId': deviceId,
        'phoneCondition': phoneCondition,
      },
    );

    if (data["success"] != true) {
      throw Exception(data["message"] ?? "Insert WTR failed");
    }

    // Check for active login without logout
    if (data["hasActiveLogin"] == true) {
      return {
        "success": true,
        "message": "Existing WTR login found without logout",
        "hasActiveLogin": true,
      };
    }

    // Check if WTR record already existed
    if (data["alreadyExists"] == true) {
      return {
        "success": true,
        "message": "WTR record already exists",
        "isLate": false,
      };
    }

    return data;
  }

  // Insert ID number
  Future<String> insertIdNumber(String idNumber, {required String deviceId}) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_idLog.php";

    try {
      final data = await _makeParallelRequests(
        endpoint: endpoint,
        body: {
          'idNumber': idNumber,
          'deviceId': deviceId,
        },
      );

      if (data["success"] == true) {
        // Check if there's a DTR record before proceeding
        final dtrCheck = await _checkDTRRecord(data["idNumber"] ?? idNumber);
        if (!dtrCheck) {
          throw Exception("Please Log first on DTR");
        }
        return data["idNumber"] ?? idNumber;
      } else {
        throw Exception(data["message"] ?? "Insert ID number failed");
      }
    } catch (e) {
      if (e is Exception && (e.toString().contains("ID number does not exist") ||
          e.toString().contains("Please Log first on DTR"))) {
        rethrow;
      }
      rethrow;
    }
  }

  // Check active login
  Future<Map<String, dynamic>> checkActiveLogin(String idNumber) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_checkActiveLogin.php";

    return _makeParallelRequests(
      endpoint: endpoint,
      body: {'idNumber': idNumber},
    );
  }

  // Logout WTR
  Future<Map<String, dynamic>> logoutWTR(String idNumber, {String? phoneConditionOut}) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_logoutWTR.php";

    final body = {'idNumber': idNumber};
    if (phoneConditionOut != null) {
      body['phoneConditionOut'] = phoneConditionOut;
    }

    final data = await _makeParallelRequests(endpoint: endpoint, body: body);

    if (data["success"] != true) {
      throw Exception(data["message"] ?? "Logout WTR failed");
    }

    return data;
  }

  // Check active WTR
  Future<Map<String, dynamic>> checkActiveWTR(String idNumber) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_checkAnyActiveWTR.php";

    final data = await _makeParallelRequests(
      endpoint: endpoint,
      body: {'idNumber': idNumber},
    );

    if (data["success"] != true) {
      throw Exception(data["message"] ?? "Check active WTR failed");
    }

    return data;
  }

  // Fetch time ins
  Future<Map<String, dynamic>> fetchTimeIns(String idNumber) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_fetchTimeIn.php?idNumber=$idNumber";
    return _makeParallelRequests(endpoint: endpoint, isGet: true);
  }

  // Check exclusive login
  Future<Map<String, dynamic>> checkExclusiveLogin(String deviceId) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_checkExclusive.php";

    return _makeParallelRequests(
      endpoint: endpoint,
      body: {'deviceId': deviceId},
    );
  }

  // Auto login exclusive user
  Future<bool> autoLoginExclusiveUser(String idNumber, String deviceId) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_idLog.php";

    try {
      final data = await _makeParallelRequests(
        endpoint: endpoint,
        body: {
          'idNumber': idNumber,
          'deviceId': deviceId,
        },
      );

      return data["success"] == true;
    } catch (e) {
      return false;
    }
  }

  // Get shift time info
  Future<Map<String, dynamic>> getShiftTimeInfo(String idNumber) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_getShiftTimeInfo.php";

    final data = await _makeParallelRequests(
      endpoint: endpoint,
      body: {'idNumber': idNumber},
    );

    if (data["success"] != true) {
      throw Exception(data["message"] ?? "Get shift time info failed");
    }

    return {
      "timeIn": data["dtrTimeIn"] ?? 'N/A',  // From hr_dtr
      "loginTime": data["wtrTimeIn"] ?? 'N/A' // From hr_wtr
    };
  }

  // Get output today
  Future<Map<String, dynamic>> getOutputToday(String idNumber) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_getOutputToday.php";

    final data = await _makeParallelRequests(
      endpoint: endpoint,
      body: {'idNumber': idNumber},
    );

    if (data["success"] != true) {
      throw Exception(data["message"] ?? "Get output today failed");
    }

    return data;
  }

  // Fetch phone name
  Future<String> fetchPhoneName(String deviceId) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_fetchPhoneName.php";
    const defaultPhoneName = "ARK LOG PH";

    try {
      final data = await _makeParallelRequests(
        endpoint: endpoint,
        body: {'deviceId': deviceId},
      );

      if (data["success"] == true && data.containsKey("phoneName")) {
        return data["phoneName"];
      }
    } catch (e) {
      // Return default name if request fails
    }

    return defaultPhoneName;
  }

  // Fetch manual link
  Future<String> fetchManualLink(int linkID, int languageFlag) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_fetchManualLink.php?linkID=$linkID";

    final data = await _makeParallelRequests(endpoint: endpoint, isGet: true);

    if (data.containsKey("manualLinkPH") && data.containsKey("manualLinkJP")) {
      String relativePath = languageFlag == 1 ? data["manualLinkPH"] : data["manualLinkJP"];
      if (relativePath.isEmpty) {
        throw Exception("No manual available for selected language");
      }

      // Use the last successful URL to resolve the relative path
      if (_lastSuccessfulUrl != null) {
        return Uri.parse(_lastSuccessfulUrl!).resolve(relativePath).toString();
      } else {
        // Use the first URL if no successful URL is available
        return Uri.parse(apiUrls[0]).resolve(relativePath).toString();
      }
    } else {
      throw Exception(data["error"] ?? "Failed to fetch manual link");
    }
  }

  // Update language flag
  Future<bool> updateLanguageFlag(String idNumber, int languageFlag) async {
    final endpoint = "V4/Others/Kurt/ArkLogAPI/kurt_updateLanguageFlag.php";

    try {
      final data = await _makeParallelRequests(
        endpoint: endpoint,
        body: {
          'idNumber': idNumber,
          'languageFlag': languageFlag.toString(),
        },
      );

      return data["success"] == true;
    } catch (e) {
      return false;
    }
  }
}