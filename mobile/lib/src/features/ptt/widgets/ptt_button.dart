import 'package:flutter/material.dart';

class PttButton extends StatefulWidget {
  final bool channelBusy;
  final VoidCallback onPressedDown;
  final VoidCallback onPressedUp;

  const PttButton({
    super.key,
    required this.channelBusy,
    required this.onPressedDown,
    required this.onPressedUp,
  });

  @override
  State<PttButton> createState() => _PttButtonState();
}

class _PttButtonState extends State<PttButton> {
  bool pressing = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) {
        if (widget.channelBusy) {
          return;
        }
        setState(() => pressing = true);
        widget.onPressedDown();
      },
      onLongPressEnd: (_) {
        if (!pressing) {
          return;
        }
        setState(() => pressing = false);
        widget.onPressedUp();
      },
      child: Container(
        width: 180,
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.channelBusy
              ? Colors.grey
              : (pressing ? Colors.red : Colors.indigo),
        ),
        child: Text(
          widget.channelBusy ? 'Kanal Mesgul' : (pressing ? 'Konus' : 'Bas Konus'),
          style: const TextStyle(color: Colors.white, fontSize: 24),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
