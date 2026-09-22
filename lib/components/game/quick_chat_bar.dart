import 'package:flutter/material.dart';

class QuickChatBar extends StatelessWidget {
  final ValueChanged<String> onSendMessage;

  const QuickChatBar({super.key, required this.onSendMessage});

  static const List<String> messages = [
    "Sorry! 🙏",
    "Ouch! 💥",
    "Love it! ❤️",
    "Good luck! 🍀",
    "😂",
    "😎",
    "🔥",
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.012),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.025)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: messages.map((msg) {
            return Padding(
              padding: const EdgeInsets.only(right: 5),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: ActionChip(
                  label: SizedBox(
                    height: 18,
                    child: Center(
                      child: Text(
                        msg,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 6,
                  ),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  backgroundColor: Colors.white.withOpacity(0.035),
                  side: BorderSide(color: Colors.white.withOpacity(0.09)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  onPressed: () => onSendMessage(msg),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
