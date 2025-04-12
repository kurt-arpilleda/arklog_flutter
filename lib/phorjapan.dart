import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PhOrJpScreen extends StatefulWidget {
  const PhOrJpScreen({super.key});

  @override
  _PhOrJpScreenState createState() => _PhOrJpScreenState();
}

class _PhOrJpScreenState extends State<PhOrJpScreen> with WidgetsBindingObserver {
  bool _isLoadingPh = false;
  bool _isLoadingJp = false;
  bool _isPhPressed = false;
  bool _isJpPressed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reset any loading states when app resumes
      if (_isLoadingPh || _isLoadingJp) {
        setState(() {
          _isLoadingPh = false;
          _isLoadingJp = false;
          _isPhPressed = false;
          _isJpPressed = false;
        });
      }
    }
  }

  Future<void> _setPreference(String value, BuildContext context) async {
    if ((value == 'ph' && _isLoadingPh) || (value == 'jp' && _isLoadingJp)) {
      return;
    }

    setState(() {
      if (value == 'ph') {
        _isLoadingPh = true;
        _isPhPressed = true;
      } else {
        _isLoadingJp = true;
        _isJpPressed = true;
      }
    });

    try {
      await Future.delayed(const Duration(milliseconds: 100));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('phorjp', value);

      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          value == 'ph' ? '/login' : '/loginJP',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (value == 'ph') {
            _isLoadingPh = false;
            _isPhPressed = false;
          } else {
            _isLoadingJp = false;
            _isJpPressed = false;
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PH or JP',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // PH Flag with button-like animation
                    GestureDetector(
                      onTapDown: (_) => setState(() => _isPhPressed = true),
                      onTapUp: (_) => setState(() => _isPhPressed = false),
                      onTapCancel: () => setState(() => _isPhPressed = false),
                      onTap: () => _setPreference('ph', context),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        transform: Matrix4.identity()..scale(_isPhPressed ? 0.95 : 1.0),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Image.asset(
                              'assets/images/philippines.png',
                              width: 75,
                              height: 75,
                              fit: BoxFit.contain,
                            ),
                            if (_isLoadingPh)
                              const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                strokeWidth: 2,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 40),
                    // JP Flag with button-like animation
                    GestureDetector(
                      onTapDown: (_) => setState(() => _isJpPressed = true),
                      onTapUp: (_) => setState(() => _isJpPressed = false),
                      onTapCancel: () => setState(() => _isJpPressed = false),
                      onTap: () => _setPreference('jp', context),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        transform: Matrix4.identity()..scale(_isJpPressed ? 0.95 : 1.0),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Image.asset(
                              'assets/images/japan.png',
                              width: 75,
                              height: 75,
                              fit: BoxFit.contain,
                            ),
                            if (_isLoadingJp)
                              const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                strokeWidth: 2,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Select your country',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}