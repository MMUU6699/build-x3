import 'package:flutter_test/flutter_test.dart';
import 'package:Kelivo/core/providers/user_provider.dart';

import '../../support/business_test_harness.dart';

void main() {
  test(
    'keeps local profile overrides scoped to the authenticated user',
    () async {
      final preferences = createBusinessTestPreferences();
      await preferences.load();
      final provider = UserProvider(preferences: preferences);
      await Future<void>.delayed(Duration.zero);

      provider.syncFromAuthUser(
        authUserId: 'account-a',
        authDisplayName: 'Account A',
        authAvatarUrl: 'https://example.com/a.png',
        authEmail: 'a@example.com',
      );
      await provider.setName('Local A');
      await provider.setAvatarEmoji('A');

      provider.clearAuthUser();
      provider.syncFromAuthUser(
        authUserId: 'account-b',
        authDisplayName: 'Account B',
        authAvatarUrl: 'https://example.com/b.png',
        authEmail: 'b@example.com',
      );

      expect(provider.name, 'Account B');
      expect(provider.avatarType, 'url');
      expect(provider.avatarValue, 'https://example.com/b.png');

      provider.clearAuthUser();
      provider.syncFromAuthUser(
        authUserId: 'account-a',
        authDisplayName: 'Account A',
        authAvatarUrl: 'https://example.com/a.png',
        authEmail: 'a@example.com',
      );

      expect(provider.name, 'Local A');
      expect(provider.avatarType, 'emoji');
      expect(provider.avatarValue, 'A');
    },
  );

  test(
    'clearAuthUser removes the previous account from visible state',
    () async {
      final preferences = createBusinessTestPreferences();
      await preferences.load();
      final provider = UserProvider(preferences: preferences);
      await Future<void>.delayed(Duration.zero);

      provider.syncFromAuthUser(
        authUserId: 'account-a',
        authDisplayName: 'Account A',
        authAvatarUrl: 'https://example.com/a.png',
        authEmail: 'a@example.com',
      );
      provider.clearAuthUser();

      expect(provider.name, 'User');
      expect(provider.avatarType, isNull);
      expect(provider.avatarValue, isNull);
    },
  );
}
