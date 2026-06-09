import 'package:flutter/material.dart';

class GlassPanel extends StatelessWidget {
  final String title;
  final Widget child;

  const GlassPanel({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Color(0xffe5e7eb), fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}