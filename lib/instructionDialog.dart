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
        // Ignore errors from a single poll attempt, next tick will retry
      } finally {
        _isPolling = false;
      }
    });
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
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogSize = screenWidth * 0.92 > 480 ? 480.0 : screenWidth * 0.92;

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.all(8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: dialogSize,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.isJapanese ? widget.waitingTitleJa : widget.waitingTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: dialogSize - 32,
                  height: dialogSize - 32,
                  child: _isLoadingImages
                      ? const Center(child: CircularProgressIndicator())
                      : _imageUrls.isEmpty
                      ? Center(
                    child: Icon(Icons.image_not_supported, size: 48, color: Colors.grey.shade400),
                  )
                      : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Image.network(
                      _imageUrls[_currentIndex],
                      key: ValueKey(_imageUrls[_currentIndex]),
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(child: CircularProgressIndicator());
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Icon(Icons.broken_image, size: 48, color: Colors.grey.shade400),
                        );
                      },
                    ),
                  ),
                ),
              ),
              if (_imageUrls.length > 1) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_imageUrls.length, (index) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: index == _currentIndex ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: index == _currentIndex ? Colors.blueAccent : Colors.grey.shade300,
                      ),
                    );
                  }),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.isJapanese ? '処理中です。お待ちください...' : 'Processing, please wait...',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}