import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chinobox/src/app/chino_box_app.dart';

void main() {
  testWidgets('app starts', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: ChinoBoxApp()));
    await tester.pump();

    expect(find.byType(ChinoBoxApp), findsOneWidget);
  });
}
