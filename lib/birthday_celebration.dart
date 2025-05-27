import 'package:flutter/material.dart';
import 'dart:math';

class BirthdayCelebration extends StatefulWidget {
  final String name;
  final int languageFlag;
  final VoidCallback onFinish;

  const BirthdayCelebration({
    Key? key,
    required this.name,
    required this.onFinish,
    this.languageFlag = 1,
  }) : super(key: key);

  static void close(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  _BirthdayCelebrationState createState() => _BirthdayCelebrationState();
}

class _BirthdayCelebrationState extends State<BirthdayCelebration>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Balloon> _balloons = [];
  final Random _random = Random();
  bool _showCake = false;
  bool _showText = false;
  double _textOpacity = 0.0;
  double _textScale = 0.5;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )
      ..addListener(() {
        _updateBalloons();
      })
      ..forward().whenComplete(widget.onFinish);

    for (int i = 0; i < 30; i++) {
      _balloons.add(_createBalloon());
    }

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _showCake = true);
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() {
        _showText = true;
        _textOpacity = 1.0;
        _textScale = 1.0;
      });
    });
  }

  Balloon _createBalloon() {
    return Balloon(
      x: _random.nextDouble(),
      speed: 2 + _random.nextDouble() * 3,
      color: Colors.primaries[_random.nextInt(Colors.primaries.length)],
      size: 30 + _random.nextDouble() * 30,
    );
  }

  void _updateBalloons() {
    setState(() {
      for (var balloon in _balloons) {
        balloon.update();
      }
      _balloons.removeWhere((b) => b.y < -0.2);
      while (_balloons.length < 30) {
        _balloons.add(_createBalloon());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    final isJapanese = widget.languageFlag == 2;
    final birthdayMessage = isJapanese
        ? 'お誕生日おめでとうございます。\n${widget.name}さん！'
        : 'Happy Birthday\n${widget.name}!';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _controller,
        builder: (_, __) {
          return Stack(
            children: [
              // Balloons
              ..._balloons.map((balloon) {
                return Positioned(
                  left: balloon.x * screenWidth,
                  bottom: balloon.y * screenHeight,
                  child: Opacity(
                    opacity: balloon.opacity,
                    child: Transform.rotate(
                      angle: balloon.angle,
                      child: CustomPaint(
                        painter: BalloonPainter(
                          color: balloon.color,
                          size: balloon.size,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),

              // Cake
              if (_showCake)
                Center(
                  child: AnimatedOpacity(
                    opacity: _showCake ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 500),
                    child: AnimatedScale(
                      scale: _showCake ? 1.0 : 0.5,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.elasticOut,
                      child: Image.asset(
                        'assets/images/birthday_cake.png',
                        width: 150,
                        height: 150,
                      ),
                    ),
                  ),
                ),

              // Text
              if (_showText)
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(height: screenHeight * 0.35),
                      AnimatedOpacity(
                        opacity: _textOpacity,
                        duration: const Duration(milliseconds: 500),
                        child: AnimatedScale(
                          scale: _textScale,
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.elasticOut,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24.0),
                            child: Text(
                              birthdayMessage,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: isJapanese ? 24 : 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.4,
                                shadows: const [
                                  Shadow(
                                    blurRadius: 10,
                                    color: Colors.black,
                                    offset: Offset(2, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class Balloon {
  double x;
  double y = 0.0;
  double speed;
  Color color;
  double size;
  double angle;
  double opacity;

  Balloon({
    required this.x,
    required this.speed,
    required this.color,
    required this.size,
  })  : angle = Random().nextDouble() * 0.2 - 0.1,
        opacity = 0.8 + Random().nextDouble() * 0.2;

  void update() {
    y += speed / 600;
    angle += (Random().nextDouble() * 0.02 - 0.01);
  }
}

class BalloonPainter extends CustomPainter {
  final Color color;
  final double size;

  BalloonPainter({required this.color, required this.size});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(this.size / 2 + 2, this.size / 2 + 2),
        width: this.size,
        height: this.size * 1.2,
      ),
      shadowPaint,
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(this.size / 2, this.size / 2),
        width: this.size,
        height: this.size * 1.2,
      ),
      paint,
    );

    final knotPaint = Paint()..color = color.withOpacity(0.8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(this.size / 2, this.size * 1.2),
          width: this.size * 0.2,
          height: this.size * 0.3,
        ),
        Radius.circular(this.size * 0.1),
      ),
      knotPaint,
    );

    final stringPaint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 1.0;

    final path = Path()
      ..moveTo(this.size / 2, this.size * 1.35)
      ..quadraticBezierTo(
        this.size / 2 + this.size * 0.1,
        this.size * 1.5,
        this.size / 2,
        this.size * 1.65,
      )
      ..quadraticBezierTo(
        this.size / 2 - this.size * 0.1,
        this.size * 1.8,
        this.size / 2,
        this.size * 1.95,
      );
    canvas.drawPath(path, stringPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
