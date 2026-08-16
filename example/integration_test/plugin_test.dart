// End-to-end test of the plugin against the real native engine on the device
// under test. Covers the 0.2.0 surface: grouped queries, search matrix, search
// params, ordered scroll, text filters, and payload schema reporting.
//
//   flutter test integration_test/plugin_test.dart -d macos

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qdrant_edge_flutter/qdrant_edge_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late QdrantEdge client;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('qe_test_');
    client = QdrantEdge();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  // (topic, text) fixtures; topic doubles as the grouping key.
  const seed = <(String, String)>[
    ('animals', 'the quick brown fox jumps over the lazy dog'),
    ('animals', 'a fast auburn fox leaps above a sleepy hound'),
    ('animals', 'the red fox hunts mice in the winter field'),
    ('finance', 'stock markets rallied on strong earnings reports'),
    ('finance', 'the central bank held interest rates steady'),
    ('science', 'photosynthesis converts sunlight into chemical energy'),
  ];

  TextIndex openSeeded() {
    final index = client.openTextIndex('${dir.path}/notes');
    for (var i = 0; i < seed.length; i++) {
      final (topic, text) = seed[i];
      index.add(i + 1, text,
          payload: {'text': text, 'topic': topic, 'rank': i + 1});
    }
    index.flush();
    return index;
  }

  test('text search returns the matching notes', () {
    final index = openSeeded();
    addTearDown(index.close);

    final hits = index.search('fox', limit: 5);
    expect(hits, isNotEmpty);
    expect(
      hits.map((h) => (h['payload'] as Map)['topic']),
      everyElement('animals'),
    );
  });

  test('searchGroups collapses hits by payload field', () {
    final index = openSeeded();
    addTearDown(index.close);

    final groups =
        index.searchGroups('fox rates energy', groupBy: 'topic', limit: 5);
    expect(groups.map((g) => g['key']).toSet(),
        containsAll(<String>['animals', 'finance']));
    for (final g in groups) {
      final hits = (g['hits'] as List).cast<Map<String, dynamic>>();
      expect(hits, isNotEmpty);
      expect(hits.length, lessThanOrEqualTo(3)); // default group_size
      expect(hits.first['payload'], isNotNull);
    }
  });

  test('searchMatrix samples points and returns neighbours', () {
    final index = openSeeded();
    addTearDown(index.close);

    final m = index.shard
        .searchMatrix({'sample': seed.length, 'limit': 2, 'using': 'bm25'});
    final sampleIds = m['sample_ids'] as List;
    final nearests = m['nearests'] as List;
    expect(sampleIds, isNotEmpty);
    expect(nearests.length, sampleIds.length);
  });

  test('search params, text filters, ordered scroll and payload schema', () {
    final index = openSeeded();
    addTearDown(index.close);
    final shard = index.shard;
    shard.createFieldIndex('topic', 'keyword');
    shard.createFieldIndex('rank', 'integer');
    shard.createFieldIndex('text', {
      'type': 'text',
      'tokenizer': 'word',
      'phrase_matching': true,
    });

    // params are accepted and do not change a correct result
    final tuned = index.search('fox', limit: 3, params: {'hnsw_ef': 64});
    expect(tuned, isNotEmpty);

    // prefix on a keyword field
    expect(
      shard.count(filter: {
        'must': [
          {
            'key': 'topic',
            'match': {'prefix': 'anim'}
          },
        ],
      }),
      3,
    );

    // phrase: "brown fox" adjacent, not just both words present
    final phrase = shard.scroll({
      'filter': {
        'must': [
          {
            'key': 'text',
            'match': {'phrase': 'brown fox'}
          },
        ],
      },
      'with_payload': true,
    });
    expect((phrase['points'] as List), hasLength(1));

    // scroll ordered by an indexed field, descending
    final ordered = shard.scroll({
      'order_by': {'key': 'rank', 'direction': 'desc'},
      'limit': 3,
      'with_payload': true,
    });
    final ranks = (ordered['points'] as List)
        .map((p) => (p['payload'] as Map)['rank'] as int)
        .toList();
    expect(ranks, [seed.length, seed.length - 1, seed.length - 2]);

    // info() reports which payload fields are indexed
    final schema = shard.info()['payload_schema'] as Map;
    expect(schema.keys, containsAll(<String>['topic', 'rank', 'text']));
  });
}
