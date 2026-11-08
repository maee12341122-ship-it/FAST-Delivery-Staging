import 'package:flutter/material.dart';

class FastAppLogo extends StatelessWidget {
  final double iconSize;
  final double textSize;
  final EdgeInsetsGeometry padding;

  const FastAppLogo({
    Key? key, 
    this.iconSize = 30.0, 
    this.textSize = 16.0,
    this.padding = const EdgeInsets.all(8.0),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.amber, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.flash_on,
            size: iconSize,
            color: Colors.amber,
          ),
          if (textSize > 0) ...[
            const SizedBox(width: 4),
            Text(
              'FAST',
              style: TextStyle(
                color: Colors.white,
                fontSize: textSize,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
