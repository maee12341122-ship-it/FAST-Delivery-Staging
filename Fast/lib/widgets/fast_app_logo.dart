import 'package:flutter/material.dart';

class FastAppLogo extends StatelessWidget {
  final double iconSize;
  final double textSize;
  final EdgeInsetsGeometry padding;

  const FastAppLogo({
    super.key,
    this.iconSize = 30.0,
    this.textSize = 16.0,
    this.padding = const EdgeInsets.all(2.0),
  });

  @override
  Widget build(BuildContext context) {
    final double logoSize = iconSize > 45 ? iconSize * 1.9 : iconSize * 1.25;

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
      child: ClipOval(
        child: Image.asset(
          'assets/images/fast_logo.jpg',
          width: logoSize,
          height: logoSize,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => SizedBox(
            width: logoSize,
            height: logoSize,
            child: Icon(
              Icons.flash_on,
              size: iconSize * 0.75,
              color: Colors.amber,
            ),
          ),
        ),
      ),
    );
  }
}
