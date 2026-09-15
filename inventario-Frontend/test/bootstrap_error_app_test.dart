import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/main.dart';

void main() {
  testWidgets('production error presentation does not expose diagnostics',
      (tester) async {
    await tester.pumpWidget(BootstrapErrorApp(
      error: StateError('SQL private-test-marker'),
      stackTrace: StackTrace.fromString('internal-stack-marker'),
      showDiagnostics: false,
    ));
    final text =
        tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(text, contains('No pudimos iniciar la aplicación'));
    expect(text, contains('contacta soporte'));
    expect(text, isNot(contains('SQL')));
    expect(text, isNot(contains('private-test-marker')));
    expect(text, isNot(contains('internal-stack-marker')));
  });

  testWidgets('debug keeps technical bootstrap detail', (tester) async {
    await tester.pumpWidget(BootstrapErrorApp(
      error: StateError('debug-only-detail'),
      stackTrace: StackTrace.fromString('debug-only-stack'),
    ));
    expect(find.textContaining('debug-only-detail'), findsOneWidget);
    expect(find.textContaining('debug-only-stack'), findsOneWidget);
  });
}
