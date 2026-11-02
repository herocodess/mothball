import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mothball/places.dart';

Widget host() => const MaterialApp(
      home: Scaffold(
        body: Align(alignment: Alignment.topRight, child: Padding(padding: EdgeInsets.all(40), child: ProjectMenu(path: '/tmp/x'))),
      ),
    );

void main() {
  testWidgets('the menu opens when the pointer rests on the button and closes after it leaves', (t) async {
    await t.pumpWidget(host());
    final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(t.getCenter(find.byIcon(Icons.more_horiz)));
    await t.pump(const Duration(milliseconds: 60));
    expect(find.textContaining('Show in'), findsNothing, reason: 'a quick pass over the button does not open it');
    await t.pump(const Duration(milliseconds: 100));
    await t.pumpAndSettle();
    expect(find.textContaining('Show in'), findsOneWidget);
    expect(find.text('Copy path'), findsOneWidget);

    // Moving onto the menu keeps it open.
    await mouse.moveTo(t.getCenter(find.text('Copy path')));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Copy path'), findsOneWidget);

    // Leaving both closes it, with the closing animation.
    await mouse.moveTo(const Offset(5, 500));
    await t.pump(const Duration(milliseconds: 250));
    await t.pumpAndSettle();
    expect(find.text('Copy path'), findsNothing);
  });

  testWidgets('a click opens the menu and keeps it open until a click outside', (t) async {
    await t.pumpWidget(host());
    await t.tap(find.byIcon(Icons.more_horiz));
    await t.pumpAndSettle();
    expect(find.text('Copy path'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Copy path'), findsOneWidget);
    await t.tapAt(const Offset(5, 500));
    await t.pumpAndSettle();
    expect(find.text('Copy path'), findsNothing);
  });

  testWidgets('right-click menu opens at the pointer and closes on a click elsewhere', (t) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => GestureDetector(
            onSecondaryTapUp: (d) => ProjectMenu.showAt(context, d.globalPosition, '/tmp/x'),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    ));
    await t.tapAt(const Offset(100, 100), buttons: kSecondaryButton, kind: PointerDeviceKind.mouse);
    await t.pumpAndSettle();
    expect(find.text('Copy path'), findsOneWidget);
    expect(t.getTopLeft(find.text('Copy path')).dx, greaterThan(100));
    await t.tapAt(const Offset(600, 500));
    await t.pumpAndSettle();
    expect(find.text('Copy path'), findsNothing);
  });
}
