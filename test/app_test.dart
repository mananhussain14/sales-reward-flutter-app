import 'package:flutter_test/flutter_test.dart';
import 'package:sale_reward/app/app.dart';

void main() {
  testWidgets('renders the saleReward application', (tester) async {
    await tester.pumpWidget(const SaleRewardApp());

    expect(find.text('saleReward'), findsOneWidget);
  });
}
