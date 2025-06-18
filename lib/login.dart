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
import 'birthday_celebration.dart';

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
  bool _isQrScannerOpen = false;
  String _phoneName = 'ARK LOG PH';
  static const List<String> exemptedIds = ['1238', '0939', '1288', '1239', '1200', '0280', '0001'];
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
      if (_isQrScannerOpen && Navigator.canPop(context)) {
        Navigator.of(context).pop(false); // Close the QR scanner dialog
      }
      _initializeApp();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (_isQrScannerOpen && Navigator.canPop(context)) {
        Navigator.of(context).pop(false); // Close the QR scanner dialog
      }
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
    if (_currentIdNumber != null) {
      try {
        int languageFlag = language == 'ja' ? 2 : 1;
        await _apiService.updateLanguageFlag(_currentIdNumber!, languageFlag);
      } catch (e) {
        print("Error updating language flag: $e");
      }
    }

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
        msg: _currentLanguage == 'ja'
            ? '国設定の更新エラー: ${e.toString()}'
            : 'Error updating country: ${e.toString()}',
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red.shade700,
        textColor: Colors.white,
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

        int languageFlag = profileData["languageFlag"] ?? 1; // Default to 1 if not set
        String language = languageFlag == 2 ? "ja" : "en";
        await _updateLanguage(language);

        setState(() {
          _firstName = profileData["firstName"];
          _surName = profileData["surName"];
          _profilePictureUrl = isPrimaryUrlValid ? primaryUrl : isFallbackUrlValid ? fallbackUrl : null;
          _currentIdNumber = idNumber;
          _latestTimeIn = latestTimeIn;
        });
        if (profileData["birthdate"] != null) {
          final birthdate = DateTime.parse(profileData["birthdate"]);
          final today = DateTime.now();
          if (birthdate.month == today.month && birthdate.day == today.day) {
            // Close any existing birthday celebration
            if (Navigator.of(context).canPop()) {
              BirthdayCelebration.close(context);
            }

            // Show new birthday celebration
            WidgetsBinding.instance.addPostFrameCallback((_) {
              showDialog(
                context: context,
                barrierColor: Colors.black.withOpacity(0.5),
                barrierDismissible: false,
                builder: (context) {
                  return BirthdayCelebration(
                    name: profileData["firstName"],
                    languageFlag: profileData["languageFlag"] ?? 1,
                    onFinish: () {
                      Navigator.of(context).pop();
                    },
                    duration: const Duration(seconds: 5),
                  );
                },
              );
            });
          }
        }
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
                              _currentLanguage == 'ja' ? '端末状態チェック' : 'Phone Condition Check',
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
                                  _currentLanguage == 'ja'
                                      ? '使用前に携帯電話に問題や損傷がないことを確認してください。正直に入力してください。全ての記録はシステムに保存され、既存の問題について責任を問われる可能性があります。'
                                      : 'Are you sure the phone has no issues or damage before using it? Please be honest — every entry is recorded in the system, and you don\'t want to be held responsible for any existing problems.',
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
                                label: Text(
                                    _currentLanguage == 'ja' ? 'はい' : 'Yes',
                                    style: TextStyle(fontWeight: FontWeight.w500)
                                ),
                                selected: phoneCondition == 'Yes',
                                selectedColor: Colors.green.shade100,
                                onSelected: (_) {
                                  setState(() => phoneCondition = 'Yes');
                                },
                              ),
                              ChoiceChip(
                                label: Text(
                                    _currentLanguage == 'ja' ? 'いいえ' : 'No',
                                    style: TextStyle(fontWeight: FontWeight.w500)
                                ),
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
                              labelText: _currentLanguage == 'ja'
                                  ? '問題の説明を入力してください'
                                  : 'Please explain the issue',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade50,
                            ),
                            maxLines: 3,
                            validator: (value) {
                              if (phoneCondition == 'No' && (value == null || value.trim().isEmpty)) {
                                return _currentLanguage == 'ja'
                                    ? '理由を入力してください'
                                    : 'Please provide an explanation';
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
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                  ),
                  child: Text(
                    _currentLanguage == 'ja' ? 'キャンセル' : 'Cancel',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 16,
                    ),
                  ),
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
                  child: Text(
                    _currentLanguage == 'ja' ? '確認' : 'Confirm',
                  ),
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
    final isExempted = exemptedIds.contains(_currentIdNumber);

    Map<String, dynamic> workTimeInfo = {};
    Map<String, dynamic> outputToday = {'outputQty': 0, 'stTime': '00:00:00', 'ngQty': 0, 'ngCount': 0};

    try {
      if (_currentIdNumber != null) {
        setState(() => _isLoading = true);
        workTimeInfo = await _apiService.getWorkTimeInfo(_currentIdNumber!);
        outputToday = await _apiService.getTodayOutput(_currentIdNumber!);
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
              contentPadding: EdgeInsets.all(16),
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
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (_profilePictureUrl != null)
                                    CircleAvatar(
                                      radius: 30,
                                      backgroundImage: NetworkImage(_profilePictureUrl!),
                                      backgroundColor: Colors.grey[300],
                                    ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (_firstName != null && _surName != null)
                                          Text(
                                            '$_firstName $_surName',
                                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                          ),
                                        SizedBox(height: 2),
                                        Text(
                                          currentDate,
                                          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 16),

                              _buildInfoCard(
                                title: _currentLanguage == 'ja' ? '本日の実績' : 'Today\'s Output',
                                content: Column(
                                  children: [
                                    _buildInfoRow(
                                      _currentLanguage == 'ja' ? '生産数量' : 'Output QTY',
                                      outputToday['outputQty'].toString(),
                                    ),
                                    SizedBox(height: 4),
                                    _buildInfoRow(
                                      _currentLanguage == 'ja' ? '標準時間' : 'Total ST',
                                      outputToday['stTime'],
                                    ),
                                    SizedBox(height: 4),
                                    _buildInfoRow(
                                      _currentLanguage == 'ja' ? '不良数量' : 'NG QTY',
                                      outputToday['ngQty'].toString(),
                                    ),
                                    SizedBox(height: 4),
                                    _buildInfoRow(
                                      _currentLanguage == 'ja' ? '不良件数' : 'NG Count',
                                      outputToday['ngCount'].toString(),
                                    ),
                                  ],
                                ),
                                backgroundColor: Colors.blue.shade50,
                                titleColor: Colors.blue.shade800,
                                centerTitle: true,
                              ),
                              SizedBox(height: 8),

                              if (workTimeInfo.isNotEmpty)
                                _buildInfoCard(
                                  title: _currentLanguage == 'ja' ? '勤務時間情報' : 'Work Time Info',
                                  content: Column(
                                    children: [
                                      _buildInfoRow(
                                        _currentLanguage == 'ja' ? '必要労働時間' : 'Work Required',
                                        '${workTimeInfo['workRequired']} h',
                                      ),
                                      SizedBox(height: 4),
                                      _buildInfoRow(
                                        _currentLanguage == 'ja' ? '実労働時間' : 'Worked Hours',
                                        '${workTimeInfo['workedHours']} h',
                                      ),
                                      SizedBox(height: 4),
                                      _buildInfoRow(
                                        _currentLanguage == 'ja' ? '残業時間' : 'Over-Time',
                                        '${workTimeInfo['overTime']} h',
                                      ),
                                      SizedBox(height: 4),
                                      _buildInfoRow(
                                        _currentLanguage == 'ja' ? '遅刻回数' : 'Late Count',
                                        workTimeInfo['lateCount'].toString(),
                                      ),
                                    ],
                                  ),
                                  backgroundColor: Colors.grey.shade100,
                                  titleColor: Colors.grey.shade800,
                                  centerTitle: true,
                                ),
                              SizedBox(height: 12),
                            ],
                          ),
                        Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _currentLanguage == 'ja'
                                      ? '守衛に預ける前に、電話に問題や損傷がないか確認しますか？'
                                      : 'Do you confirm the phone has no issues or damage before charging it to the guardhouse?',
                                  style: TextStyle(
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                        SizedBox(height: 16),

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
                            spacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              ChoiceChip(
                                label: Text(
                                    _currentLanguage == 'ja' ? 'はい' : 'Yes',
                                    style: TextStyle(fontSize: 13)
                                ),
                                selected: phoneCondition == 'Yes',
                                selectedColor: Colors.green.shade100,
                                onSelected: (_) {
                                  setState(() => phoneCondition = 'Yes');
                                },
                              ),
                              ChoiceChip(
                                label: Text(
                                    _currentLanguage == 'ja' ? 'いいえ' : 'No',
                                    style: TextStyle(fontSize: 13)
                                ),
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
                          SizedBox(height: 16),
                          TextFormField(
                            controller: _explanationController,
                            focusNode: _explanationFocusNode,
                            decoration: InputDecoration(
                              labelText: _currentLanguage == 'ja'
                                  ? '問題の内容を説明してください'
                                  : 'Please explain the issue',
                              labelStyle: TextStyle(fontSize: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              contentPadding: EdgeInsets.all(12),
                            ),
                            style: TextStyle(fontSize: 13),
                            maxLines: 3,
                            validator: (value) {
                              if (phoneCondition == 'No' && (value == null || value.trim().isEmpty)) {
                                return _currentLanguage == 'ja'
                                    ? '理由を入力してください'
                                    : 'Please provide an explanation';
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
                  child: Text(
                    _currentLanguage == 'ja' ? '閉じる' : 'Close',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                      _shakeController.forward(from: 0); // Trigger the shake animation
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
                  child: Text(
                    isExempted
                        ? (_currentLanguage == 'ja' ? '確認' : 'Confirm')
                        : (_currentLanguage == 'ja' ? 'スキャン' : 'Scan'),
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 13)),
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
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment:
        centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: titleColor,
            ),
          ),
          SizedBox(height: 8),
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
              content: Text(
                  _currentLanguage == 'ja'
                      ? '$deviceInfo でアクティブなログインセッションがあります'
                      : 'You have an active login session on $deviceInfo'
              ),
              behavior: SnackBarBehavior.fixed,
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
        final profileData = await _apiService.fetchProfile(actualIdNumber);

        if (profileData["success"] == true) {
          String profilePictureFileName = profileData["picture"];

          String primaryUrl = "${ApiService.apiUrls[0]}V4/11-A%20Employee%20List%20V2/profilepictures/$profilePictureFileName";
          bool isPrimaryUrlValid = await _isImageAvailable(primaryUrl);

          String fallbackUrl = "${ApiService.apiUrls[1]}V4/11-A%20Employee%20List%20V2/profilepictures/$profilePictureFileName";
          bool isFallbackUrlValid = await _isImageAvailable(fallbackUrl);

          // Fetch timeIn records
          final timeInData = await _apiService.fetchTimeIns(actualIdNumber);
          String? latestTimeIn = timeInData["latestTimeIn"] != null
              ? _formatTimeIn(timeInData["latestTimeIn"])
              : null;

          int languageFlag = profileData["languageFlag"] ?? 1; // Default to 1 if not set
          String language = languageFlag == 2 ? "ja" : "en";
          await _updateLanguage(language);

          setState(() {
            _firstName = profileData["firstName"];
            _surName = profileData["surName"];
            _profilePictureUrl = isPrimaryUrlValid ? primaryUrl : isFallbackUrlValid ? fallbackUrl : null;
            _currentIdNumber = actualIdNumber;
            _latestTimeIn = latestTimeIn;
            _isLoggedIn = true;
            _idController.text = actualIdNumber;
          });
          if (profileData["birthdate"] != null) {
            final birthdate = DateTime.parse(profileData["birthdate"]);
            final today = DateTime.now();
            if (birthdate.month == today.month && birthdate.day == today.day) {
              // Close any existing birthday celebration
              if (Navigator.of(context).canPop()) {
                BirthdayCelebration.close(context);
              }

              // Show new birthday celebration
              WidgetsBinding.instance.addPostFrameCallback((_) {
                showDialog(
                  context: context,
                  barrierColor: Colors.black.withOpacity(0.5),
                  barrierDismissible: false,
                  builder: (context) {
                    return BirthdayCelebration(
                      name: profileData["firstName"],
                      languageFlag: profileData["languageFlag"] ?? 1,
                      onFinish: () {
                        Navigator.of(context).pop();
                      },
                      duration: const Duration(seconds: 9),
                    );
                  },
                );
              });
            }
          }
        }

        // Show late or relogin dialog if applicable
        if (wtrResponse['isLate'] == true || wtrResponse['isRelogin'] == true) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            showDialog(
              context: context,
              builder: (BuildContext context) {
                String title;
                String message;

                if (wtrResponse['isRelogin'] == true && wtrResponse['isLate'] == true) {
                  title = _currentLanguage == 'ja' ? "再ログイン (遅刻)" : "Relogin (Late)";
                  message = _currentLanguage == 'ja'
                      ? "再ログインされました。シフトに遅刻しています"
                      : "You have relogged in and you are late for your shift";
                } else if (wtrResponse['isRelogin'] == true) {
                  title = _currentLanguage == 'ja' ? "再ログイン" : "Relogin";
                  message = _currentLanguage == 'ja'
                      ? "再ログインされました"
                      : "You have relogged in";
                } else {
                  title = _currentLanguage == 'ja' ? "遅刻ログイン" : "Late Login";
                  message = wtrResponse['lateMessage'] ??
                      (_currentLanguage == 'ja'
                          ? "シフトに遅刻しています"
                          : "You are late for your shift");
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

        String successMessage = _currentLanguage == 'ja'
            ? 'ID: $actualIdNumber でログインしました'
            : 'Successfully logged in with ID: $actualIdNumber';
        if (wtrResponse['updated'] == true) {
          successMessage = _currentLanguage == 'ja'
              ? 'デバイス情報で既存のWTRレコードを更新しました'
              : 'Successfully updated existing WTR record with device info';
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
    final isExempted = exemptedIds.contains(_currentIdNumber);

    final phoneConditionResult = await _showPhoneConditionDialogOut();
    if (phoneConditionResult == null) {
      return;
    }

    String phoneConditionOut = phoneConditionResult['phoneConditionOut'] ?? 'Good: Yes';

    // Only show QR scanner for non exempted users
    if (!isExempted) {
      final bool? qrVerified = await _showQrScanner();
      if (qrVerified != true) {
        return;
      }
    }

    try {
      setState(() {
        _isLoading = true;
      });
      try {
        if (_currentIdNumber != null) {
          await _apiService.insertDailyPerformance(_currentIdNumber!);
          print("Daily performance data inserted successfully");
        }
      } catch (e) {
        print("Error inserting daily performance: $e");
      }

      final activeSessionsCheck = await _apiService.checkActiveWTR(_currentIdNumber!);

      if (activeSessionsCheck["hasActiveSessions"] == true) {
        final confirmResult = await _apiService.confirmLogoutWTR(_currentIdNumber!);
        bool confirm = false;

        if (confirmResult["isUndertime"] == true) {
          confirm = await showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text(
                  _currentLanguage == 'ja' ? '早退の確認' : 'Early Logout',
                ),
                content: Text(
                  _currentLanguage == 'ja'
                      ? 'シフト終了時間は${confirmResult["shiftOut"]}です。本当にログアウトしますか？'
                      : 'Your shift ends at ${confirmResult["shiftOut"]}. Are you sure you want to logout now?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      _currentLanguage == 'ja' ? 'キャンセル' : 'Cancel',
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(
                      _currentLanguage == 'ja' ? 'ログアウトする' : 'Logout Anyway',
                    ),
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
                  title: Text(
                    _currentLanguage == 'ja' ? 'ログアウトの確認' : 'Confirm Logout',
                  ),
                  content: Text(
                    _currentLanguage == 'ja' ? 'ログアウトしますか？' : 'Are you sure you want to logout?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(
                        _currentLanguage == 'ja' ? 'キャンセル' : 'Cancel',
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(
                        _currentLanguage == 'ja' ? 'ログアウト' : 'Logout',
                      ),
                    ),
                  ],
                );
              },
            );
          } else {
            confirm = true;
          }
        }

        if (confirm != true) {
          setState(() {
            _isLoading = false;
          });
          return; // User cancelled the logout
        }
      }

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
              SnackBar(
                content: Text(
                    _currentLanguage == 'ja'
                        ? 'シフト終了前にログアウトしました'
                        : 'You have logged out before your shift ended'
                ),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.fixed,
              ),
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
          SnackBar(
            content: Text(
                _currentLanguage == 'ja'
                    ? 'ログアウトに成功しました'
                    : 'Logged out successfully'
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.fixed,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                _currentLanguage == 'ja'
                    ? 'ログアウトエラー'
                    : 'Logout error'
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.fixed,
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              _currentLanguage == 'ja'
                  ? 'エラーが発生しました'
                  : 'An error occurred'
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.fixed,
        ),
      );
    }
  }

  Future<bool?> _showQrScanner() async {
    _qrErrorMessage = null;
    _isFlashOn = false;
    _isQrScannerOpen = true;

    return await showDialog<bool>(
      context: context,
      barrierDismissible: false, // This prevents closing when tapping outside
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              insetPadding: const EdgeInsets.all(8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenWidth = MediaQuery.of(context).size.width;
                  final screenHeight = MediaQuery.of(context).size.height;
                  final isLandscape = screenWidth > screenHeight;
                  final maxScannerSize = isLandscape
                      ? screenHeight - 120
                      : screenWidth * 0.92;
                  final cutOutSize = maxScannerSize * 0.9;

                  return SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            children: [
                              Text(
                                _currentLanguage == 'ja'
                                    ? 'ログアウト時は守衛所でQRコードをスキャンしてください'
                                    : 'Scan the QR code at the Guard House to log out',
                                style: TextStyle(
                                  fontSize: _currentLanguage == 'ja' ? 16 : 18,
                                  fontWeight: FontWeight.bold,
                                  height: 1.4,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: maxScannerSize,
                                maxHeight: maxScannerSize,
                              ),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: QRView(
                                  key: qrKey,
                                  onQRViewCreated: (controller) =>
                                      _onQRViewCreated(controller, setState),
                                  overlay: QrScannerOverlayShape(
                                    borderColor: Colors.red,
                                    borderRadius: 10,
                                    borderLength: 40,
                                    borderWidth: 8,
                                    cutOutSize: cutOutSize,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _currentLanguage == 'ja'
                                ? '⚠️ ログアウトにはAPI-Guard-HigherBand Wi-Fiへの接続が必要です。ログアウト後は守衛に電話を充電してください。'
                                : '⚠️ Connect to API-Guard-HigherBand Wi-Fi to log out. Please charge the phone to the guardhouse after logging out.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
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
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(child: SizedBox()),
                              IconButton(
                                icon: Icon(
                                  Icons.highlight,
                                  color: _isFlashOn ? Colors.amber : Colors.grey,
                                  size: 36,
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
                                      _isFlashOn = false;
                                      Navigator.of(context).pop(false);
                                      qrController?.dispose();
                                    },
                                    child: Text(
                                      _currentLanguage == 'ja'
                                          ? 'キャンセル'
                                          : 'Cancel',
                                    ),
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
              ),
            );
          },
        );
      },
    ).then((value) {
      _isFlashOn = false;
      _isQrScannerOpen = false;
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
            _qrErrorMessage = _currentLanguage == 'ja'
                ? '無効なQRコードデータです'
                : 'Invalid QR code data';
          });
        }
      } catch (e) {
        setState(() {
          _qrErrorMessage = _currentLanguage == 'ja'
              ? 'QRコードのデコードに失敗しました'
              : 'Failed to decode QR code';
        });
      }
    });
  }

  Future<String> _getDeviceId() async {
    try {
      String? identifier = await UniqueIdentifier.serial;
      return identifier ?? 'unknown-device';
    }catch (e) {
      print('Error getting device identifier: $e');
      return _currentLanguage == 'ja'
          ? 'デバイスIDの取得中にエラーが発生しました'
          : 'error-getting-device-id';
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
                                _currentLanguage == 'ja' ? 'アークログ' : 'ARK LOG',
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
                          padding: EdgeInsets.symmetric(
                            horizontal: _currentLanguage == 'ja' ? 35.0 : 16.0,
                          ),
                          child: Row(
                            children: [
                              Text(
                                _currentLanguage == 'ja' ? '言語' : 'Language',
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
                                _currentLanguage == 'ja' ? 'キーボード' : 'Keyboard',
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
                          padding: EdgeInsets.only(
                            left: _currentLanguage == 'ja' ? 46.0 : 30.0,
                          ),
                          child: Row(
                            children: [
                              Text(
                                _currentLanguage == 'ja' ? '手引き' : 'Manual',
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
                                      SnackBar(
                                        content: Text(
                                            _currentLanguage == 'ja'
                                                ? 'マニュアルのオープンに失敗しました: ${e.toString()}'
                                                : 'Failed to open manual: ${e.toString()}'
                                        ),
                                      ),
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
                        _currentLanguage == 'ja' ? '国' : 'Country',
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
                          _isLoggedIn
                              ? (_currentLanguage == 'ja'
                              ? 'ようこそ ${_firstName ?? ""}さん'
                              : 'Welcome ${_firstName ?? ""}')
                              : (_currentLanguage == 'ja'
                              ? 'ID番号を入力してください'
                              : 'Enter your ID number'),
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
                                    _currentLanguage == 'ja'
                                        ? '最終ログイン: $_latestTimeIn'
                                        : 'Last Login: $_latestTimeIn',
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
                                labelText: _currentLanguage == 'ja' ? 'ID番号' : 'ID Number',
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
                                  return _currentLanguage == 'ja'
                                      ? 'ID番号を入力してください'
                                      : 'Please enter your ID number';
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
                                _isLoggedIn
                                    ? (_currentLanguage == 'ja' ? 'ログアウト' : 'LOGOUT')
                                    : (_currentLanguage == 'ja' ? 'ログイン' : 'LOGIN'),
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
