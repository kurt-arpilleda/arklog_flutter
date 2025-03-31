import 'package:flutter/material.dart';
import 'api_service.dart';
import 'package:unique_identifier/unique_identifier.dart';
import 'package:http/http.dart' as http;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _idController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final ApiServiceLog _apiService = ApiServiceLog();
  bool _isLoading = false;
  String? _firstName;
  String? _surName;
  String? _profilePictureUrl;
  String? _deviceId;
  bool _isLoggedIn = false;
  String? _currentIdNumber;

  @override
  void initState() {
    super.initState();
    _initializeDeviceId();
  }

  Future<void> _initializeDeviceId() async {
    _deviceId = await _getDeviceId();
    if (_deviceId != null) {
      _loadLastIdNumber();
    }
  }

  Future<void> _loadLastIdNumber() async {
    try {
      String? lastIdNumber = await _apiService.getLastIdNumber(_deviceId!);
      if (lastIdNumber != null && lastIdNumber.isNotEmpty) {
        _idController.text = lastIdNumber;
        await _fetchProfile(lastIdNumber);
        setState(() {
          _isLoggedIn = true;
          _currentIdNumber = lastIdNumber;
        });
      }
    } catch (e) {
      print('Error loading last ID number: $e');
    }
  }

  Future<void> _fetchProfile(String idNumber) async {
    try {
      final profileData = await _apiService.fetchProfile(idNumber);
      if (profileData["success"] == true) {
        String profilePictureFileName = profileData["picture"];

        String primaryUrl = "${ApiServiceLog.apiUrls[0]}V4/11-A%20Employee%20List%20V2/profilepictures/$profilePictureFileName";
        bool isPrimaryUrlValid = await _isImageAvailable(primaryUrl);

        String fallbackUrl = "${ApiServiceLog.apiUrls[1]}V4/11-A%20Employee%20List%20V2/profilepictures/$profilePictureFileName";
        bool isFallbackUrlValid = await _isImageAvailable(fallbackUrl);

        setState(() {
          _firstName = profileData["firstName"];
          _surName = profileData["surName"];
          _profilePictureUrl = isPrimaryUrlValid ? primaryUrl : isFallbackUrlValid ? fallbackUrl : null;
          _currentIdNumber = idNumber;
        });
      }
    } catch (e) {
      print("Error fetching profile: $e");
    }
  }

  Future<bool> _isImageAvailable(String url) async {
    try {
      final response = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        await _apiService.insertIdNumber(
          _idController.text,
          deviceId: _deviceId!,
        );
        await _fetchProfile(_idController.text);
        setState(() {
          _isLoggedIn = true;
          _currentIdNumber = _idController.text;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully logged in with ID: ${_idController.text}')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    bool confirm = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Confirm Logout"),
          content: const Text("Are you sure you want to logout?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Logout"),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() {
        _isLoading = true;
      });

      try {
        await _apiService.logout(_deviceId!);
        setState(() {
          _isLoggedIn = false;
          _firstName = null;
          _surName = null;
          _profilePictureUrl = null;
          _currentIdNumber = null;
          _idController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logged out successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<String> _getDeviceId() async {
    try {
      String? identifier = await UniqueIdentifier.serial;
      return identifier ?? 'unknown-device';
    } catch (e) {
      print('Error getting device identifier: $e');
      return 'error-getting-device-id';
    }
  }

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3452B4),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'ARK LOG',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isLoggedIn ? 'Welcome ${_firstName ?? ""}' : 'Enter your ID number',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            children: [
                              Container(
                                width: 140,
                                height: 140,
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.blue[50],
                                  border: Border.all(
                                    color: const Color(0xFF3452B4),
                                    width: 3,
                                  ),
                                ),
                                child: _profilePictureUrl != null
                                    ? ClipOval(
                                  child: Image.network(
                                    _profilePictureUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Icon(
                                      Icons.person,
                                      size: 70,
                                      color: const Color(0xFF3452B4),
                                    ),
                                  ),
                                )
                                    : Icon(
                                  Icons.person,
                                  size: 70,
                                  color: const Color(0xFF3452B4),
                                ),
                              ),
                              if (_firstName != null || _surName != null) ...[
                                Text(
                                  '${_firstName ?? ''} ${_surName ?? ''}',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'ID: ${_currentIdNumber ?? ''}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,  // Medium weight
                                    letterSpacing: 0.5,          // Slightly spaced out letters
                                    shadows: [
                                      Shadow(
                                        color: Colors.black.withOpacity(0.2),
                                        blurRadius: 2,
                                        offset: Offset(1, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (!_isLoggedIn)
                            TextFormField(
                              controller: _idController,
                              decoration: InputDecoration(
                                labelText: 'ID Number',
                                prefixIcon: const Icon(Icons.badge),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                filled: true,
                                fillColor: Colors.grey[50],
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your ID number';
                                }
                                return null;
                              },
                            ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _isLoading
                                  ? null
                                  : _isLoggedIn
                                  ? _logout
                                  : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isLoggedIn ? Colors.red : const Color(0xFF3452B4),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: _isLoading
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : Text(
                                _isLoggedIn ? 'LOGOUT' : 'LOGIN',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}