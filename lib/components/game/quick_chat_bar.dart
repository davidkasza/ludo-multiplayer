import 'package:flutter/material.dart';

class QuickChatBar extends StatelessWidget {
  final ValueChanged<String> onSendMessage;

  const QuickChatBar({
    super.key,
    required this.onSendMessage,
  });

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
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.04)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: messages.map((msg) {
            return Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: ActionChip(
                label: SizedBox(
                  height: 20,
                  child: Center(
                    child: Text(
                      msg,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 8,
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: Colors.white.withOpacity(0.05),
                side: BorderSide(color: Colors.white.withOpacity(0.14)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                onPressed: () => onSendMessage(msg),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}