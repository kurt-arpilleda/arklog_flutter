import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const List<String> apiUrls = [
    "http://192.168.254.163/",
    "http://126.209.7.246/"
  ];

  static const Duration requestTimeout = Duration(seconds: 2);
  static const int maxRetries = 6;
  static const Duration initialRetryDelay = Duration(seconds: 1);

  Future<Map<String, dynamic>> fetchProfile(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI2/kurt_fetchProfile.php?idNumber=$idNumber");
          final response = await http.get(uri).timeout(requestTimeout);

          if (response.statusCode == 200) {
            return jsonDecode(response.body);
          }
        } catch (e) {
          // print("Error accessing $apiUrl on attempt $attempt: $e");
        }
      }
      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1));
        await Future.delayed(delay);
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<String?> getLastIdNumber(String deviceId) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI2/kurt_getLastId.php?deviceId=$deviceId");
          final response = await http.get(uri).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return data["idNumber"];
            }
            return null;
          }
        } catch (e) {
          // print("Error accessing $apiUrl on attempt $attempt: $e");
        }
      }
      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1));
        await Future.delayed(delay);
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<void> logout(String deviceId) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI2/kurt_logout.php");
          final response = await http.post(
            uri,
            body: {'deviceId': deviceId},
          ).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return;
            } else {
              throw Exception(data["message"]);
            }
          }
        } catch (e) {
          // print("Error accessing $apiUrl on attempt $attempt: $e");
        }
      }
      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1));
        await Future.delayed(delay);
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }
  Future<Map<String, dynamic>> confirmLogoutWTR(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI2/kurt_confirmLogoutWTR.php");
          final response = await http.post(
            uri,
            body: {'idNumber': idNumber},
          ).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return data;
            } else {
              throw Exception(data["message"]);
            }
          }
        } catch (e) {
          // print("Error accessing $apiUrl on attempt $attempt: $e");
        }
      }
      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1));
        await Future.delayed(delay);
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<String> insertIdNumber(String idNumber, {required String deviceId}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI2/kurt_idLog.php");
          final response = await http.post(
            uri,
            body: {
              'idNumber': idNumber,
              'deviceId': deviceId,
            },
          ).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              // Check if there's a DTR record before proceeding
              final dtrCheck = await _checkDTRRecord(data["idNumber"] ?? idNumber);
              if (!dtrCheck) {
                throw Exception("Please Log first on DTR");
              }
              return data["idNumber"] ?? idNumber;
            } else {
              throw Exception(data["message"] ?? "Unknown error occurred");
            }
          }
        } catch (e) {
          if (e is Exception && (e.toString().contains("ID number does not exist") ||
              e.toString().contains("Please Log first on DTR"))) {
            throw e;
          }
          // Otherwise continue with retry logic
        }
      }
      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1));
        await Future.delayed(delay);
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<bool> _checkDTRRecord(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI2/kurt_checkDTR.php?idNumber=$idNumber");
          final response = await http.get(uri).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            return data["hasDTRRecord"] == true;
          }
        } catch (e) {
          // Continue with retry logic
        }
      }
      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1));
        await Future.delayed(delay);
      }
    }
    throw Exception("Failed to check DTR record after $maxRetries attempts");
  }

  Future<Map<String, dynamic>> insertWTR(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI2/kurt_insertWTR2.php");
          final response = await http.post(
            uri,
            body: {
              'idNumber': idNumber,
            },
          ).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              // Check if there's an active login without logout
              if (data["hasActiveLogin"] == true) {
                return {
                  "success": true,
                  "message": "Existing WTR login found without logout",
                  "hasActiveLogin": true,
                };
              }
              // Check if WTR record already existed (completed session)
              if (data["alreadyExists"] == true) {
                return {
                  "success": true,
                  "message": "WTR record already exists",
                  "isLate": false,
                };
              }
              return data;
            } else {
              throw Exception(data["message"] ?? "Unknown error occurred");
            }
          }
        } catch (e) {
          if (e is Exception && e.toString().contains("ID number does not exist")) {
            throw e;
          }
          // Otherwise continue with retry logic
        }
      }
      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1));
        await Future.delayed(delay);
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<Map<String, dynamic>> logoutWTR(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI2/kurt_logoutWTR2.php");
          final response = await http.post(
            uri,
            body: {'idNumber': idNumber},
          ).timeout(requestTimeout);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              // Skip if already logged out
              if (data['alreadyLoggedOut'] == true) {
                return data;
              }
              // Return undertime data if applicable
              return data;
            } else {
              throw Exception(data["message"]);
            }
          }
        } catch (e) {
          // print("Error accessing $apiUrl on attempt $attempt: $e");
        }
      }
      if (attempt < maxRetries) {
        final delay = initialRetryDelay * (1 << (attempt - 1));
        await Future.delayed(delay);
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }
}