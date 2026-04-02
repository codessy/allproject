import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:walkietalkie_mobile/src/features/ptt/widgets/ptt_button.dart';

void main() {
  group('PttButton', () {
    testWidgets('calls down and up on long press when channel is available', (tester) async {
      var downCalls = 0;
      var upCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PttButton(
                channelBusy: false,
                onPressedDown: () => downCalls += 1,
                onPressedUp: () => upCalls += 1,
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(tester.getCenter(find.byType(PttButton)));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump();

      expect(downCalls, 1);
      expect(upCalls, 1);
      expect(find.text('Bas Konus'), findsOneWidget);
    });

    testWidgets('does not call callbacks when channel is busy', (tester) async {
      var downCalls = 0;
      var upCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PttButton(
                channelBusy: true,
                onPressedDown: () => downCalls += 1,
                onPressedUp: () => upCalls += 1,
              ),
            ),
          ),
        ),
      );

      final gesture = await tester.startGesture(tester.getCenter(find.byType(PttButton)));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump();

      expect(find.text('Kanal Mesgul'), findsOneWidget);
      expect(downCalls, 0);
      expect(upCalls, 0);
    });
  });
}
