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
        if (item.currency == CollectibleCurrency.achievement) {
          expect(item.price, 0, reason: '${item.id} is achievement-unlocked, not purchasable');
        } else {
          expect(item.price, greaterThan(0));
        }
      }
    });


    test('catalog items do not point at unverified artwork files', () {
      expect(kuruCollectibles.every((item) => item.assetPath == null), isTrue);
    });

    test('launch catalog has the four planned tiers and exactly three legendaries', () {
      expect(kuruCollectibles, hasLength(60));
      expect(kuruCollectibles.where((item) => item.tier == CollectibleTier.standard), hasLength(25));
      expect(kuruCollectibles.where((item) => item.tier == CollectibleTier.premium), hasLength(12));
      expect(kuruCollectibles.where((item) => item.tier == CollectibleTier.contributor), hasLength(10));
      expect(kuruCollectibles.where((item) => item.tier == CollectibleTier.contributor).every((item) => item.currency == CollectibleCurrency.achievement && item.price == 0 && item.unlockRule != null), isTrue);
      expect(kuruCollectibles.where((item) => item.tier == CollectibleTier.topTen), hasLength(10));
      final legendary = kuruCollectibles.where((item) => item.tier == CollectibleTier.legendary).toList();
      expect(legendary, hasLength(3));
      expect(legendary.map((item) => item.id), containsAll([
        'legendary_progenitor', 'legendary_celestial', 'legendary_cute_kuro',
      ]));
      expect(legendary.every((item) => item.currency == CollectibleCurrency.achievement), isTrue);
      expect(legendary.every((item) => item.unlockRule?.isNotEmpty == true), isTrue);
    });

    test('all catalog categories have a user-facing label', () {
      for (final category in CollectibleCategory.values) {
        expect(collectibleCategoryLabel(category).trim(), isNotEmpty);
      }
    });

    test('premium currency and event collectibles are explicitly tagged', () {
      expect(kuruCollectibles.where((item) => item.currency == CollectibleCurrency.gold), isNotEmpty);
      expect(kuruCollectibles.where((item) => item.eventOnly), isNotEmpty);
      expect(kuruCollectibles.every((item) => item.accent.toARGB32() != 0), isTrue);
    });


    test('premium character entries and all achievement items have explicit metadata', () {
      expect(kuruCollectibles.map((item) => item.id), containsAll([
        'character_akira',
        'character_mini_gojo',
      ]));
      for (final item in kuruCollectibles.where(
        (item) => item.currency == CollectibleCurrency.achievement,
      )) {
        expect(
          item.unlockRule?.trim(),
          isNotEmpty,
          reason: '${item.id} needs a visible unlock condition',
        );
      }
    });

    test('the catalog includes the key sticker expression entries', () {
      final names = kuruCollectibles
          .where((item) => item.category == CollectibleCategory.sticker)
          .map((item) => item.name)
          .toSet();
      expect(names, containsAll(['Happy', 'Laughing', 'Love', 'Shock', 'Angry', 'Cry',
        'Sleepy', 'Reading', 'Excited', 'Thinking', 'Salute', 'Bye Bye',
        'Clap', 'Hug', 'Cheer', 'Wow', 'Oops', 'Thank You', 'Support',
        'Creator Mode', 'Level Up!', 'Galaxy Mode', 'Rich Kuru']));
    });
  });
}
