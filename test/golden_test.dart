import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sugar_light/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  setUpAll(() async {
    final font = rootBundle.load('assets/fonts/Nunito.ttf');
    await (FontLoader('Nunito')..addFont(font)).load();
    final icons = rootBundle.load('assets/fonts/MaterialIcons-Regular.otf');
    await (FontLoader('MaterialIcons')..addFont(icons)).load();
  });
  testWidgets('screen golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    await tester.pumpWidget(const EmberFree());
    await tester.pump(const Duration(seconds: 1));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('screen.png'),
    );
  });
}
