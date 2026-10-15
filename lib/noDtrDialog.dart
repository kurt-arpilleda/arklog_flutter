import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'api_service.dart';

class NoDtrDialog extends StatefulWidget {
  final String idNumber;
  final bool isJapanese;
  final ApiService apiService;

  const NoDtrDialog({
    Key? key,
    required this.idNumber,
    required this.apiService,
    this.isJapanese = false,
  }) : super(key: key);

  static Future<void> show({
    required BuildContext context,
    required String idNumber,
    required ApiService apiService,
    bool isJapanese = false,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) {
        return NoDtrDialog(
          idNumber: idNumber,
          apiService: apiService,
          isJapanese: isJapanese,
        );
      },
    );
  }

  @override
  State<NoDtrDialog> createState() => _NoDtrDialogState();
}

class _NoDtrDialogState extends State<NoDtrDialog> {
  final TextEditingController _reasonController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Map<String, dynamic>> _pending = [];
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _isSaving = false;
  bool _isClosing = false;
  TimeOfDay? _timeOut;
  String? _error;
  String? _displayId;
  String? _firstName;
  String? _surName;
  String? _pictureUrl;
  bool _profileRequested = false;

  static const int _reasonMin = 5;
  static const int _reasonMax = 255;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  TimeOfDay? _parseHm(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatHm(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Map<String, dynamic>? get _current => _pending.isEmpty ? null : _pending.first;

  DateTime? get _timeIn {
    final raw = _current?['timeIn']?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw.replaceFirst(' ', 'T'));
  }

  bool get _isSameAsTimeIn {
    final tIn = _timeIn;
    if (tIn == null || _timeOut == null) return false;
    return _formatHm(_timeOut!) == _formatHm(TimeOfDay(hour: tIn.hour, minute: tIn.minute));
  }

  bool get _isNextDay {
    final tIn = _timeIn;
    if (tIn == null || _timeOut == null) return false;
    return _formatHm(_timeOut!).compareTo(_formatHm(TimeOfDay(hour: tIn.hour, minute: tIn.minute))) < 0;
  }

  String get _hintText {
    final tIn = _timeIn;
    if (tIn == null || _timeOut == null) return '';
    if (_isSameAsTimeIn) {
      return widget.isJapanese
          ? '退勤時間を出勤時間と同じにすることはできません。'
          : "Time out can't be the same as time in.";
    }
    var day = DateTime(tIn.year, tIn.month, tIn.day);
    if (_isNextDay) {
      day = day.add(const Duration(days: 1));
    }
    final dayText = DateFormat('yyyy-MM-dd').format(day);
    final base = (widget.isJapanese ? '退勤時間の確認' : 'Confirm time out') +
        ' $dayText ${_formatHm(_timeOut!)}';
    if (_isNextDay) {
      return base + ' | ' + (widget.isJapanese ? '翌日 / 夜勤' : 'Next day / Night shift');
    }
    return base;
  }

  bool get _hintWarning => _isSameAsTimeIn || _isNextDay;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final data = await widget.apiService.fetchNoDtr(widget.idNumber);
      final raw = data['pending'];
      final list = <Map<String, dynamic>>[];
      if (raw is List) {
        for (final item in raw) {
          list.add(Map<String, dynamic>.from(item as Map));
        }
      }
      if (list.isEmpty) {
        _close();
        return;
      }
      if (!mounted) return;
      final preTimeOut = list.first['timeOut']?.toString() ?? '';
      final resolvedId = data['idNumber']?.toString() ?? widget.idNumber;
      setState(() {
        _pending = list;
        _displayId = resolvedId;
        _timeOut = preTimeOut.isNotEmpty ? _parseHm(preTimeOut) : null;
        _reasonController.clear();
        _error = null;
        _isLoading = false;
      });
      _loadProfile(resolvedId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _loadProfile(String id) async {
    if (_profileRequested) return;
    _profileRequested = true;
    try {
      final profile = await widget.apiService.fetchProfile(id);
      if (profile["success"] != true || !mounted) return;
      final fileName = profile["picture"]?.toString() ?? '';
      String? foundUrl;
      if (fileName.isNotEmpty) {
        final urls = await widget.apiService.getCurrentApiUrls();
        for (final base in urls) {
          final url = "${base}V4/11-A%20Employee%20List%20V2/profilepictures/$fileName";
          try {
            final response = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 3));
            if (response.statusCode == 200) {
              foundUrl = url;
              break;
            }
          } catch (e) {}
        }
      }
      if (!mounted) return;
      setState(() {
        _firstName = profile["firstName"]?.toString();
        _surName = profile["surName"]?.toString();
        _pictureUrl = foundUrl;
      });
    } catch (e) {
      _profileRequested = false;
    }
  }

