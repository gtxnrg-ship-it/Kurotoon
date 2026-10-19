import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kurotoon_core/kurotoon_core.dart';
import 'package:kurotoon_flutter/runtime.dart';
import 'package:kurotoon_flutter/storage/kurotoon_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory temp;
  KurotoonRuntime? runtime;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kurotoon-runtime-persistence-test-');
    runtime = null;
  });

  tearDown(() async {
    final activeRuntime = runtime;
    if (activeRuntime != null) await activeRuntime.dispose();
    await temp.delete(recursive: true);
  });

  test('restores persisted provider cooldown after runtime restart', () async {
    final databasePath = p.join(temp.path, 'kurotoon.db');
    final database = await KurotoonDatabase.open(
      databasePath: databasePath,
      factory: databaseFactoryFfi,
    );
    final seedTracker = ProviderHealthTracker();
    seedTracker.record(
      'mangadex',
      const ProviderResponse(
        status: ProviderResultStatus.rateLimited,
        message: 'do not persist this message',
        retryAfter: Duration(minutes: 10),
      ),
    );
    await database.setSetting(
      'provider.health.mangadex',
      seedTracker.snapshotFor('mangadex').toJson(),
    );
    await database.close();

    runtime = await KurotoonRuntime.initialize(databasePath: databasePath);
    final restored = runtime!.providerHealth.snapshotFor('mangadex');
    expect(restored.state, ProviderHealthState.coolingDown);
    expect(restored.consecutiveFailures, 1);
    expect(restored.lastStatus, ProviderResultStatus.rateLimited);
    expect(restored.lastMessage, isNull);
    expect(runtime!.providerHealth.remainingCooldown('mangadex'), isNotNull);
  });
}
