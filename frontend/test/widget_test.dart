import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/ai_chat_page.dart';

void main() {
  testWidgets('AI chat page renders the assistant shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AiChatPage()));

    expect(find.text('Voya AI'), findsOneWidget);
    expect(find.text('Travel Assistant'), findsOneWidget);
    expect(find.text('Ask something about travel...'), findsOneWidget);
  });
}
