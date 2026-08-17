import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class SurveyDialog extends StatefulWidget {
  final String surveyUrl;
  final bool isJapanese;

  const SurveyDialog({
    Key? key,
    required this.surveyUrl,
    this.isJapanese = false,
  }) : super(key: key);

  static Future<void> show({
    required BuildContext context,
    required String surveyUrl,
    bool isJapanese = false,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (context) {
        return SurveyDialog(surveyUrl: surveyUrl, isJapanese: isJapanese);
      },
    );
  }

  @override
  State<SurveyDialog> createState() => _SurveyDialogState();
}

class _SurveyDialogState extends State<SurveyDialog> {
  InAppWebViewController? webViewController;
  double _progress = 0;
  bool _isLoading = true;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = screenSize.width * 0.94 > 620 ? 620.0 : screenSize.width * 0.94;
    final dialogHeight = screenSize.height * 0.85;

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.transparent,
        child: Container(
          width: dialogWidth,
          height: dialogHeight,
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
                child: Row(
                  children: [
                    const Icon(Icons.assignment, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.isJapanese ? "アンケート" : "SURVEY",
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              if (_isLoading)
                LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress,
                  backgroundColor: const Color(0xFFEFF6FF),
                  color: const Color(0xFF2563EB),
                  minHeight: 3,
                ),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(widget.surveyUrl)),
                    initialSettings: InAppWebViewSettings(
                      mediaPlaybackRequiresUserGesture: false,
                      javaScriptEnabled: true,
                      useHybridComposition: true,
                      allowsInlineMediaPlayback: true,
                      cacheEnabled: true,
                      javaScriptCanOpenWindowsAutomatically: true,
                      transparentBackground: true,
                      thirdPartyCookiesEnabled: true,
                      domStorageEnabled: true,
                      databaseEnabled: true,
                      hardwareAcceleration: true,
                      supportMultipleWindows: false,
                      useWideViewPort: true,
                      loadWithOverviewMode: true,
                      mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                      verticalScrollBarEnabled: false,
                      horizontalScrollBarEnabled: false,
                    ),
                    onWebViewCreated: (controller) {
                      webViewController = controller;
                    },
                    onLoadStart: (controller, url) {
                      setState(() {
                        _isLoading = true;
                        _progress = 0;
                      });
                    },
                    onLoadStop: (controller, url) {
                      setState(() {
                        _isLoading = false;
                        _progress = 1;
                      });
                    },
                    onProgressChanged: (controller, progress) {
                      setState(() {
                        _progress = progress / 100;
                      });
                    },
                    onReceivedServerTrustAuthRequest: (controller, challenge) async {
                      return ServerTrustAuthResponse(action: ServerTrustAuthResponseAction.PROCEED);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}