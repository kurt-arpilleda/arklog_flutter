import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const List<String> apiUrls = [
    "http://192.168.254.163/",
    "http://126.209.7.246/"
  ];

  static const Duration requestTimeout = Duration(seconds: 2);
  static const int maxRetries = 6;
  static const Duration initialRetryDelay = Duration(seconds: 1);

  // Cache for the last working server index
  int? _lastWorkingServerIndex;
  late http.Client httpClient;
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  ApiService() {
    httpClient = _createHttpClient();
  }

  http.Client _createHttpClient() {
    final HttpClient client = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return IOClient(client);
  }

  void _showToast(String message) {
    Fluttertoast.showToast(
      msg: message,
      toastLength: Toast.LENGTH_LONG,
      gravity: ToastGravity.BOTTOM,
    );
  }

  // Helper method to make parallel requests and return the first successful response
  Future<T> _makeParallelRequest<T>(Future<T> Function(String apiUrl) requestFn) async {
    // Try the last working server first if available
    if (_lastWorkingServerIndex != null) {
      try {
        final result = await requestFn(apiUrls[_lastWorkingServerIndex!])
            .timeout(requestTimeout);
        return result;
      } catch (e) {
        // If the last working server fails, proceed with parallel requests
      }
    }

    // Create a list of futures for all API URLs
    final futures = apiUrls.map((apiUrl) => requestFn(apiUrl).timeout(requestTimeout));

    // Use Future.any to get the first successful response
    try {
      final result = await Future.any(futures);
      // Remember which server worked
      _lastWorkingServerIndex = apiUrls.indexOf((result as dynamic).apiUrlUsed ?? apiUrls[0]);
      return result;
    } catch (e) {
      // If all parallel requests fail, throw an exception
      throw Exception("All API URLs are unreachable");
    }
  }

  Future<Map<String, dynamic>> fetchProfile(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_fetchProfile.php?idNumber=$idNumber");
          final response = await httpClient.get(uri);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return _ApiResult(data, apiUrl);
            } else {
              throw Exception(data["message"] ?? "Profile fetch failed");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<String?> getLastIdNumber(String deviceId) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_getLastId.php?deviceId=$deviceId");
          final response = await httpClient.get(uri);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return _ApiResult(data["idNumber"], apiUrl);
            }
            return _ApiResult(null, apiUrl);
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<void> logout(String deviceId) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_logout.php");
          final response = await httpClient.post(
            uri,
            body: {'deviceId': deviceId},
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return _ApiResult(null, apiUrl);
            } else {
              throw Exception(data["message"]);
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });
        return; // Success
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<Map<String, dynamic>> confirmLogoutWTR(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_confirmLogoutWTR.php");
          final response = await httpClient.post(
            uri,
            body: {'idNumber': idNumber},
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return _ApiResult(data, apiUrl);
            } else {
              throw Exception(data["message"]);
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<bool> _checkDTRRecord(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_checkDTR.php?idNumber=$idNumber");
          final response = await httpClient.get(uri);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            return _ApiResult(data["hasDTRRecord"] == true, apiUrl);
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Failed to check DTR record after $maxRetries attempts");
  }

  Future<Map<String, dynamic>> insertWTR(String idNumber, {required String deviceId, String phoneCondition = 'Good'}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          // Check if there's an existing active WTR record first
          final checkUri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_checkActiveWTR.php");
          final checkResponse = await httpClient.post(
            checkUri,
            body: {'idNumber': idNumber},
          );

          if (checkResponse.statusCode == 200) {
            final checkData = jsonDecode(checkResponse.body);

            if (checkData["success"] == true && checkData["hasActiveSessions"] == true) {
              // Update the existing WTR record with phoneName and dateInDetail
              final updateUri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_existingInsert.php");
              final updateResponse = await httpClient.post(
                updateUri,
                body: {
                  'idNumber': idNumber,
                  'deviceId': deviceId,
                  'phoneCondition': phoneCondition,
                },
              );

              if (updateResponse.statusCode == 200) {
                final updateData = jsonDecode(updateResponse.body);
                if (updateData["success"] == true) {
                  return _ApiResult({
                    "success": true,
                    "message": "Existing WTR login found and updated",
                    "hasActiveLogin": true,
                    "updated": true
                  }, apiUrl);
                }
              }
            }
          }

          // If no active sessions or update failed, proceed with normal insertion
          final insertUri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_insertWTR.php");
          final response = await httpClient.post(
            insertUri,
            body: {
              'idNumber': idNumber,
              'deviceId': deviceId,
              'phoneCondition': phoneCondition,
            },
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              // Check if there's an active login without logout
              if (data["hasActiveLogin"] == true) {
                return _ApiResult({
                  "success": true,
                  "message": "Existing WTR login found without logout",
                  "hasActiveLogin": true,
                }, apiUrl);
              }
              // Check if WTR record already existed (completed session)
              if (data["alreadyExists"] == true) {
                return _ApiResult({
                  "success": true,
                  "message": "WTR record already exists",
                  "isLate": false,
                }, apiUrl);
              }
              return _ApiResult(data, apiUrl);
            } else {
              throw Exception(data["message"] ?? "Unknown error occurred");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        if (e is Exception && e.toString().contains("ID number does not exist")) {
          throw e;
        }
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<String> insertIdNumber(String idNumber, {required String deviceId}) async {
    // First check if ID exists and is active
    try {
      final exists = await _checkIdExistsAndActive(idNumber);
      if (!exists) {
        throw Exception("This ID is not existing or is not active");
      }
    } catch (e) {
      throw Exception("This ID is not existing or is not active");
    }

    // If ID exists and is active, proceed with the original logic
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_idLog.php");
          final response = await httpClient.post(
            uri,
            body: {
              'idNumber': idNumber,
              'deviceId': deviceId,
            },
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              // Check if there's a DTR record before proceeding
              final dtrCheck = await _checkDTRRecord(data["idNumber"] ?? idNumber);
              if (!dtrCheck) {
                throw Exception("Please Log first on DTR");
              }
              return _ApiResult(data["idNumber"] ?? idNumber, apiUrl);
            } else {
              throw Exception(data["message"] ?? "Unknown error occurred");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        if (e is Exception && (e.toString().contains("ID number does not exist") ||
            e.toString().contains("Please Log first on DTR"))) {
          throw e;
        }
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<bool> _checkIdExistsAndActive(String idNumber) async {
    try {
      final response = await _makeParallelRequest((apiUrl) async {
        final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_checkId.php");
        final response = await httpClient.post(
          uri,
          body: {'idNumber': idNumber},
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return _ApiResult(data["exists"] ?? false, apiUrl);
        }
        throw Exception("HTTP ${response.statusCode}");
      });
      return response.value;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> checkActiveLogin(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_checkActiveLogin.php");
          final response = await httpClient.post(
            uri,
            body: {
              'idNumber': idNumber,
            },
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            return _ApiResult(data, apiUrl);
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<Map<String, dynamic>> logoutWTR(String idNumber, {String? phoneConditionOut}) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_logoutWTR.php");
          final response = await httpClient.post(
            uri,
            body: {
              'idNumber': idNumber,
              if (phoneConditionOut != null) 'phoneConditionOut': phoneConditionOut,
            },
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              // Skip if already logged out
              if (data['alreadyLoggedOut'] == true) {
                return _ApiResult(data, apiUrl);
              }
              // Return undertime data if applicable
              return _ApiResult(data, apiUrl);
            } else {
              throw Exception(data["message"]);
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<Map<String, dynamic>> checkActiveWTR(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_checkAnyActiveWTR.php");
          final response = await httpClient.post(
            uri,
            body: {'idNumber': idNumber},
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return _ApiResult(data, apiUrl);
            } else {
              throw Exception(data["message"]);
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<Map<String, dynamic>> fetchTimeIns(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_fetchTimeIn.php?idNumber=$idNumber");
          final response = await httpClient.get(uri);

          if (response.statusCode == 200) {
            return _ApiResult(jsonDecode(response.body), apiUrl);
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }

  Future<Map<String, dynamic>> checkExclusiveLogin(String deviceId) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_checkExclusive.php");
          final response = await httpClient.post(
            uri,
            body: {'deviceId': deviceId},
          );

          if (response.statusCode == 200) {
            return _ApiResult(jsonDecode(response.body), apiUrl);
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Failed to check exclusive login after $maxRetries attempts");
  }

  Future<bool> autoLoginExclusiveUser(String idNumber, String deviceId) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_idLog.php");
          final response = await httpClient.post(
            uri,
            body: {
              'idNumber': idNumber,
              'deviceId': deviceId,
            },
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            return _ApiResult(data["success"] == true, apiUrl);
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Failed to auto-login exclusive user after $maxRetries attempts");
  }

  Future<String> fetchPhoneName(String deviceId) async {
    String defaultPhoneName = "ARK LOG PH";

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_fetchPhoneName.php");
          final response = await httpClient.post(
            uri,
            body: {
              'deviceId': deviceId,
            },
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true && data.containsKey("phoneName")) {
              return _ApiResult(data["phoneName"], apiUrl);
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    // Return default name if all attempts fail
    return defaultPhoneName;
  }

  Future<String> fetchManualLink(int linkID, int languageFlag) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_fetchManualLink.php?linkID=$linkID");
          final response = await httpClient.get(uri);

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data.containsKey("manualLinkPH") && data.containsKey("manualLinkJP")) {
              String relativePath = languageFlag == 1 ? data["manualLinkPH"] : data["manualLinkJP"];
              if (relativePath.isEmpty) {
                throw Exception("No manual available for selected language");
              }
              return _ApiResult(Uri.parse(apiUrl).resolve(relativePath).toString(), apiUrl);
            } else {
              throw Exception(data["error"]);
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          print("Waiting for ${delay.inSeconds} seconds before retrying...");
          await Future.delayed(delay);
        }
      }
    }

    String finalError = "All API URLs are unreachable after $maxRetries attempts";
    _showToast(finalError);
    throw Exception(finalError);
  }

  Future<bool> updateLanguageFlag(String idNumber, int languageFlag) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_updateLanguageFlag.php");
          final response = await httpClient.post(
            uri,
            body: {
              'idNumber': idNumber,
              'languageFlag': languageFlag.toString(),
            },
          );

          if (response.statusCode == 200) {
            final responseData = jsonDecode(response.body);
            return _ApiResult(responseData["success"] == true, apiUrl);
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }
  Future<Map<String, dynamic>> getWorkTimeInfo(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_getWorkTimeInfo.php");
          final response = await httpClient.post(
            uri,
            body: {
              'idNumber': idNumber,
            },
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return _ApiResult({
                "workRequired": data["workRequired"] ?? '0.0',
                "workedHours": data["workedHours"] ?? '0.0',
                "overTime": data["overTime"] ?? '0.0',
                "lateCount": data["lateCount"] ?? '0',
              }, apiUrl);
            } else {
              throw Exception(data["message"] ?? "Unknown error occurred");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }
  Future<Map<String, dynamic>> getTodayOutput(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_getTodayOutput.php");
          final response = await httpClient.post(
            uri,
            body: {
              'idNumber': idNumber,
            },
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return _ApiResult({
                "outputQty": data["outputQty"] ?? 0,
                "stTime": data["stTime"] ?? '00:00:00',
                "ngQty": data["ngQty"] ?? 0,
                "ngCount": data["ngCount"] ?? 0,
              }, apiUrl);
            } else {
              throw Exception(data["message"] ?? "Unknown error occurred");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }
  Future<Map<String, dynamic>> insertDailyPerformance(String idNumber) async {
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final result = await _makeParallelRequest((apiUrl) async {
          final uri = Uri.parse("${apiUrl}V4/Others/Kurt/ArkLogAPI/kurt_insertDailyPerformance.php");
          final response = await httpClient.post(
            uri,
            body: {
              'idNumber': idNumber,
            },
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return _ApiResult({
                "success": true,
                "message": data["message"] ?? "Performance data saved successfully",
              }, apiUrl);
            } else {
              throw Exception(data["error"] ?? data["message"] ?? "Unknown error occurred");
            }
          }
          throw Exception("HTTP ${response.statusCode}");
        });

        return result.value;
      } catch (e) {
        print("Attempt $attempt failed: $e");
        if (attempt < maxRetries) {
          final delay = initialRetryDelay * (1 << (attempt - 1));
          await Future.delayed(delay);
        }
      }
    }
    throw Exception("Both API URLs are unreachable after $maxRetries attempts");
  }
}

// Helper class to track which API URL was used
class _ApiResult<T> {
  final T value;
  final String apiUrlUsed;

  _ApiResult(this.value, this.apiUrlUsed);
}