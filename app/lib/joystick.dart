import 'package:flutter/material.dart';

class Joystick extends StatefulWidget {
  const Joystick({super.key, required this.onChanged, this.size = 130});
  final ValueChanged<Offset> onChanged;
  final double size;

  @override
  State<Joystick> createState() => _JoystickState();
}

class _JoystickState extends State<Joystick> {
  Offset _v = Offset.zero;

  void _set(Offset local) {
    final r = widget.size / 2;
    var v = (local - Offset(r, r)) / r;
    if (v.distance > 1) v = v / v.distance;
    setState(() => _v = v);
    widget.onChanged(v);
  }

  void _reset() {
    setState(() => _v = Offset.zero);
    widget.onChanged(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.size / 2;
    return GestureDetector(
      onPanStart: (d) => _set(d.localPosition),
      onPanUpdate: (d) => _set(d.localPosition),
      onPanEnd: (_) => _reset(),
      onPanCancel: _reset,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Stack(children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withAlpha(200),
              border: Border.all(color: Colors.teal, width: 2),
            ),
          ),
          Positioned(
            left: r + _v.dx * r * 0.6 - 24,
            top: r + _v.dy * r * 0.6 - 24,
            child: Container(
              width: 48,
              height: 48,
              decoration:
                  const BoxDecoration(shape: BoxShape.circle, color: Colors.teal),
            ),
          ),
        ]),
      ),
    );
  }
}
