import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'package:unique_identifier/unique_identifier.dart';
import 'package:http/http.dart' as http;
import 'auto_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttertoast/fluttertoast.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _idController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final ApiService _apiService = ApiService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isLoading = false;
  bool _isInitializing = true; // New flag for initial loading
  String? _firstName;
  String? _surName;
  String? _profilePictureUrl;
  String? _deviceId;
  bool _isLoggedIn = false;
  String? _currentIdNumber;
  int? _currentLanguageFlag;
  String? _phOrJp;
  bool _isPhCountryPressed = false;
  bool _isJpCountryPressed = false;
  bool _isCountryLoadingPh = false;
  bool _isCountryLoadingJp = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      setState(() {
        _isInitializing = true;
      });

      await _initializeDeviceId();
      await _loadCurrentLanguageFlag();
      await _loadPhOrJp();
      await AutoUpdate.checkForUpdate(context);

      if (_deviceId != null) {
        await _loadLastIdNumber();
      }
    } catch (e) {
      debugPrint("Error initializing app: $e");
    } finally {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  Future<void> _loadCurrentLanguageFlag() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentLanguageFlag = prefs.getInt('languageFlag') ?? 1;
    });
  }

  Future<void> _loadPhOrJp() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _phOrJp = prefs.getString('phorjp') ?? 'ph';
    });
  }

  Future<void> _updateLanguageFlag(int flag) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('languageFlag', flag);
    setState(() {
      _currentLanguageFlag = flag;
    });
  }

  Future<void> _updatePhOrJp(String value) async {
    if ((value == 'ph' && _isCountryLoadingPh) || (value == 'jp' && _isCountryLoadingJp)) {
      return;
    }

    setState(() {
      if (value == 'ph') {
        _isCountryLoadingPh = true;
        _isPhCountryPressed = true;
      } else {
        _isCountryLoadingJp = true;
        _isJpCountryPressed = true;
      }
    });

    await Future.delayed(Duration(milliseconds: 100));

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('phorjp', value);
      setState(() {
        _phOrJp = value;
      });

      if (value == "ph") {
        Navigator.pushReplacementNamed(context, '/login');
      } else if (value == "jp") {
        Navigator.pushReplacementNamed(context, '/loginJP');
      }
    } catch (e) {
      print("Error updating country preference: $e");
      Fluttertoast.showToast(
        msg: "Error updating country: ${e.toString()}",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
      );
    } finally {
      setState(() {
        if (value == 'ph') {
          _isCountryLoadingPh = false;
          _isPhCountryPressed = false;
        } else {
          _isCountryLoadingJp = false;
          _isJpCountryPressed = false;
        }
      });
    }
  }

  Future<void> _showInputMethodPicker() async {
    try {
      if (Platform.isAndroid) {
        const MethodChannel channel = MethodChannel('input_method_channel');
        await channel.invokeMethod('showInputMethodPicker');
      } else {
        Fluttertoast.showToast(
          msg: "Keyboard selection is only available on Android",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
        );
      }
    } catch (e) {
      debugPrint("Error showing input method picker: $e");
    }
  }

  Future<void> _initializeDeviceId() async {
    _deviceId = await _getDeviceId();
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

        String primaryUrl = "${ApiService.apiUrls[0]}V4/11-A%20Employee%20List%20V2/profilepictures/$profilePictureFileName";
        bool isPrimaryUrlValid = await _isImageAvailable(primaryUrl);

        String fallbackUrl = "${ApiService.apiUrls[1]}V4/11-A%20Employee%20List%20V2/profilepictures/$profilePictureFileName";
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
      key: _scaffoldKey,
      backgroundColor: Colors.grey[100],
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight - 20),
        child: SafeArea(
          child: AppBar(
            backgroundColor: Color(0xFF3452B4),
            centerTitle: true,
            toolbarHeight: kToolbarHeight - 20,
            leading: Padding(
              padding: const EdgeInsets.only(left: 10.0),
              child: IconButton(
                icon: Icon(
                  Icons.settings,
                  color: Colors.white,
                ),
                onPressed: () {
                  _scaffoldKey.currentState?.openDrawer();
                },
              ),
            ),
            title: _currentIdNumber != null
                ? Text(
              "ID: $_currentIdNumber",
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
                shadows: [
                  Shadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 2,
                    offset: Offset(1, 1),
                  ),
                ],
              ),
            )
                : null,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 10.0),
                child: IconButton(
                  icon: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red,
                    ),
                    alignment: Alignment.center,
                    width: 36,
                    height: 36,
                    child: Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  onPressed: () {
                    if (Platform.isIOS) {
                      exit(0);
                    } else {
                      SystemNavigator.pop();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      drawer: SizedBox(
        width: MediaQuery.of(context).size.width * 0.70,
        child: Drawer(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          color: Color(0xFF2053B3),
                          padding: EdgeInsets.only(top: 20, bottom: 20),
                          child: Column(
                            children: [
                              Text(
                                'ARK LOG PH',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Row(
                            children: [
                              Text(
                                "Language",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 25),
                              GestureDetector(
                                onTap: () => _updateLanguageFlag(1),
                                child: Column(
                                  children: [
                                    Image.asset(
                                      'assets/images/americanFlag.gif',
                                      width: 40,
                                      height: 40,
                                    ),
                                    if (_currentLanguageFlag == 1)
                                      Container(
                                        height: 2,
                                        width: 40,
                                        color: Colors.blue,
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 30),
                              GestureDetector(
                                onTap: () => _updateLanguageFlag(2),
                                child: Column(
                                  children: [
                                    Image.asset(
                                      'assets/images/japaneseFlag.gif',
                                      width: 40,
                                      height: 40,
                                    ),
                                    if (_currentLanguageFlag == 2)
                                      Container(
                                        height: 2,
                                        width: 40,
                                        color: Colors.blue,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.only(left: 16.0),
                          child: Row(
                            children: [
                              Text(
                                "Keyboard",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 15),
                              IconButton(
                                icon: Icon(Icons.keyboard, size: 28),
                                iconSize: 28,
                                onPressed: () {
                                  _showInputMethodPicker();
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Text(
                        "Country",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 25),
                      GestureDetector(
                        onTapDown: (_) => setState(() => _isPhCountryPressed = true),
                        onTapUp: (_) => setState(() => _isPhCountryPressed = false),
                        onTapCancel: () => setState(() => _isPhCountryPressed = false),
                        onTap: () => _updatePhOrJp("ph"),
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 100),
                          transform: Matrix4.identity()..scale(_isPhCountryPressed ? 0.95 : 1.0),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.asset(
                                'assets/images/philippines.png',
                                width: 40,
                                height: 40,
                              ),
                              if (_phOrJp == "ph" && !_isCountryLoadingPh)
                                Opacity(
                                  opacity: 0.6,
                                  child: Icon(Icons.refresh, size: 20, color: Colors.white),
                                ),
                              if (_isCountryLoadingPh)
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                    strokeWidth: 2,
                                  ),
                                ),
                              if (_phOrJp == "ph")
                                Positioned(
                                  bottom: 0,
                                  child: Container(
                                    height: 2,
                                    width: 40,
                                    color: Colors.blue,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 30),
                      GestureDetector(
                        onTapDown: (_) => setState(() => _isJpCountryPressed = true),
                        onTapUp: (_) => setState(() => _isJpCountryPressed = false),
                        onTapCancel: () => setState(() => _isJpCountryPressed = false),
                        onTap: () => _updatePhOrJp("jp"),
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: 100),
                          transform: Matrix4.identity()..scale(_isJpCountryPressed ? 0.95 : 1.0),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Image.asset(
                                'assets/images/japan.png',
                                width: 40,
                                height: 40,
                              ),
                              if (_phOrJp == "jp" && !_isCountryLoadingJp)
                                Opacity(
                                  opacity: 0.6,
                                  child: Icon(Icons.refresh, size: 20, color: Colors.white),
                                ),
                              if (_isCountryLoadingJp)
                                SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                    strokeWidth: 2,
                                  ),
                                ),
                              if (_phOrJp == "jp")
                                Positioned(
                                  bottom: 0,
                                  child: Container(
                                    height: 2,
                                    width: 40,
                                    color: Colors.blue,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Center(
        child: _isInitializing
            ? CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3452B4)),
        )
            : SingleChildScrollView(
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
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.5,
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