import 'package:flutter/material.dart';

enum CollectibleCategory { sticker, avatar, seasonal, outfit, pose, expression, character }
enum CollectibleCurrency { silver, gold, achievement }
enum CollectibleTier { standard, premium, topTen, legendary, contributor }

/// Stable catalog identity. Artwork paths are deliberately explicit so each
/// collectible can be replaced by a reviewed, isolated source crop without
/// changing ownership or achievement records.
class KuruCollectible {
  const KuruCollectible({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.currency,
    required this.price,
    required this.rarity,
    required this.icon,
    required this.accent,
    required this.animation,
    this.assetPath,
    this.eventOnly = false,
    this.tier = CollectibleTier.standard,
    this.unlockRule,
  });

  final String id;
  final String name;
  final CollectibleCategory category;
  final String description;
  final CollectibleCurrency currency;
  final int price;
  final String rarity;
  final IconData icon;
  final Color accent;
  final CollectibleAnimation animation;
  final String? assetPath;
  final bool eventOnly;
  final CollectibleTier tier;
  /// Human-readable unlock condition. A backend must enforce restricted rewards.
  final String? unlockRule;
}

enum CollectibleAnimation { bounce, hearts, tears, sparkle, pulse, float, shake, orbit, confetti }

const kuruCollectibles = <KuruCollectible>[
  KuruCollectible(id:'kuru_happy', name:'Happy', category:CollectibleCategory.sticker, description:'A bright little burst of happiness.', currency:CollectibleCurrency.silver, price:80, rarity:'Common', icon:Icons.sentiment_very_satisfied_rounded, accent:Color(0xFFFF80C8), animation:CollectibleAnimation.bounce, assetPath:'assets/shop/stickers/happy.jpg'),
  KuruCollectible(id:'kuru_laughing', name:'Laughing', category:CollectibleCategory.sticker, description:'Kuru cannot stop giggling.', currency:CollectibleCurrency.silver, price:90, rarity:'Common', icon:Icons.mood_rounded, accent:Color(0xFFFFB45E), animation:CollectibleAnimation.shake, assetPath:'assets/shop/stickers/laughing.jpg'),
  KuruCollectible(id:'kuru_love', name:'Love', category:CollectibleCategory.sticker, description:'A little cosmic affection.', currency:CollectibleCurrency.silver, price:100, rarity:'Common', icon:Icons.favorite_rounded, accent:Color(0xFFFF6EAB), animation:CollectibleAnimation.hearts, assetPath:'assets/shop/stickers/love.jpg'),
  KuruCollectible(id:'kuru_shock', name:'Shock', category:CollectibleCategory.sticker, description:'Absolutely did not see that coming.', currency:CollectibleCurrency.silver, price:90, rarity:'Common', icon:Icons.visibility_rounded, accent:Color(0xFF8FEAFF), animation:CollectibleAnimation.bounce, assetPath:'assets/shop/stickers/shock.jpg'),
  KuruCollectible(id:'kuru_angry', name:'Angry', category:CollectibleCategory.sticker, description:'Tiny ears. Huge attitude.', currency:CollectibleCurrency.silver, price:90, rarity:'Common', icon:Icons.whatshot_rounded, accent:Color(0xFFFF765F), animation:CollectibleAnimation.shake, assetPath:'assets/shop/stickers/angry.jpg'),
  KuruCollectible(id:'kuru_cry', name:'Cry', category:CollectibleCategory.sticker, description:'A dramatic rainstorm of tears.', currency:CollectibleCurrency.silver, price:100, rarity:'Common', icon:Icons.water_drop_rounded, accent:Color(0xFF79C9FF), animation:CollectibleAnimation.tears, assetPath:'assets/shop/stickers/cry.jpg'),
  KuruCollectible(id:'kuru_sleepy', name:'Sleepy', category:CollectibleCategory.sticker, description:'Drifting off between the stars.', currency:CollectibleCurrency.silver, price:80, rarity:'Common', icon:Icons.nights_stay_rounded, accent:Color(0xFFB6A0FF), animation:CollectibleAnimation.float),
  KuruCollectible(id:'kuru_reading', name:'Reading', category:CollectibleCategory.sticker, description:'One more chapter. Definitely.', currency:CollectibleCurrency.silver, price:100, rarity:'Common', icon:Icons.menu_book_rounded, accent:Color(0xFF9EDFCB), animation:CollectibleAnimation.float),
  KuruCollectible(id:'kuru_excited', name:'Excited', category:CollectibleCategory.sticker, description:'The whole galaxy is cheering.', currency:CollectibleCurrency.silver, price:100, rarity:'Common', icon:Icons.celebration_rounded, accent:Color(0xFFFFD166), animation:CollectibleAnimation.confetti),
  KuruCollectible(id:'kuru_thinking', name:'Thinking', category:CollectibleCategory.sticker, description:'Investigating the mysteries of space.', currency:CollectibleCurrency.silver, price:90, rarity:'Common', icon:Icons.psychology_rounded, accent:Color(0xFFB8A0FF), animation:CollectibleAnimation.pulse),
  KuruCollectible(id:'kuru_salute', name:'Salute', category:CollectibleCategory.sticker, description:'Always ready for the next adventure.', currency:CollectibleCurrency.achievement, price:0, rarity:'Uncommon', icon:Icons.waving_hand_rounded, accent:Color(0xFF8FEAFF, tier:CollectibleTier.contributor, unlockRule:'Earned by completing the first Kuro onboarding journey.'), animation:CollectibleAnimation.bounce),
  KuruCollectible(id:'kuru_bye_bye', name:'Bye Bye', category:CollectibleCategory.sticker, description:'See you on the next orbit.', currency:CollectibleCurrency.silver, price:80, rarity:'Common', icon:Icons.waving_hand_rounded, accent:Color(0xFFB6A0FF), animation:CollectibleAnimation.float),
  KuruCollectible(id:'kuru_clap', name:'Clap', category:CollectibleCategory.sticker, description:'A standing ovation from a tiny cat.', currency:CollectibleCurrency.achievement, price:0, rarity:'Common', icon:Icons.back_hand_rounded, accent:Color(0xFFFFB45E, tier:CollectibleTier.contributor, unlockRule:'Earned by helping test a Shop release and submitting useful feedback.'), animation:CollectibleAnimation.bounce),
  KuruCollectible(id:'kuru_hug', name:'Hug', category:CollectibleCategory.sticker, description:'A warm hug across the universe.', currency:CollectibleCurrency.silver, price:100, rarity:'Common', icon:Icons.volunteer_activism_rounded, accent:Color(0xFFFF80C8), animation:CollectibleAnimation.hearts),
  KuruCollectible(id:'kuru_cheer', name:'Cheer', category:CollectibleCategory.sticker, description:'You can do it. Kuru believes in you.', currency:CollectibleCurrency.achievement, price:0, rarity:'Uncommon', icon:Icons.emoji_events_rounded, accent:Color(0xFFFFD166, tier:CollectibleTier.contributor, unlockRule:'Earned by encouraging the Kuro community.'), animation:CollectibleAnimation.confetti),
  KuruCollectible(id:'kuru_wow', name:'Wow', category:CollectibleCategory.sticker, description:'A tiny face full of wonder.', currency:CollectibleCurrency.silver, price:90, rarity:'Common', icon:Icons.auto_awesome_rounded, accent:Color(0xFF8FEAFF), animation:CollectibleAnimation.pulse),
  KuruCollectible(id:'kuru_oops', name:'Oops', category:CollectibleCategory.sticker, description:'That was probably not supposed to happen.', currency:CollectibleCurrency.silver, price:90, rarity:'Common', icon:Icons.error_outline_rounded, accent:Color(0xFFFFB45E), animation:CollectibleAnimation.shake),
  KuruCollectible(id:'kuru_thank_you', name:'Thank You', category:CollectibleCategory.sticker, description:'A little thank-you from Kuru.', currency:CollectibleCurrency.achievement, price:0, rarity:'Common', icon:Icons.redeem_rounded, accent:Color(0xFFFF80C8, tier:CollectibleTier.contributor, unlockRule:'A thank-you reward for early community members.'), animation:CollectibleAnimation.hearts),
  KuruCollectible(id:'kuru_support', name:'Support', category:CollectibleCategory.sticker, description:'A tiny reminder that you are not alone.', currency:CollectibleCurrency.achievement, price:0, rarity:'Uncommon', icon:Icons.favorite_border_rounded, accent:Color(0xFFB6A0FF, tier:CollectibleTier.contributor, unlockRule:'Earned through a meaningful community contribution.'), animation:CollectibleAnimation.pulse),
  KuruCollectible(id:'kuru_creator_mode', name:'Creator Mode', category:CollectibleCategory.sticker, description:'Make something wonderful.', currency:CollectibleCurrency.gold, price:2, rarity:'Rare', icon:Icons.brush_rounded, accent:Color(0xFFC8A2FF), animation:CollectibleAnimation.orbit),
  KuruCollectible(id:'kuru_level_up', tier:CollectibleTier.premium, name:'Level Up!', category:CollectibleCategory.sticker, description:'A new level in your cosmic journey.', currency:CollectibleCurrency.gold, price:2, rarity:'Rare', icon:Icons.rocket_launch_rounded, accent:Color(0xFFFFD166), animation:CollectibleAnimation.confetti),
  KuruCollectible(id:'kuru_galaxy_mode', tier:CollectibleTier.premium, name:'Galaxy Mode', category:CollectibleCategory.sticker, description:'Kuru becomes one with the cosmos.', currency:CollectibleCurrency.gold, price:4, rarity:'Epic', icon:Icons.blur_circular_rounded, accent:Color(0xFFB68CFF), animation:CollectibleAnimation.orbit),
  KuruCollectible(id:'kuru_rich_kuru', tier:CollectibleTier.premium, name:'Rich Kuru', category:CollectibleCategory.sticker, description:'A glittering golden celebration.', currency:CollectibleCurrency.gold, price:3, rarity:'Epic', icon:Icons.paid_rounded, accent:Color(0xFFFFD166), animation:CollectibleAnimation.sparkle),
  KuruCollectible(id:'avatar_cosmic', name:'Cosmic Kuru', category:CollectibleCategory.avatar, description:'Your signature cosmic profile portrait.', currency:CollectibleCurrency.achievement, price:0, rarity:'Uncommon', icon:Icons.account_circle_rounded, accent:Color(0xFFB68CFF, tier:CollectibleTier.contributor, unlockRule:'Founding-user reward for an eligible early account.'), animation:CollectibleAnimation.orbit),
  KuruCollectible(id:'avatar_crown', tier:CollectibleTier.premium, name:'Royal Kuru', category:CollectibleCategory.avatar, description:'A crown for your cosmic achievements.', currency:CollectibleCurrency.gold, price:3, rarity:'Epic', icon:Icons.workspace_premium_rounded, accent:Color(0xFFFFD166), animation:CollectibleAnimation.sparkle),
  KuruCollectible(id:'avatar_sunglasses', tier:CollectibleTier.premium, name:'Cool Kuru', category:CollectibleCategory.avatar, description:'Cool, calm, and orbiting.', currency:CollectibleCurrency.silver, price:220, rarity:'Rare', icon:Icons.face_rounded, accent:Color(0xFF8FEAFF), animation:CollectibleAnimation.pulse),
  KuruCollectible(id:'avatar_halloween', name:'Pumpkin Kuru', category:CollectibleCategory.avatar, description:'A spooky seasonal portrait.', currency:CollectibleCurrency.achievement, price:0, rarity:'Seasonal', icon:Icons.celebration_rounded, accent:Color(0xFFFF9B54, tier:CollectibleTier.contributor, unlockRule:'Earned by completing a seasonal community event.'), animation:CollectibleAnimation.float, eventOnly:true),
  KuruCollectible(id:'season_new_year', name:'New Year Kuru', category:CollectibleCategory.seasonal, description:'Celebrate a new orbit around the sun.', currency:CollectibleCurrency.gold, price:2, rarity:'Seasonal', icon:Icons.celebration_rounded, accent:Color(0xFFFFD166), animation:CollectibleAnimation.confetti, eventOnly:true),
  KuruCollectible(id:'season_valentine', name:'Valentine Kuru', category:CollectibleCategory.seasonal, description:'A heart-shaped cosmic keepsake.', currency:CollectibleCurrency.gold, price:2, rarity:'Seasonal', icon:Icons.favorite_rounded, accent:Color(0xFFFF6EAB), animation:CollectibleAnimation.hearts, eventOnly:true),
  KuruCollectible(id:'season_spring', name:'Spring Kuru', category:CollectibleCategory.seasonal, description:'Petals drifting through the galaxy.', currency:CollectibleCurrency.gold, price:2, rarity:'Seasonal', icon:Icons.local_florist_rounded, accent:Color(0xFFFFA5D0), animation:CollectibleAnimation.float, eventOnly:true),
  KuruCollectible(id:'season_summer', name:'Summer Kuru', category:CollectibleCategory.seasonal, description:'Sunny days and beachside adventures.', currency:CollectibleCurrency.gold, price:2, rarity:'Seasonal', icon:Icons.wb_sunny_rounded, accent:Color(0xFFFFB45E), animation:CollectibleAnimation.bounce, eventOnly:true),
  KuruCollectible(id:'season_halloween', name:'Halloween Kuru', category:CollectibleCategory.seasonal, description:'A spooky little limited edition.', currency:CollectibleCurrency.gold, price:2, rarity:'Seasonal', icon:Icons.nightlight_round, accent:Color(0xFFFF8A4C), animation:CollectibleAnimation.float, eventOnly:true),
  KuruCollectible(id:'season_winter', name:'Winter Kuru', category:CollectibleCategory.seasonal, description:'A frosty friend from distant worlds.', currency:CollectibleCurrency.gold, price:2, rarity:'Seasonal', icon:Icons.ac_unit_rounded, accent:Color(0xFF8FEAFF), animation:CollectibleAnimation.sparkle, eventOnly:true),
  KuruCollectible(id:'season_anniversary', name:'Anniversary Kuru', category:CollectibleCategory.seasonal, description:'A keepsake for another year together.', currency:CollectibleCurrency.gold, price:4, rarity:'Legendary', icon:Icons.military_tech_rounded, accent:Color(0xFFFFD166), animation:CollectibleAnimation.confetti, eventOnly:true),
  KuruCollectible(id:'outfit_hoodie', name:'Signature Hoodie', category:CollectibleCategory.outfit, description:'Kuru’s classic cosmic hoodie.', currency:CollectibleCurrency.silver, price:250, rarity:'Uncommon', icon:Icons.checkroom_rounded, accent:Color(0xFFB68CFF), animation:CollectibleAnimation.float),
  KuruCollectible(id:'outfit_cape_flow', tier:CollectibleTier.premium, name:'Cape Flow', category:CollectibleCategory.outfit, description:'A trail of violet cosmic energy.', currency:CollectibleCurrency.gold, price:3, rarity:'Epic', icon:Icons.air_rounded, accent:Color(0xFFB68CFF), animation:CollectibleAnimation.orbit),
  KuruCollectible(id:'outfit_galaxy_aura', tier:CollectibleTier.premium, name:'Galaxy Aura', category:CollectibleCategory.outfit, description:'A little orbit of stardust around Kuru.', currency:CollectibleCurrency.gold, price:4, rarity:'Epic', icon:Icons.blur_on_rounded, accent:Color(0xFFB68CFF), animation:CollectibleAnimation.orbit),
  KuruCollectible(id:'outfit_paw_gloves', name:'Paw Gloves', category:CollectibleCategory.outfit, description:'Soft paws for cosmic adventures.', currency:CollectibleCurrency.silver, price:180, rarity:'Uncommon', icon:Icons.pets_rounded, accent:Color(0xFFFF80C8), animation:CollectibleAnimation.bounce),
  KuruCollectible(id:'outfit_creator_tablet', name:'Creator Tablet', category:CollectibleCategory.outfit, description:'Tools for the maker in you.', currency:CollectibleCurrency.gold, price:2, rarity:'Rare', icon:Icons.tablet_mac_rounded, accent:Color(0xFF8FEAFF), animation:CollectibleAnimation.pulse),
  KuruCollectible(id:'pose_wave', name:'Cosmic Wave', category:CollectibleCategory.pose, description:'A friendly wave from Kuru.', currency:CollectibleCurrency.achievement, price:0, rarity:'Common', icon:Icons.waving_hand_rounded, accent:Color(0xFF8FEAFF, tier:CollectibleTier.contributor, unlockRule:'Earned by reaching an early activity milestone.'), animation:CollectibleAnimation.bounce),
  KuruCollectible(id:'pose_star_pose', name:'Starlight Pose', category:CollectibleCategory.pose, description:'A little dramatic cosmic flourish.', currency:CollectibleCurrency.achievement, price:0, rarity:'Rare', icon:Icons.auto_awesome_rounded, accent:Color(0xFFB68CFF, tier:CollectibleTier.contributor, unlockRule:'Contributor recognition for accepted artwork or documentation.'), animation:CollectibleAnimation.sparkle),
  KuruCollectible(id:'expression_neutral', name:'Neutral', category:CollectibleCategory.expression, description:'Kuru’s everyday expression.', currency:CollectibleCurrency.achievement, price:0, rarity:'Common', icon:Icons.face_retouching_natural_rounded, accent:Color(0xFFB6A0FF, tier:CollectibleTier.contributor, unlockRule:'A community participation keepsake.'), animation:CollectibleAnimation.pulse),
  KuruCollectible(id:'character_baby_jobby', tier:CollectibleTier.premium, name:'Baby Jobby', category:CollectibleCategory.character, description:'A tiny companion for your collection.', currency:CollectibleCurrency.gold, price:3, rarity:'Epic', icon:Icons.child_care_rounded, accent:Color(0xFFFFD166), animation:CollectibleAnimation.bounce),
  KuruCollectible(id:'character_tiny_eren', tier:CollectibleTier.premium, name:'Tiny Eren', category:CollectibleCategory.character, description:'A mini character collectible.', currency:CollectibleCurrency.gold, price:3, rarity:'Epic', icon:Icons.face_rounded, accent:Color(0xFF8FEAFF), animation:CollectibleAnimation.pulse),
  KuruCollectible(id:'character_mini_gojo', tier:CollectibleTier.premium, name:'Mini Gojo', category:CollectibleCategory.character, description:'A mini character collectible.', currency:CollectibleCurrency.gold, price:3, rarity:'Epic', icon:Icons.visibility_rounded, accent:Color(0xFFB68CFF), animation:CollectibleAnimation.sparkle),
  KuruCollectible(id:'character_chibi_anya', tier:CollectibleTier.premium, name:'Chibi Anya', category:CollectibleCategory.character, description:'A mini character collectible.', currency:CollectibleCurrency.gold, price:3, rarity:'Epic', icon:Icons.face_3_rounded, accent:Color(0xFFFF80C8), animation:CollectibleAnimation.hearts),
  KuruCollectible(id:'top_aurora_kuru', name:'Aurora Kuru', category:CollectibleCategory.character, description:'A luminous aurora-themed Kuru design selected for exceptional visual impact.', currency:CollectibleCurrency.silver, price:360, rarity:'Rare', icon:Icons.auto_awesome_rounded, accent:Color(0xFF83EAF7), animation:CollectibleAnimation.sparkle, tier:CollectibleTier.topTen),
  KuruCollectible(id:'top_moonlit_kuru', name:'Moonlit Kuru', category:CollectibleCategory.character, description:'A quiet moonlit portrait with a soft celestial glow.', currency:CollectibleCurrency.gold, price:4, rarity:'Epic', icon:Icons.dark_mode_rounded, accent:Color(0xFFB6A0FF), animation:CollectibleAnimation.orbit, tier:CollectibleTier.topTen),
  KuruCollectible(id:'top_crystal_kuru', name:'Crystal Kuru', category:CollectibleCategory.character, description:'A prismatic crystal-inspired collectible with a brilliant finish.', currency:CollectibleCurrency.gold, price:4, rarity:'Epic', icon:Icons.diamond_rounded, accent:Color(0xFF8FEAFF), animation:CollectibleAnimation.sparkle, tier:CollectibleTier.topTen),
  KuruCollectible(id:'top_royal_kuru', name:'Royal Eclipse', category:CollectibleCategory.character, description:'A regal eclipse-inspired look for the most stylish collectors.', currency:CollectibleCurrency.gold, price:5, rarity:'Epic', icon:Icons.workspace_premium_rounded, accent:Color(0xFFFFD166), animation:CollectibleAnimation.confetti, tier:CollectibleTier.topTen),
  KuruCollectible(id:'top_starlight_kuru', name:'Starlight Kuru', category:CollectibleCategory.character, description:'A star-forged design with a radiant cosmic silhouette.', currency:CollectibleCurrency.gold, price:4, rarity:'Epic', icon:Icons.star_rounded, accent:Color(0xFFFFD166), animation:CollectibleAnimation.sparkle, tier:CollectibleTier.topTen),
  KuruCollectible(id:'top_void_kuru', name:'Voidwalker Kuru', category:CollectibleCategory.character, description:'A mysterious deep-space design with a violet aura.', currency:CollectibleCurrency.gold, price:5, rarity:'Epic', icon:Icons.blur_circular_rounded, accent:Color(0xFFB68CFF), animation:CollectibleAnimation.orbit, tier:CollectibleTier.topTen),
  KuruCollectible(id:'top_dream_kuru', name:'Dreamweaver Kuru', category:CollectibleCategory.character, description:'A dreamy pastel cosmic design made for the showcase shelf.', currency:CollectibleCurrency.gold, price:4, rarity:'Epic', icon:Icons.nights_stay_rounded, accent:Color(0xFFFF80C8), animation:CollectibleAnimation.float, tier:CollectibleTier.topTen),
  KuruCollectible(id:'top_comet_kuru', name:'Comet Trail Kuru', category:CollectibleCategory.character, description:'A dynamic comet-themed design with a trail of stardust.', currency:CollectibleCurrency.gold, price:4, rarity:'Epic', icon:Icons.rocket_launch_rounded, accent:Color(0xFF8FEAFF), animation:CollectibleAnimation.bounce, tier:CollectibleTier.topTen),
  KuruCollectible(id:'top_lunar_crown', name:'Lunar Crown', category:CollectibleCategory.character, description:'An elegant moon-crowned Kuru collectible.', currency:CollectibleCurrency.gold, price:5, rarity:'Epic', icon:Icons.brightness_3_rounded, accent:Color(0xFFC8A2FF), animation:CollectibleAnimation.orbit, tier:CollectibleTier.topTen),
  KuruCollectible(id:'top_prism_heart', name:'Prism Heart', category:CollectibleCategory.character, description:'A luminous heart-themed design with a spectrum-like accent.', currency:CollectibleCurrency.gold, price:4, rarity:'Epic', icon:Icons.favorite_rounded, accent:Color(0xFFFF6EAB), animation:CollectibleAnimation.hearts, tier:CollectibleTier.topTen),
  KuruCollectible(id:'character_akira', tier:CollectibleTier.premium, name:'Akira', category:CollectibleCategory.character, description:'A premium character collectible in the Kuro universe.', currency:CollectibleCurrency.gold, price:4, rarity:'Epic', icon:Icons.bolt_rounded, accent:Color(0xFFFF765F), animation:CollectibleAnimation.pulse),
  KuruCollectible(id:'legendary_progenitor', name:'Progenitor', category:CollectibleCategory.character, description:'The original Kuro. The origin point of the entire collection.', currency:CollectibleCurrency.achievement, price:0, rarity:'Legendary', icon:Icons.all_inclusive_rounded, accent:Color(0xFFFFD166), animation:CollectibleAnimation.orbit, tier:CollectibleTier.legendary, unlockRule:'Founding reward or administrator grant; never purchasable.'),
  KuruCollectible(id:'legendary_celestial', name:'Celestial', category:CollectibleCategory.character, description:'Kuro transcends the stars and becomes one with the cosmos.', currency:CollectibleCurrency.achievement, price:0, rarity:'Legendary', icon:Icons.flare_rounded, accent:Color(0xFF83EAF7), animation:CollectibleAnimation.sparkle, tier:CollectibleTier.legendary, unlockRule:'Complete the Celestial multi-step collection quest.'),
  KuruCollectible(id:'legendary_cute_kuro', name:'Cute Kuro', category:CollectibleCategory.character, description:'The secret, impossibly adorable legendary form of Kuro.', currency:CollectibleCurrency.achievement, price:0, rarity:'Legendary', icon:Icons.favorite_rounded, accent:Color(0xFFFF80C8), animation:CollectibleAnimation.hearts, tier:CollectibleTier.legendary, unlockRule:'Secret reward for completing the Kuro achievement sequence.'),
];

String collectibleTierLabel(CollectibleTier tier) => switch (tier) { CollectibleTier.standard => 'Standard', CollectibleTier.premium => 'Premium', CollectibleTier.topTen => 'Top 10', CollectibleTier.legendary => 'Legendary', CollectibleTier.contributor => 'Contributor' };

String collectibleCategoryLabel(CollectibleCategory category) => switch (category) {
  CollectibleCategory.sticker => 'Stickers',
  CollectibleCategory.avatar => 'Avatars',
  CollectibleCategory.seasonal => 'Seasonal',
  CollectibleCategory.outfit => 'Outfits',
  CollectibleCategory.pose => 'Poses',
  CollectibleCategory.expression => 'Expressions',
  CollectibleCategory.character => 'Characters',
};
