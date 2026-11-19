import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'key_mapping.dart';

typedef KeyCallback = void Function(int keyCode, bool isDown);

class VirtualKeypad extends StatelessWidget {
  final KeyCallback onKey;
  final bool showNumeric;

  const VirtualKeypad({
    super.key,
    required this.onKey,
    this.showNumeric = true,
  });

  Widget _buildKeyButton({
    required String label,
    required int keyCode,
    Color? color,
    double width = 56,
    double height = 48,
  }) {
    return Listener(
      onPointerDown: (_) {
        HapticFeedback.lightImpact();
        onKey(keyCode, true);
      },
      onPointerUp: (_) => onKey(keyCode, false),
      onPointerCancel: (_) => onKey(keyCode, false),
      child: Container(
        width: width,
        height: height,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: color ?? Colors.grey[850],
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              offset: const Offset(0, 2),
              blurRadius: 3,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF1A1A1A),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Row: Softkeys
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildKeyButton(
                label: "LSK",
                keyCode: J2meKey.softLeft,
                color: Colors.blueGrey[700],
                width: 72,
              ),
              _buildKeyButton(
                label: "CLR",
                keyCode: J2meKey.clear,
                color: Colors.red[800],
                width: 60,
              ),
              _buildKeyButton(
                label: "RSK",
                keyCode: J2meKey.softRight,
                color: Colors.blueGrey[700],
                width: 72,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Main Control Area: D-Pad and Numeric Keypad side by side or stacked
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // D-Pad Cross
              Column(
                children: [
                  _buildKeyButton(label: "▲", keyCode: J2meKey.up),
                  Row(
                    children: [
                      _buildKeyButton(label: "◀", keyCode: J2meKey.left),
                      _buildKeyButton(
                        label: "OK",
                        keyCode: J2meKey.fire,
                        color: Colors.amber[700],
                      ),
                      _buildKeyButton(label: "▶", keyCode: J2meKey.right),
                    ],
                  ),
                  _buildKeyButton(label: "▼", keyCode: J2meKey.down),
                ],
              ),

              // Numeric Keypad (Nokia 1-9, *, 0, #)
              if (showNumeric)
                Column(
                  children: [
                    Row(
                      children: [
                        _buildKeyButton(label: "1", keyCode: J2meKey.num1, width: 44, height: 40),
                        _buildKeyButton(label: "2", keyCode: J2meKey.num2, width: 44, height: 40),
                        _buildKeyButton(label: "3", keyCode: J2meKey.num3, width: 44, height: 40),
                      ],
                    ),
                    Row(
                      children: [
                        _buildKeyButton(label: "4", keyCode: J2meKey.num4, width: 44, height: 40),
                        _buildKeyButton(label: "5", keyCode: J2meKey.num5, width: 44, height: 40),
                        _buildKeyButton(label: "6", keyCode: J2meKey.num6, width: 44, height: 40),
                      ],
                    ),
                    Row(
                      children: [
                        _buildKeyButton(label: "7", keyCode: J2meKey.num7, width: 44, height: 40),
                        _buildKeyButton(label: "8", keyCode: J2meKey.num8, width: 44, height: 40),
                        _buildKeyButton(label: "9", keyCode: J2meKey.num9, width: 44, height: 40),
                      ],
                    ),
                    Row(
                      children: [
                        _buildKeyButton(label: "*", keyCode: J2meKey.star, width: 44, height: 40),
                        _buildKeyButton(label: "0", keyCode: J2meKey.num0, width: 44, height: 40),
                        _buildKeyButton(label: "#", keyCode: J2meKey.hash, width: 44, height: 40),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
