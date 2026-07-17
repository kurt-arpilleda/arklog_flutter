import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'api_service.dart';

class ToJapanDialog extends StatefulWidget {
  final String idNumber;
  final bool isJapanese;

  const ToJapanDialog({
    Key? key,
    required this.idNumber,
    this.isJapanese = false,
  }) : super(key: key);

  static Future<bool?> show({
    required BuildContext context,
    required String idNumber,
    bool isJapanese = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) {
        return ToJapanDialog(idNumber: idNumber, isJapanese: isJapanese);
      },
    );
  }

  @override
  State<ToJapanDialog> createState() => _ToJapanDialogState();
}

class _ToJapanDialogState extends State<ToJapanDialog> {
  final ApiService _apiService = ApiService();
  final TextEditingController _passportYearController = TextEditingController();

  int? _isInterested;
  int? _interestedType;
  int? _hasPassport;
  bool _isSubmitting = false;

  bool get _isJa => widget.isJapanese;

  @override
  void dispose() {
    _passportYearController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_isInterested == null || _hasPassport == null) return false;
    if (_isInterested == 1 && _interestedType == null) return false;
    if (_hasPassport == 1 && _passportYearController.text.trim().isEmpty) return false;
    return true;
  }

  Future<void> _submit() async {
    if (!_canSubmit || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      final result = await _apiService.submitToJapanSurvey(
        idNumber: widget.idNumber,
        isInterested: _isInterested!,
        interestedType: _isInterested == 1 ? _interestedType : null,
        hasPassport: _hasPassport!,
        passportValidity: _hasPassport == 1 ? _passportYearController.text.trim() : null,
      );

      if (result["success"] == true) {
        Fluttertoast.showToast(
          msg: _isJa ? "送信が完了しました。ありがとうございます。" : "Survey submitted, thank you!",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
        );
        if (mounted) Navigator.of(context).pop(true);
      } else {
        Fluttertoast.showToast(
          msg: result["message"] ?? (_isJa ? "送信に失敗しました" : "Failed to submit survey"),
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: _isJa ? "送信に失敗しました" : "Failed to submit survey",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width * 0.92 > 520 ? 520.0 : screenSize.width * 0.92;

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.transparent,
        child: Container(
          width: dialogWidth,
          constraints: BoxConstraints(maxHeight: screenSize.height * 0.88),
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
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
                child: Column(
                  children: [
                    const Icon(Icons.flight_takeoff, color: Colors.white, size: 32),
                    const SizedBox(height: 10),
                    Text(
                      _isJa ? "日本 短期・長期 アンケート" : "JAPAN SHORT TERM AND LONG TERM SURVEY",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _questionLabel(_isJa ? "1. 興味がありますか？" : "1. Are you interested?"),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _OptionCard(
                              label: _isJa ? "興味あり" : "Interested",
                              icon: Icons.check_circle,
                              selected: _isInterested == 1,
                              color: Colors.green,
                              onTap: () => setState(() {
                                _isInterested = 1;
                              }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _OptionCard(
                              label: _isJa ? "興味なし" : "Not Interested",
                              icon: Icons.cancel,
                              selected: _isInterested == 2,
                              color: Colors.red,
                              onTap: () => setState(() {
                                _isInterested = 2;
                                _interestedType = null;
                              }),
                            ),
                          ),
                        ],
                      ),
                      if (_isInterested == 1) ...[
                        const SizedBox(height: 20),
                        _questionLabel(_isJa ? "2. 短期、長期、それとも両方？" : "2. Short Term, Long Term, or Both?"),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _OptionCard(
                                label: _isJa ? "短期" : "Short Term",
                                icon: Icons.access_time_filled,
                                selected: _interestedType == 1,
                                color: const Color(0xFF3452B4),
                                onTap: () => setState(() => _interestedType = 1),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _OptionCard(
                                label: _isJa ? "長期" : "Long Term",
                                icon: Icons.hourglass_bottom,
                                selected: _interestedType == 2,
                                color: const Color(0xFF3452B4),
                                onTap: () => setState(() => _interestedType = 2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _OptionCard(
                                label: _isJa ? "両方" : "Both",
                                icon: Icons.all_inclusive,
                                selected: _interestedType == 3,
                                color: const Color(0xFF3452B4),
                                onTap: () => setState(() => _interestedType = 3),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                      _questionLabel(_isJa ? "3. パスポートを持っていますか？" : "3. Do you have a passport?"),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _OptionCard(
                              label: _isJa ? "はい" : "Yes",
                              icon: Icons.check_circle,
                              selected: _hasPassport == 1,
                              color: Colors.green,
                              onTap: () => setState(() {
                                _hasPassport = 1;
                              }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _OptionCard(
                              label: _isJa ? "いいえ" : "No",
                              icon: Icons.cancel,
                              selected: _hasPassport == 2,
                              color: Colors.red,
                              onTap: () => setState(() {
                                _hasPassport = 2;
                                _passportYearController.clear();
                              }),
                            ),
                          ),
                        ],
                      ),
                      if (_hasPassport == 1) ...[
                        const SizedBox(height: 20),
                        _questionLabel(
                          _isJa
                              ? "4. パスポートの有効期限はいつまでですか？（年のみで結構です）"
                              : "4. Until when is your passport's validity? (Year is okay)",
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _passportYearController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          maxLength: 4,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: _isJa ? "例：2028" : "e.g. 2028",
                            counterText: "",
                            prefixIcon: const Icon(Icons.badge_outlined),
                            filled: true,
                            fillColor: const Color(0xFFF3F4F6),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _canSubmit && !_isSubmitting ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3452B4),
                      disabledBackgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                        : const Icon(Icons.send, color: Colors.white),
                    label: Text(
                      _isJa ? "送信" : "Submit",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: Color(0xFF1E293B),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _OptionCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? color : Colors.grey.shade400, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? color : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}