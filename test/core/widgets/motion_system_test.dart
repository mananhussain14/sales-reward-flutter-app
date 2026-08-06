import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/core/design/design.dart';
import 'package:sale_reward/core/widgets/widgets.dart';

import '../../support/pump_app.dart';

/// The motion system's four primitives and the progress ring.
///
/// One property is defended above all the others: **reduced motion removes the
/// movement, never the state**. Every primitive here has to be at its settled
/// end on the first frame when a reader has asked for less motion — the real
/// number, the opaque content, the drawn arc — because a screen that renders
/// nothing under an accessibility setting is worse than one that never animated.
///
/// The second property is that **nothing here loops or replays**. A count-up
/// that restarted whenever a Bloc emitted an equal state would make every figure
/// on the earnings and home screens flicker on any unrelated rebuild.
void main() {
  /// `MediaQuery.disableAnimations` true, and nothing else.
  const FakeAccessibilityFeatures reducedMotion = FakeAccessibilityFeatures(
    disableAnimations: true,
  );

  String textOf(WidgetTester tester) =>
      tester.widget<Text>(find.byType(Text)).data ?? '';

  group('SrEnter', () {
    testWidgets('settles opaque and drops its wrappers', (
      WidgetTester tester,
    ) async {
      await pumpThemed(tester, const SrEnter(child: Text('Arrived')));
      await tester.pumpAndSettle();

      expect(find.text('Arrived'), findsOneWidget);
      // Settled: nothing composites afterwards.
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('under reduced motion the content is simply there', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = reducedMotion;
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await pumpThemed(tester, const SrEnter(child: Text('Arrived')));
      // One frame, no settling.
      expect(find.text('Arrived'), findsOneWidget);
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    });

    testWidgets('a staggered item still arrives', (WidgetTester tester) async {
      await pumpThemed(tester, const SrEnter(index: 4, child: Text('Fifth')));
      await tester.pumpAndSettle();

      expect(find.text('Fifth'), findsOneWidget);
    });
  });

  group('SrCountUp', () {
    Widget counter(int value) => SrCountUp(
      value: value,
      builder: (BuildContext context, int displayed) => Text('$displayed'),
    );

    testWidgets('ends on the stored value', (WidgetTester tester) async {
      await pumpThemed(tester, counter(2530));
      await tester.pumpAndSettle();

      expect(textOf(tester), '2530');
    });

    testWidgets('counts from zero rather than starting there', (
      WidgetTester tester,
    ) async {
      await pumpThemed(tester, counter(2530));
      // The first frame is the start of the tween, not its end.
      expect(int.parse(textOf(tester)), lessThan(2530));

      await tester.pumpAndSettle();
      expect(textOf(tester), '2530');
    });

    testWidgets('a rebuild with the same value does not replay it', (
      WidgetTester tester,
    ) async {
      await pumpThemed(tester, counter(500));
      await tester.pumpAndSettle();
      expect(textOf(tester), '500');

      // The same value again — what an equal Bloc state, a rotation or a theme
      // change produces. The figure must not drop back to zero.
      await pumpThemed(tester, counter(500));
      await tester.pump();
      expect(textOf(tester), '500');
    });

    testWidgets('zero is a real value and renders as zero', (
      WidgetTester tester,
    ) async {
      await pumpThemed(tester, counter(0));
      await tester.pumpAndSettle();

      expect(textOf(tester), '0');
    });

    testWidgets('under reduced motion the first frame is the real number', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = reducedMotion;
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await pumpThemed(tester, counter(2530));

      expect(textOf(tester), '2530');
    });
  });

  group('SrProgressRing', () {
    testWidgets('draws, and stays silent to assistive technology', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        const SrProgressRing(value: 0.48, center: Text('48%')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CustomPaint), findsWidgets);
      // The caller owns the announcement: a bare ring announces a percentage
      // and nothing about whose units it counts.
      expect(find.byType(ExcludeSemantics), findsWidgets);
      expect(find.text('48%'), findsOneWidget);
    });

    testWidgets('a value past the end is clamped rather than overdrawn', (
      WidgetTester tester,
    ) async {
      await pumpThemed(tester, const SrProgressRing(value: 1.6));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('a segmented ring renders', (WidgetTester tester) async {
      await pumpThemed(tester, const SrProgressRing(value: 0.5, segments: 4));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('under reduced motion it is painted at its value at once', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = reducedMotion;
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await pumpThemed(tester, const SrProgressRing(value: 0.7));

      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('SrPressScale', () {
    testWidgets('acknowledges a press and returns to rest', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        const SrPressScale(
          // Opaque to hit testing, as every real surface this wraps is.
          child: SizedBox(
            width: 100,
            height: 44,
            child: ColoredBox(color: Color(0xFF000000)),
          ),
        ),
      );

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(SrPressScale)),
      );
      await tester.pump(SrMotion.fast);

      final AnimatedScale pressed = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      expect(pressed.scale, lessThan(1));

      await gesture.up();
      await tester.pumpAndSettle();

      final AnimatedScale released = tester.widget<AnimatedScale>(
        find.byType(AnimatedScale),
      );
      expect(released.scale, 1);
    });

    testWidgets('under reduced motion nothing moves', (
      WidgetTester tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = reducedMotion;
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await pumpThemed(
        tester,
        const SrPressScale(
          child: SizedBox(
            width: 100,
            height: 44,
            child: ColoredBox(color: Color(0xFF000000)),
          ),
        ),
      );

      expect(find.byType(AnimatedScale), findsNothing);
    });

    testWidgets('a disabled surface does not respond', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        const SrPressScale(
          enabled: false,
          child: SizedBox(
            width: 100,
            height: 44,
            child: ColoredBox(color: Color(0xFF000000)),
          ),
        ),
      );

      expect(find.byType(AnimatedScale), findsNothing);
    });
  });

  group('SrSuccessMark', () {
    testWidgets('settles, and is present at once under reduced motion', (
      WidgetTester tester,
    ) async {
      await pumpThemed(tester, const SrSuccessMark());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

      tester.platformDispatcher.accessibilityFeaturesTestValue = reducedMotion;
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );

      await pumpThemed(tester, const SrSuccessMark());
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    });
  });

  group('SrHeroPanel', () {
    forEachBrightness((Brightness brightness) {
      testWidgets('renders its content in ${brightness.name}', (
        WidgetTester tester,
      ) async {
        await pumpThemed(
          tester,
          const SrHeroPanel(
            icon: Icons.savings_rounded,
            child: SrHeroFact(label: 'This month', value: '530 coins'),
          ),
          brightness: brightness,
        );

        expect(find.text('This month'), findsOneWidget);
        expect(find.text('530 coins'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('the watermark glyph carries no meaning of its own', (
      WidgetTester tester,
    ) async {
      await pumpThemed(
        tester,
        const SrHeroPanel(
          icon: Icons.savings_rounded,
          child: Text('Total campaign coins earned'),
        ),
      );

      expect(find.text('Total campaign coins earned'), findsOneWidget);
      // Decorative only: every meaning on this panel is in its text.
      expect(find.byType(ExcludeSemantics), findsWidgets);
    });
  });
}