  void _close() {
    if (_isClosing || !mounted) return;
    _isClosing = true;
    Navigator.of(context).pop();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOut ?? const TimeOfDay(hour: 17, minute: 0),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _timeOut = picked;
        _error = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_isSaving || _current == null) return;

    if (_timeOut == null) {
      setState(() {
        _error = widget.isJapanese ? '退勤時間を入力してください。' : 'Enter your time out.';
      });
      return;
    }

    if (_isSameAsTimeIn) {
      setState(() {
        _error = widget.isJapanese
            ? '退勤時間を出勤時間と同じにすることはできません。'
            : "Time out can't be the same as time in.";
      });
      return;
    }

    final reason = _reasonController.text.trim();
    if (reason.length < _reasonMin) {
      setState(() {
        _error = widget.isJapanese
            ? '理由を$_reasonMin文字以上で入力してください。'
            : 'Enter the reason (at least $_reasonMin characters).';
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      final result = await widget.apiService.saveNoDtr(
        idNumber: widget.idNumber,
        dtrId: _current!['dtrId'] as int,
        timeOut: _formatHm(_timeOut!),
        reason: reason,
      );
      final status = result['status']?.toString();
      if (status == 'success' || status == 'stale') {
        if (!mounted) return;
        setState(() {
          _isSaving = false;
        });
        await _load();
        return;
      }
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        final message = result['message']?.toString() ?? '';
        _error = message.isNotEmpty
            ? message
            : (widget.isJapanese
            ? '退勤時間を保存できませんでした。もう一度お試しください。'
            : 'Could not save your time out. Try again.');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = widget.isJapanese
            ? 'サーバーに接続できません。接続を確認してもう一度お試しください。'
            : 'Could not reach the server. Check your connection and try again.';
      });
    }
  }

  String _fullDate(DateTime d) {
    if (widget.isJapanese) {
      const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
      return '${d.year}年${d.month}月${d.day}日（${weekdays[d.weekday - 1]}）';
    }
    return DateFormat('EEEE, MMMM d, y').format(d);
  }

  String _monthShort(DateTime d) {
    if (widget.isJapanese) return '${d.month}月';
    return DateFormat('MMM').format(d);
  }

  Widget _tagalog(String text, {double fontSize = 11, double top = 2}) {
    if (widget.isJapanese) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          color: Colors.grey.shade600,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF3452B4), Color(0xFF2053B3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.history_toggle_off, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.isJapanese ? '退勤打刻がありません' : 'Missing Time Out',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeCard() {
    final fullName = '${_firstName ?? ''} ${_surName ?? ''}'.trim();
    final id = _displayId ?? widget.idNumber;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFD3F5)),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.blue[50],
              border: Border.all(color: const Color(0xFF3452B4), width: 2),
            ),
            child: _pictureUrl != null
                ? ClipOval(
              child: Image.network(
                _pictureUrl!,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.person,
                  size: 32,
                  color: Color(0xFF3452B4),
                ),
              ),
            )
                : const Icon(Icons.person, size: 32, color: Color(0xFF3452B4)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName.isNotEmpty
                      ? fullName
                      : (widget.isJapanese ? '読み込み中...' : 'Loading...'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B1F24),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'ID: $id',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: CircularProgressIndicator(color: Color(0xFF3452B4)),
      ),
    );
  }

  Widget _buildLoadFailed() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 14),
          Text(
            widget.isJapanese
                ? 'サーバーに接続できません。'
                : 'Could not reach the server.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(widget.isJapanese ? '再試行' : 'Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3452B4),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    final tIn = _timeIn;
    final hasPreTimeOut = (_current?['timeOut']?.toString() ?? '').isNotEmpty;
    final remaining = _pending.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildEmployeeCard(),
          const SizedBox(height: 16),
          if (remaining > 1)
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4D6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF915F00),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.isJapanese
                            ? '残り$remaining件'
                            : '$remaining records left  •  May $remaining na natitirang record',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF915F00),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Text(
            hasPreTimeOut
                ? (widget.isJapanese
                ? 'この日の退勤打刻がない理由を入力してください。'
                : 'Please enter the reason why there is no time out for this day.')
                : (widget.isJapanese
                ? '以下の日の退勤打刻が記録されていません。実際に退勤した時間を入力してください。'
                : 'No time out was recorded for the day below. Enter the time you actually left.'),
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          _tagalog(
            hasPreTimeOut
                ? 'Pakilagay ang dahilan kung bakit walang time-out para sa araw na ito.'
                : 'Walang time-out record para sa araw sa ibaba. Ilagay ang eksaktong oras ng iyong pag-alis.',
            top: 6,
          ),
          const SizedBox(height: 16),
          if (tIn != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F7F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4E7EC)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE4E7EC)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          color: const Color(0xFF3452B4),
                          child: Text(
                            _monthShort(tIn),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Text(
                            tIn.day.toString(),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _fullDate(tIn),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text.rich(
                          TextSpan(
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                            children: [
                              TextSpan(text: widget.isJapanese ? '出勤: ' : 'Time in: '),
                              TextSpan(
                                text: DateFormat('h:mm a').format(tIn),
                                style: const TextStyle(
                                  color: Color(0xFF1B1F24),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Text(
            widget.isJapanese ? '退勤時間' : 'Time out',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _isSaving ? null : _pickTime,
            child: Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _timeOut == null ? const Color(0xFFD0D5DD) : const Color(0xFF3452B4),
                  width: _timeOut == null ? 1 : 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _timeOut == null ? '--:--' : _formatHm(_timeOut!),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        color: _timeOut == null ? Colors.grey.shade400 : const Color(0xFF1B1F24),
                      ),
                    ),
                  ),
                  const Icon(Icons.access_time, color: Color(0xFF3452B4)),
                ],
              ),
            ),
          ),
          if (_hintText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _hintText,
                style: TextStyle(
                  fontSize: 13,
                  color: _hintWarning ? const Color(0xFF915F00) : Colors.grey.shade600,
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            widget.isJapanese ? '退勤打刻がない理由' : 'Reason for no time out',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          _tagalog('Dahilan kung bakit walang time-out'),
          const SizedBox(height: 8),
          TextField(
            controller: _reasonController,
            enabled: !_isSaving,
            minLines: 3,
            maxLines: 4,
            maxLength: _reasonMax,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
            onTap: () {
              Future.delayed(const Duration(milliseconds: 300), () {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    _scrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              });
            },
            decoration: InputDecoration(
              hintText: widget.isJapanese
                  ? '例：退勤の打刻を忘れました'
                  : 'Example: I forgot to time out',
              filled: true,
              fillColor: Colors.grey.shade50,
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF3452B4), width: 1.5),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFB3261E), fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3452B4),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFF3452B4).withOpacity(0.6),
                disabledForegroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
                  : Text(
                widget.isJapanese ? '送信' : 'SUBMIT',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
              border: const Border(
                left: BorderSide(color: Color(0xFF3452B4), width: 3),
              ),
            ),
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
                children: [
                  TextSpan(
                    text: widget.isJapanese ? '注意: ' : 'Note: ',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1B1F24)),
                  ),
                  TextSpan(
                    text: widget.isJapanese
                        ? '時間の修正は当日の午前8:00から正午12:00までです。'
                        : 'Time correction period will be 8:00 AM to 12:00 NN of the day only.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final availableHeight = screenSize.height - viewInsets.bottom;
    final dialogWidth = screenSize.width * 0.94 > 480 ? 480.0 : screenSize.width * 0.94;

    return PopScope(
      canPop: false,
      child: GestureDetector(
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.transparent,
          child: Container(
            width: dialogWidth,
            constraints: BoxConstraints(maxHeight: availableHeight * 0.92),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.25),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                Flexible(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const ClampingScrollPhysics(),
                    child: _isLoading
                        ? _buildLoading()
                        : _loadFailed
                        ? _buildLoadFailed()
                        : _buildForm(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}