import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class InstructionDialog extends StatefulWidget {
  final String imageFolderUrl;
  final Future<bool> Function() onPoll;
  final bool isJapanese;
  final String waitingTitle;
  final String waitingTitleJa;
  final Duration pollInterval;
  final Duration slideInterval;
  final int maxImages;
  final String imageExtension;

  const InstructionDialog({
    Key? key,
    required this.imageFolderUrl,
    required this.onPoll,
    this.isJapanese = false,
    this.waitingTitle = 'Please wait',
    this.waitingTitleJa = 'お待ちください',
    this.pollInterval = const Duration(seconds: 1),
    this.slideInterval = const Duration(seconds: 4),
    this.maxImages = 30,
    this.imageExtension = 'jpeg',
  }) : super(key: key);

  static Future<bool?> show({
    required BuildContext context,
    required String imageFolderUrl,
    required Future<bool> Function() onPoll,
    bool isJapanese = false,
    String waitingTitle = 'Please wait',
    String waitingTitleJa = 'お待ちください',
    Duration pollInterval = const Duration(seconds: 1),
    Duration slideInterval = const Duration(seconds: 4),
    int maxImages = 30,
    String imageExtension = 'jpeg',
  }) {
    FocusManager.instance.primaryFocus?.unfocus();
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return InstructionDialog(
          imageFolderUrl: imageFolderUrl,
          onPoll: onPoll,
          isJapanese: isJapanese,
          waitingTitle: waitingTitle,
          waitingTitleJa: waitingTitleJa,
          pollInterval: pollInterval,
          slideInterval: slideInterval,
          maxImages: maxImages,
          imageExtension: imageExtension,
        );
      },
    );
  }

  @override
  State<InstructionDialog> createState() => _InstructionDialogState();
}

class _InstructionDialogState extends State<InstructionDialog> {
  List<String> _imageUrls = [];
  bool _isLoadingImages = true;
  int _currentIndex = 0;
  Timer? _pollTimer;
  Timer? _slideTimer;
  late http.Client _client;
  bool _isClosing = false;
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    _client = _createHttpClient();
    _discoverImages();
    _startPolling();
  }

  http.Client _createHttpClient() {
    final HttpClient client = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return IOClient(client);
  }

  Future<void> _discoverImages() async {
    final List<String> foundUrls = [];
    for (int i = 1; i <= widget.maxImages; i++) {
      final url = '${widget.imageFolderUrl}$i.${widget.imageExtension}';
      try {
        final response = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          foundUrls.add(url);
        } else {
          break;
        }
      } catch (e) {
        break;
      }
    }

    if (mounted) {
      setState(() {
        _imageUrls = foundUrls;
        _isLoadingImages = false;
      });
      if (_imageUrls.length > 1) {
        _startSlideshow();
      }
    }
  }

  void _startSlideshow() {
    _slideTimer = Timer.periodic(widget.slideInterval, (_) {
      if (!mounted || _imageUrls.isEmpty) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _imageUrls.length;
      });
    });
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(widget.pollInterval, (_) async {
      if (_isClosing || _isPolling) return;
      _isPolling = true;
      try {
        final done = await widget.onPoll();
        if (done && mounted && !_isClosing) {
          _isClosing = true;
          _pollTimer?.cancel();
          Navigator.of(context).pop(true);
        }
      } catch (e) {
      } finally {
        _isPolling = false;
      }
    });
  }

  void _goToIndex(int index) {
    if (_imageUrls.isEmpty) return;
    setState(() {
      _currentIndex = index;
    });
    _slideTimer?.cancel();
    _startSlideshow();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _slideTimer?.cancel();
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final availableHeight = screenSize.height - viewInsets.bottom;
    final dialogWidth = screenSize.width * 0.94 > 620 ? 620.0 : screenSize.width * 0.94;
    final imageHeight = availableHeight * 0.5 > 560 ? 560.0 : availableHeight * 0.5;

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
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
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
                        Text(
                          widget.isJapanese ? widget.waitingTitleJa : widget.waitingTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Container(
                            width: double.infinity,
                            height: imageHeight,
                            color: const Color(0xFFF3F4F6),
                            child: _isLoadingImages
                                ? const Center(child: CircularProgressIndicator())
                                : _imageUrls.isEmpty
                                ? Center(
                              child: Icon(Icons.image_not_supported, size: 64, color: Colors.grey.shade400),
                            )
                                : Stack(
                              children: [
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 400),
                                  child: Image.network(
                                    _imageUrls[_currentIndex],
                                    key: ValueKey(_imageUrls[_currentIndex]),
                                    width: double.infinity,
                                    height: imageHeight,
                                    fit: BoxFit.contain,
                                    loadingBuilder: (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return const Center(child: CircularProgressIndicator());
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return Center(
                                        child: Icon(Icons.broken_image, size: 64, color: Colors.grey.shade400),
                                      );
                                    },
                                  ),
                                ),
                                if (_imageUrls.length > 1) ...[
                                  Positioned(
                                    left: 8,
                                    top: 0,
                                    bottom: 0,
                                    child: Center(
                                      child: _NavButton(
                                        icon: Icons.chevron_left,
                                        onTap: () => _goToIndex((_currentIndex - 1 + _imageUrls.length) % _imageUrls.length),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 8,
                                    top: 0,
                                    bottom: 0,
                                    child: Center(
                                      child: _NavButton(
                                        icon: Icons.chevron_right,
                                        onTap: () => _goToIndex((_currentIndex + 1) % _imageUrls.length),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (_imageUrls.length > 1) ...[
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(_imageUrls.length, (index) {
                              return GestureDetector(
                                onTap: () => _goToIndex(index),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  width: index == _currentIndex ? 28 : 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    color: index == _currentIndex ? const Color(0xFF2563EB) : Colors.grey.shade300,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF2563EB)),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              widget.isJapanese ? '処理中です。お待ちください...' : 'Processing, please wait...',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF1E40AF),
                                fontWeight: FontWeight.w600,
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

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}