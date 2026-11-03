import 'package:flutter_connect/flutter_connect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'WebView bridge carries configured identity and escapes inline HTML',
    () {
      final script = WebViewProviders.script(
        info: ProviderInfo(
          name: '</script><script>alert(1)</script>',
          rdns: 'onl.tone',
        ),
        channel: 'WalletBridge',
      );
      expect(script, contains('window["WalletBridge"].postMessage'));
      expect(script, contains('"rdns":"onl.tone"'));
      expect(script, isNot(contains('</script>')));
      expect(script, contains(WebViewProviders.documentProperty));
      expect(script, contains(WebViewProviders.replyProperty));
      expect(script, contains("Object.defineProperty(window, 'connect'"));
      expect(script, contains("Object.defineProperty(window, 'core'"));
    },
  );

  test('WebView bridge rejects executable channel expressions', () {
    expect(
      () =>
          WebViewProviders.script(info: ProviderInfo(), channel: 'x);alert(1)'),
      throwsArgumentError,
    );
  });
}
