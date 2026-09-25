import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/features/auth/providers/auth_provider.dart';

void main() {
  test('fails closed when Supabase dart-defines are missing', () {
    final provider = AuthProvider();
    addTearDown(provider.dispose);

    expect(provider.isInitialized, isTrue);
    expect(provider.status, AuthStatus.unconfigured);
    expect(provider.configurationError, contains('SUPABASE_URL'));
    expect(provider.configurationError, contains('SUPABASE_PUBLISHABLE_KEY'));
  });
}
