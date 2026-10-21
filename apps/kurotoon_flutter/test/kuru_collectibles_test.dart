import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_flutter/shop/kuru_collectibles.dart';

void main() {
  group('Kuru collectible catalog', () {
    test('every collectible has a stable, unique identity', () {
      final ids = kuruCollectibles.map((item) => item.id).toList();
      expect(ids, isNotEmpty);
      expect(ids.toSet().length, ids.length);
      for (final item in kuruCollectibles) {
        expect(item.id, matches(RegExp(r'^[a-z0-9_]+$')));
        expect(item.name.trim(), isNotEmpty);
        expect(item.description.trim(), isNotEmpty);
        expect(item.price, greaterThan(0));
      }
    });

    test('all catalog categories have a user-facing label', () {
      for (final category in CollectibleCategory.values) {
        expect(collectibleCategoryLabel(category).trim(), isNotEmpty);
      }
    });

    test('premium currency and event collectibles are explicitly tagged', () {
      expect(kuruCollectibles.where((item) => item.currency == CollectibleCurrency.gold), isNotEmpty);
      expect(kuruCollectibles.where((item) => item.eventOnly), isNotEmpty);
      expect(kuruCollectibles.every((item) => item.accent.alpha > 0), isTrue);
    });

    test('the reference sticker set includes the key expressions', () {
      final names = kuruCollectibles
          .where((item) => item.category == CollectibleCategory.sticker)
          .map((item) => item.name)
          .toSet();
      expect(names, containsAll(['Happy', 'Laughing', 'Love', 'Shock', 'Angry', 'Cry',
        'Sleepy', 'Reading', 'Excited', 'Thinking', 'Salute', 'Bye Bye',
        'Clap', 'Hug', 'Cheer', 'Wow', 'Oops', 'Thank You', 'Support',
        'Creator Mode', 'Level Up!', 'Galaxy Mode', 'Rich Kuru', 'Nom Nom']));
    });
  });
}
