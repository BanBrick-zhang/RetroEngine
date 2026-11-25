import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savedeck_toolkit/widgets/translation_dialog.dart';

Widget _host(void Function(BuildContext) onOpen) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => onOpen(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('取消翻译弹窗不应用结果', (tester) async {
    String? result;
    await tester.pumpWidget(_host((context) async {
      result = await showTranslationResultDialog(
        context,
        original: 'Hello',
        translated: '你好',
      );
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('你好'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('修改译文后应用返回编辑后的内容', (tester) async {
    String? result;
    await tester.pumpWidget(_host((context) async {
      result = await showTranslationResultDialog(
        context,
        original: 'Hello',
        translated: '你好',
      );
    }));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '您好');
    await tester.tap(find.text('应用翻译'));
    await tester.pumpAndSettle();

    expect(result, '您好');
  });
}