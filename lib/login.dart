import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'pdfViewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';
import 'package:unique_identifier/unique_identifier.dart';
import 'package:http/http.dart' as http;
import 'auto_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final TextEditingController _idController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final ApiService _apiService = ApiService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  QRViewController? qrController;
  bool _isLoading = false;
  bool _isInitializing = true; // New flag for initial loading
  String? _firstName;
  String? _surName;
  String? _profilePictureUrl;
  String? _deviceId;
  bool _isLoggedIn = false;
  String? _currentIdNumber;
  String? _currentLanguage; // Changed from _currentLanguageFlag to _currentLanguage
  String? _phOrJp;
  bool _isPhCountryPressed = false;
  bool _isJpCountryPressed = false;
  bool _isCountryLoadingPh = false;
  bool _isCountryLoadingJp = false;
  String _currentDateTime = '';
  String? _latestTimeIn;
  String? _qrErrorMessage;
  Timer? _timer;
  bool _isExclusiveUser = false;
  bool _isFlashOn = false;
  String _phoneName = 'ARK LOG PH';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    tz.initializeTimeZones();
    _initializeApp();
    _updateDateTime();
    _timer = Timer.periodic(Duration(seconds: 1), (Timer t) => _updateDateTime());

  }
  Future<void> _initializeApp() async {
    try {
      setState(() {
        _isInitializing = true;
      });

      await _initializeDeviceId();
      await _loadCurrentLanguage();
      await _loadPhOrJp();

      if (!AutoUpdate.isUpdating) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          AutoUpdate.checkForUpdate(context);
        });
      }

      // Reset the exclusive user flag to false by default
      bool wasExclusive = _isExclusiveUser;
      setState(() {
        _isExclusiveUser = false;
      });
      if (_deviceId != null) {
        try {
          final fetchedPhoneName = await _apiService.fetchPhoneName(_deviceId!);
          setState(() {
            _phoneName = fetchedPhoneName;
          });
        } catch (e) {
          debugPrint("Error fetching phone name: $e");
          // Continue with default name if fetch fails
        }
      }
      // Check for exclusive login
      if (_deviceId != null) {
        try {
          final exclusiveCheck = await _apiService.checkExclusiveLogin(_deviceId!);
          if (exclusiveCheck['isExclusive'] == true) {
            final idNumber = exclusiveCheck['idNumber'];

            // Check if ID number changed for an exclusive device
            if (_isLoggedIn && _currentIdNumber != idNumber) {
              // ID number changed, handle the change
              setState(() {
                _isLoggedIn = false;
                _currentIdNumber = null;
                _firstName = null;
                _surName = null;
                _profilePictureUrl = null;
                _idController.clear();
              });
            }

            final loginSuccess = await _apiService.autoLoginExclusiveUser(idNumber, _deviceId!);

            if (loginSuccess) {
              await _fetchProfile(idNumber);
              setState(() {
                _isLoggedIn = true;
                _currentIdNumber = idNumber;
                _idController.text = idNumber;
                _isExclusiveUser = true;
              });
              return; // Skip the rest if exclusive login succeeded
            }
          } else if (wasExclusive) {
            // Device was previously exclusive but is no longer
            setState(() {
              _isLoggedIn = false;
              _currentIdNumber = null;
              _firstName = null;
              _surName = null;
              _profilePictureUrl = null;
              _idController.clear();
            });
          }
        } catch (e) {
          debugPrint("Exclusive login check failed: $e");
          // Continue with normal flow if exclusive check fails
        }
        // Normal flow if not exclusive user
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
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // App has come back to the foreground
      _initializeApp(); // Re-run your init logic
    }
  }
  void _updateDateTime() {
    // Get Manila timezone
    final manila = tz.getLocation('Asia/Manila');
    final now = tz.TZDateTime.now(manila);

    final formattedDate = DateFormat('MMMM dd, yyyy HH:mm:ss').format(now);

    if (mounted) {
      setState(() {
        _currentDateTime = formattedDate;
      });
    }
  }

  Future<void> _loadCurrentLanguage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentLanguage = prefs.getString('language') ?? 'en'; // Default to 'en'
    });
  }

  Future<void> _loadPhOrJp() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _phOrJp = prefs.getString('phorjp') ?? 'ph';
    });
  }

  Future<void> _updateLanguage(String language) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', language);
    setState(() {
      _currentLanguage = language;
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

        // Fetch timeIn records
        final timeInData = await _apiService.fetchTimeIns(idNumber);
        String? latestTimeIn = timeInData["latestTimeIn"] != null
            ? _formatTimeIn(timeInData["latestTimeIn"])
            : null;

        setState(() {
          _firstName = profileData["firstName"];
          _surName = profileData["surName"];
          _profilePictureUrl = isPrimaryUrlValid ? primaryUrl : isFallbackUrlValid ? fallbackUrl : null;
          _currentIdNumber = idNumber;
          _latestTimeIn = latestTimeIn;
        });
      }
    } catch (e) {
      print("Error fetching profile: $e");
    }
  }
  String _formatTimeIn(String timeIn) {
    try {
      DateTime dateTime = DateTime.parse(timeIn);
      return DateFormat('hh:mm a').format(dateTime);
    } catch (e) {
      return timeIn; // return as-is if parsing fails
    }
  }

  Future<bool> _isImageAvailable(String url) async {
    try {
      final response = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, String>?> _showPhoneConditionDialogIn() async {
    String? phoneCondition;
    final TextEditingController _explanationController = TextEditingController();
    final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
    final ScrollController _scrollController = ScrollController();
    final FocusNode _explanationFocusNode = FocusNode();

    final GlobalKey _choiceChipsKey = GlobalKey();

    return showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final dialogWidth = screenWidth * 0.95 > 480 ? 480.0 : screenWidth * 0.95;

        return StatefulBuilder(
          builder: (context, setState) {
            final AnimationController _shakeController = AnimationController(
              duration: Duration(milliseconds: 400),
              vsync: Navigator.of(context),
            );

            final Animation<double> _offsetAnimation = TweenSequence<double>([
              TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
              TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
              TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0), weight: 2),
              TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
              TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0), weight: 1),
            ]).animate(_shakeController);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              contentPadding: EdgeInsets.all(24),
              actionsPadding: EdgeInsets.only(right: 16, bottom: 16),
              content: Container(
                width: dialogWidth,
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Column(
                          children: [
                            Image.asset(
                              'assets/images/phonecheck.png',
                              height: 80,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'Phone Condition Check',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey.shade800,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 24),
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.shade900),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Are you sure the phone has no issues or damage before using it? Please be honest — every entry is recorded in the system, and you don\'t want to be held responsible for any existing problems.',
                                  style: TextStyle(
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 20),
                        AnimatedBuilder(
                          animation: _shakeController,
                          builder: (context, child) {
                            return Transform.translate(
                              offset: Offset(_offsetAnimation.value, 0),
                              child: child,
                            );
                          },
                          child: Wrap(
                            key: _choiceChipsKey,
                            spacing: 12,
                            alignment: WrapAlignment.center,
                            children: [
                              ChoiceChip(
                                label: Text('Yes', style: TextStyle(fontWeight: FontWeight.w500)),
                                selected: phoneCondition == 'Yes',
                                selectedColor: Colors.green.shade100,
                                onSelected: (_) {
                                  setState(() => phoneCondition = 'Yes');
                                },
                              ),
                              ChoiceChip(
                                label: Text('No', style: TextStyle(fontWeight: FontWeight.w500)),
                                selected: phoneCondition == 'No',
                                selectedColor: Colors.red.shade100,
                                onSelected: (_) {
                                  setState(() {
                                    phoneCondition = 'No';
                                    Future.delayed(Duration(milliseconds: 300), () {
                                      _scrollController.animateTo(
                                        _scrollController.position.maxScrollExtent,
                                        duration: Duration(milliseconds: 400),
                                        curve: Curves.easeOut,
                                      );
                                      FocusScope.of(context).requestFocus(_explanationFocusNode);
                                    });
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        if (phoneCondition == 'No') ...[
                          SizedBox(height: 20),
                          TextFormField(
                            controller: _explanationController,
                            focusNode: _explanationFocusNode,
                            decoration: InputDecoration(
                              labelText: 'Please explain the issue',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            maxLines: 3,
                            validator: (value) {
                              if (phoneCondition == 'No' &&
                                  (value == null || value.trim().isEmpty)) {
                                return 'Please provide an explanation';
                              }
                              return null;
                            },
                          ),
                        ],
                        SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text('Cancel', style: TextStyle(color: Colors.grey.shade700)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    if (phoneCondition == null) {
                      final contextChoice = _choiceChipsKey.currentContext;
                      if (contextChoice != null) {
                        await Scrollable.ensureVisible(
                          contextChoice,
                          duration: Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                      _shakeController.forward(from: 0);
                      return;
                    }

                    if (phoneCondition == 'No' && !_formKey.currentState!.validate()) {
                      return;
                    }

                    String finalCondition = phoneCondition == 'Yes'
                        ? 'Good'
                        : 'Not Good: ${_explanationController.text.trim()}';

                    Navigator.of(context).pop({'phoneCondition': finalCondition});
                  },
                  child: Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<Map<String, String>?> _showPhoneConditionDialogOut() async {
    String? phoneCondition;
    final TextEditingController _explanationController = TextEditingController();
    final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
    final ScrollController _scrollController = ScrollController();
    final FocusNode _explanationFocusNode = FocusNode();

    final GlobalKey _choiceChipsKey = GlobalKey();

    final currentDate = DateFormat('MMMM d, y').format(DateTime.now());

    Map<String, dynamic> shiftTimeInfo = {};
    Map<String, dynamic> outputToday = {'totalCount': 0, 'totalQty': 0};

    try {
      if (_currentIdNumber != null) {
        setState(() => _isLoading = true);
        shiftTimeInfo = await _apiService.getShiftTimeInfo(_currentIdNumber!);
        outputToday = await _apiService.getOutputToday(_currentIdNumber!);
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      print("Error fetching data: $e");
    }

    return showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final screenWidth = MediaQuery.of(context).size.width;
        final dialogWidth = screenWidth * 0.95 > 480 ? 480.0 : screenWidth * 0.95;

        return StatefulBuilder(
          builder: (context, setState) {
            final AnimationController _shakeController = AnimationController(
              duration: Duration(milliseconds: 400),
              vsync: Navigator.of(context),
            );

            final Animation<double> _offsetAnimation = TweenSequence<double>([
              TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
              TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
              TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0), weight: 2),
              TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
              TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0), weight: 1),
            ]).animate(_shakeController);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              contentPadding: EdgeInsets.all(24),
              actionsPadding: EdgeInsets.only(right: 16, bottom: 16),
              content: Container(
                width: dialogWidth,
                child: Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (_currentIdNumber != null &&
                            (_profilePictureUrl != null || _firstName != null || _surName != null))
                          Column(
                            children: [
                              if (_profilePictureUrl != null)
                                CircleAvatar(
                                  radius: 35,
                                  backgroundImage: NetworkImage(_profilePictureUrl!),
                                  backgroundColor: Colors.grey[300],
                                ),
                              SizedBox(height: 10),
                              if (_firstName != null && _surName != null)
                                Text(
                                  '$_firstName $_surName',
                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center,
                                ),
                              SizedBox(height: 4),
                              Text(
                                currentDate,
                                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                              ),
                              SizedBox(height: 20),

                              _buildInfoCard(
                                title: 'Your Output Today',
                                content: Column(
                                  children: [
                                    _buildInfoRow('Item Count', outputToday['totalCount'].toString()),
                                    SizedBox(height: 8),
                                    _buildInfoRow('Item Quantity', outputToday['totalQty'].toString()),
                                  ],
                                ),
                                backgroundColor: Colors.indigo.shade50,
                                titleColor: Colors.indigo.shade800,
                                centerTitle: true,
                              ),
                              SizedBox(height: 16),

                              if (shiftTimeInfo.isNotEmpty)
                                _buildInfoCard(
                                  title: 'Time Log',
                                  content: Column(
                                    children: [
                                      _buildTimeRow('Time In', shiftTimeInfo['timeIn'] ?? 'N/A'),
                                      SizedBox(height: 8),
                                      _buildTimeRow('Login', shiftTimeInfo['loginTime'] ?? 'N/A'),
                                    ],
                                  ),
                                  backgroundColor: Colors.grey.shade100,
                                  titleColor: Colors.grey.shade800,
                                  centerTitle: true,
                                ),
                              SizedBox(height: 24),
                            ],
                          ),
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Do you confirm the phone has no issues before handing it to the guard?',
                                  style: TextStyle(
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 20),

                        AnimatedBuilder(
                          animation: _shakeController,
                          builder: (context, child) {
                            return Transform.translate(
                              offset: Offset(_offsetAnimation.value, 0),
                              child: child,
                            );
                          },
                          child: Wrap(
                            key: _choiceChipsKey,
                            spacing: 12,
                            alignment: WrapAlignment.center,
                            children: [
                              ChoiceChip(
                                label: Text('Yes'),
                                selected: phoneCondition == 'Yes',
                                selectedColor: Colors.green.shade100,
                                onSelected: (_) {
                                  setState(() => phoneCondition = 'Yes');
                                },
                              ),
                              ChoiceChip(
                                label: Text('No'),
                                selected: phoneCondition == 'No',
                                selectedColor: Colors.red.shade100,
                                onSelected: (_) {
                                  setState(() {
                                    phoneCondition = 'No';
                                    Future.delayed(Duration(milliseconds: 300), () {
                                      _scrollController.animateTo(
                                        _scrollController.position.maxScrollExtent,
                                        duration: Duration(milliseconds: 400),
                                        curve: Curves.easeOut,
                                      );
                                      FocusScope.of(context).requestFocus(_explanationFocusNode);
                                    });
                                  });
                                },
                              ),
                            ],
                          ),
                        ),

                        if (phoneCondition == 'No') ...[
                          SizedBox(height: 20),
                          TextFormField(
                            controller: _explanationController,
                            focusNode: _explanationFocusNode,
                            decoration: InputDecoration(
                              labelText: 'Please explain the issue',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            maxLines: 3,
                            validator: (value) {
                              if (phoneCondition == 'No' &&
                                  (value == null || value.trim().isEmpty)) {
                                return 'Please provide an explanation';
                              }
                              return null;
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    if (phoneCondition == null) {
                      final contextChoice = _choiceChipsKey.currentContext;
                      if (contextChoice != null) {
                        await Scrollable.ensureVisible(
                          contextChoice,
                          duration: Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                      _shakeController.forward(from: 0);
                      return;
                    }

                    if (phoneCondition == 'No' && !_formKey.currentState!.validate()) {
                      return;
                    }

                    String finalCondition = phoneCondition == 'Yes'
                        ? 'Good'
                        : 'Not Good: ${_explanationController.text.trim()}';

                    Navigator.of(context).pop({'phoneConditionOut': finalCondition});
                  },
                  child: Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTimeRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.w500)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.blueGrey,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.w500)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
      ],
    );
  }

  Widget _buildInfoCard({
    required String title,
    required Widget content,
    required Color backgroundColor,
    required Color titleColor,
    bool centerTitle = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment:
        centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: titleColor,
            ),
          ),
          SizedBox(height: 12),
          content,
        ],
      ),
    );
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        // First check for active login before proceeding
        final activeLoginCheck = await _apiService.checkActiveLogin(_idController.text);
        if (activeLoginCheck["hasActiveLogin"] == true) {
          String deviceInfo = activeLoginCheck["phoneName"] ?? activeLoginCheck["deviceID"] ?? "another device";
          ScaffoldMessenger.of(context).removeCurrentSnackBar(); // Remove any existing snackbar
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('You have an active login session on $deviceInfo'),
              behavior: SnackBarBehavior.fixed, // Optional: prevents floating behavior
            ),
          );
          setState(() {
            _isLoading = false;
          });
          return;
        }

        // Show phone condition dialog before anything else
        final phoneConditionResult = await _showPhoneConditionDialogIn();
        if (phoneConditionResult == null) {
          // User cancelled the dialog
          setState(() {
            _isLoading = false;
          });
          return;
        }

        String phoneCondition = phoneConditionResult['phoneCondition'] ?? 'Good';

        // Proceed with insertIdNumber only after phone condition is provided
        final actualIdNumber = await _apiService.insertIdNumber(
          _idController.text,
          deviceId: _deviceId!,
        );

        // Proceed with WTR using phone condition
        final wtrResponse = await _apiService.insertWTR(
          actualIdNumber,
          deviceId: _deviceId!,
          phoneCondition: phoneCondition,
        );

        // Fetch profile using actual ID
        await _fetchProfile(actualIdNumber);
        setState(() {
          _isLoggedIn = true;
          _currentIdNumber = actualIdNumber;
          _idController.text = actualIdNumber;
        });

        // Show late or relogin dialog if applicable
        if (wtrResponse['isLate'] == true || wtrResponse['isRelogin'] == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                String title;
                String message;

                if (wtrResponse['isRelogin'] == true && wtrResponse['isLate'] == true) {
                  title = "Relogin (Late)";
                  message = "You have relogged in and you are late for your shift";
                } else if (wtrResponse['isRelogin'] == true) {
                  title = "Relogin";
                  message = "You have relogged in";
                } else {
                  title = "Late Login";
                  message = wtrResponse['lateMessage'] ?? "You are late for your shift";
                }

                return AlertDialog(
                  title: Text(title),
                  content: Text(message),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text("OK"),
                    ),
                  ],
                );
              },
            );
          });
        }

        String successMessage = 'Successfully logged in with ID: $actualIdNumber';
        if (wtrResponse['updated'] == true) {
          successMessage = 'Successfully updated existing WTR record with device info';
        }
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
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
    final exemptedIds = ['1243', '0939', '1163', '1239', '1288', '123s8'];
    final isExempted = exemptedIds.contains(_currentIdNumber);

    // Only show QR scanner for non exempted users
    if (!isExempted) {
      final bool? qrVerified = await _showQrScanner();
      if (qrVerified != true) {
        return;
      }
    }

    // Show phone condition dialog for logout
    final phoneConditionResult = await _showPhoneConditionDialogOut();
    if (phoneConditionResult == null) {
      // User cancelled the dialog
      return;
    }

    String phoneConditionOut = phoneConditionResult['phoneConditionOut'] ?? 'Good: Yes';

    try {
      // First check if there are any active WTR sessions
      final activeSessionsCheck = await _apiService.checkActiveWTR(_currentIdNumber!);
      // Only proceed with confirm logout if there are active sessions
      if (activeSessionsCheck["hasActiveSessions"] == true) {
        // Call the confirmLogoutWTR API to check if the user is trying to log out before shift end
        final confirmResult = await _apiService.confirmLogoutWTR(_currentIdNumber!);

        // Display different dialog based on whether it's an undertime logout or not
        bool confirm = false;

        if (confirmResult["isUndertime"] == true) {
          // Show undertime-specific dialog
          confirm = await showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text("Early Logout"),
                content: Text("Your shift ends at ${confirmResult["shiftOut"]}. Are you sure you want to logout now?"),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text("Cancel"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text("Logout Anyway"),
                  ),
                ],
              );
            },
          );
        } else {
          // For management, skip confirmation dialog
          if (!isExempted) {
            // Standard logout confirmation dialog for non-management
            confirm = await showDialog(
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
          } else {
            // Management can logout without confirmation
            confirm = true;
          }
        }

        if (confirm != true) {
          return; // User cancelled the logout
        }
      }

      setState(() {
        _isLoading = true;
      });

      try {
        // Only logout from WTR system if there are active sessions
        if (activeSessionsCheck["hasActiveSessions"] == true) {
          final logoutResult = await _apiService.logoutWTR(
            _currentIdNumber!,
            phoneConditionOut: phoneConditionOut,
          );

          // Check if this was an undertime logout
          if (logoutResult["isUndertime"] == true) {
            // Show undertime message
            ScaffoldMessenger.of(context).removeCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You have logged out before your shift ended')),
            );
          }
        }

        // Always logout from the device tracking system
        await _apiService.logout(_deviceId!);

        setState(() {
          _isLoggedIn = false;
          _firstName = null;
          _surName = null;
          _profilePictureUrl = null;
          _currentIdNumber = null;
          _idController.clear();
        });
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Logged out successfully')),
        );
      } catch (e) {
        // Error handling
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      // Error handling
    }
  }

  Future<bool?> _showQrScanner() async {
    _qrErrorMessage = null; // Reset error message
    _isFlashOn = false;     // Reset flash icon initially

    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.95,
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Center(
                      child: Text(
                        "Scan the QR code at the Guard House to log out",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.9,
                        height: MediaQuery.of(context).size.width * 0.9,
                        child: QRView(
                          key: qrKey,
                          onQRViewCreated: (controller) => _onQRViewCreated(controller, setState),
                          overlay: QrScannerOverlayShape(
                            borderColor: Colors.red,
                            borderRadius: 10,
                            borderLength: 30,
                            borderWidth: 10,
                            cutOutSize: MediaQuery.of(context).size.width * 0.7,
                          ),
                        ),
                      ),
                    ),
                    if (_qrErrorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _qrErrorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Container()), // Spacer
                        IconButton(
                          icon: Icon(
                            Icons.highlight, // or use Icons.flashlight_on if you're on Material 3
                            color: _isFlashOn ? Colors.amber : Colors.grey,
                            size: 36, // Increased size
                          ),
                          onPressed: () async {
                            if (qrController != null) {
                              await qrController?.toggleFlash();
                              setState(() {
                                _isFlashOn = !_isFlashOn;
                              });
                            }
                          },
                        ),
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                _isFlashOn = false; // Reset flash icon
                                Navigator.of(context).pop(false);
                                qrController?.dispose();
                              },
                              child: const Text("Cancel"),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((value) {
      _isFlashOn = false; // Also reset after dialog closes in any way
      return value;
    });
  }

  String xorDecrypt(String base64Data, String key) {
    final decodedBytes = base64.decode(base64Data);
    final keyBytes = utf8.encode(key);
    final decryptedBytes = List<int>.generate(decodedBytes.length, (i) {
      return decodedBytes[i] ^ keyBytes[i % keyBytes.length];
    });
    return utf8.decode(decryptedBytes);
  }

  void _onQRViewCreated(QRViewController controller, void Function(void Function()) setState) {
    qrController = controller;
    bool isVerified = false;

    controller.scannedDataStream.listen((scanData) {
      if (isVerified) return;

      final qrData = scanData.code;
      if (qrData == null) return;

      try {
        final decrypted = xorDecrypt(qrData, 'arklog123'); // same key as used in PHP

        if (decrypted == '4rkT3chBirthD@y=2003-06-09 06:31:20') {
          isVerified = true;
          qrController?.pauseCamera();
          Navigator.of(context).pop(true);
          qrController?.dispose();
        } else {
          setState(() {
            _qrErrorMessage = 'Invalid QR code data';
          });
        }
      } catch (e) {
        setState(() {
          _qrErrorMessage = 'Failed to decode QR code';
        });
      }
    });
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
    WidgetsBinding.instance.removeObserver(this);
    qrController?.dispose();
    _idController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.grey[100],
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(kToolbarHeight * 1.5), // Increased height to accommodate both headers
        child: SafeArea(
          child: Column(
            children: [
              Container(
                height: kToolbarHeight - 20,
                color: Color(0xFF3452B4),
                child: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  centerTitle: true,
                  toolbarHeight: kToolbarHeight - 20,
                  leading: IconButton(
                    padding: EdgeInsets.zero, // Removes internal padding
                    iconSize: 30, // Slightly smaller if needed
                    icon: Icon(
                      Icons.settings,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      _scaffoldKey.currentState?.openDrawer();
                    },
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.only(right: 6.0), // Slightly tighter padding
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 25,
                        icon: Container(
                          width: 25,
                          height: 25,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red,
                          ),
                          child: Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 25,
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
              Container(
                color: Color(0xFF3452B4),
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: IntrinsicHeight(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Transform.translate(
                          offset: Offset(-10, 0), // Moves content slightly to the left
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/images/philippines.png',
                                width: 36,
                                height: 36,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'ARK LOG',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
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
                                _phoneName,
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
                                onTap: () => _updateLanguage('en'),
                                child: Column(
                                  children: [
                                    Image.asset(
                                      'assets/images/americanFlag.gif',
                                      width: 40,
                                      height: 40,
                                    ),
                                    if (_currentLanguage == 'en')
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
                                onTap: () => _updateLanguage('ja'),
                                child: Column(
                                  children: [
                                    Image.asset(
                                      'assets/images/japaneseFlag.gif',
                                      width: 40,
                                      height: 40,
                                    ),
                                    if (_currentLanguage == 'ja')
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
                        SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.only(left: 29.0),
                          child: Row(
                            children: [
                              Text(
                                "Manual",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 15),
                              IconButton(
                                icon: Icon(Icons.menu_book, size: 28),
                                iconSize: 28,
                                onPressed: () async {
                                  try {
                                    // Show loading indicator
                                    setState(() {
                                      _isLoading = true;
                                    });

                                    // Get the current language from shared preferences
                                    final prefs = await SharedPreferences.getInstance();
                                    final language = prefs.getString('language') ?? 'en';

                                    // Determine language flag (1 for English, 2 for Japanese)
                                    final languageFlag = language == 'ja' ? 2 : 1;

                                    // Fetch the manual link (using linkID 10 as specified)
                                    final pdfUrl = await _apiService.fetchManualLink(10, languageFlag);

                                    // Open the PDF viewer
                                    if (!mounted) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => PDFViewerScreen(
                                          pdfUrl: pdfUrl,
                                          fileName: 'manual_${language == 'ja' ? 'jp' : 'en'}.pdf',
                                          languageFlag: languageFlag,
                                        ),
                                      ),
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Failed to open manual: ${e.toString()}')),
                                    );
                                  } finally {
                                    if (!mounted) return;
                                    setState(() {
                                      _isLoading = false;
                                    });
                                  }
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
                        Text(
                          _isLoggedIn ? 'Welcome ${_firstName ?? ""}' : 'Enter your ID number',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            overflow: TextOverflow.ellipsis,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        // SizedBox(height: 8),
                        // Text(
                        //   _currentDateTime,
                        //   style: TextStyle(
                        //     color: Colors.white,
                        //     fontSize: 16,
                        //     fontWeight: FontWeight.w500,
                        //   ),
                        // ),
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
                                if (_latestTimeIn != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Last Login: $_latestTimeIn',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
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
                                suffixIcon: _idController.text.isNotEmpty
                                    ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _idController.clear();
                                  },
                                ) : null,
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
                              onChanged: (_) {
                                // This triggers a rebuild to show/hide the clear icon
                                (context as Element).markNeedsBuild();
                              },
                              onFieldSubmitted: (value) {
                                if (!_isLoading && !_isLoggedIn && _formKey.currentState!.validate()) {
                                  _login();
                                }
                              },
                              textInputAction: TextInputAction.go,
                            ),
                          const SizedBox(height: 24),
                          if (!_isExclusiveUser) SizedBox(
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
