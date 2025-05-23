import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiServiceJP {
  static const List<String> apiUrls = [
    "http://192.168.1.213/",
    "http://220.157.175.232/"
  ];

  static const Duration requestTimeout = Duration(seconds: 2);
  static const int maxRetries = 6;
  static const Duration initialRetryDelay = Duration(seconds: 1);

  Future<String> insertIdNumber(String idNumber, {required String deviceId}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_idLog.php");
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
              // Return the actual idNumber from the response
              return data["idNumber"] ?? idNumber;
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
  Future<Map<String, dynamic>> fetchProfile(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      for (String apiUrl in apiUrls) {
        try {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_fetchProfile.php?idNumber=$idNumber");
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
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_getLastId.php?deviceId=$deviceId");
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
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_logout.php");
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
}