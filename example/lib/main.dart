// Minimal example: index a few notes and search them on-device using the
// TextIndex convenience (BM25 lexical search; pass a modelDir for hybrid).
// The "group by topic" switch shows queryGroups: one entry per topic instead of
// every matching note.

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qdrant_edge_flutter/qdrant_edge_flutter.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(home: SearchPage());
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  TextIndex? _index;
  final _controller = TextEditingController(text: 'fox');
  List<Map<String, dynamic>> _hits = [];
  bool _grouped = false;
  String _status = 'opening...';

  // (topic, text) — the topic is stored as payload so we can group on it.
  static const _seed = <(String, String)>[
    ('animals', 'the quick brown fox jumps over the lazy dog'),
    ('animals', 'a fast auburn fox leaps above a sleepy hound'),
    ('animals', 'the red fox hunts mice in the winter field'),
    ('finance', 'stock markets rallied on strong earnings reports'),
    ('finance', 'the central bank held interest rates steady'),
    ('science', 'photosynthesis converts sunlight into chemical energy'),
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final dir = await getApplicationDocumentsDirectory();
    final index = QdrantEdge().openTextIndex('${dir.path}/notes_db_v2');
    if (index.count() == 0) {
      for (var i = 0; i < _seed.length; i++) {
        final (topic, text) = _seed[i];
        index.add(i + 1, text, payload: {'text': text, 'topic': topic});
      }
      index.flush();
      // Grouping and ordered scroll read the field through its payload index.
      index.shard.createFieldIndex('topic', 'keyword');
    }
    setState(() {
      _index = index;
      _status = '${index.count()} documents indexed';
    });
    _runSearch();
  }

  void _runSearch() {
    final index = _index;
    if (index == null) return;
    final query = _controller.text;
    setState(() {
      if (!_grouped) {
        _hits = index.search(query, limit: 5);
        return;
      }
      // One line per topic: the group key plus its best hit.
      _hits = index
          .searchGroups(query, groupBy: 'topic', limit: 5, groupSize: 3)
          .map((g) {
        final hits = (g['hits'] as List).cast<Map<String, dynamic>>();
        return {...hits.first, 'group': g['key'], 'groupSize': hits.length};
      }).toList();
    });
  }

  @override
  void dispose() {
    _index?.close();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('qdrant-edge on-device search')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: (_) => _runSearch(),
                    decoration: const InputDecoration(
                      labelText: 'Search',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _runSearch, child: const Text('Go')),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Group by topic'),
              value: _grouped,
              onChanged: (v) {
                setState(() => _grouped = v);
                _runSearch();
              },
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _hits.length,
                itemBuilder: (_, i) {
                  final h = _hits[i];
                  final score = (h['score'] as num?)?.toDouble() ?? 0;
                  final payload = h['payload'] as Map?;
                  final group = h['group'];
                  return ListTile(
                    leading: CircleAvatar(child: Text('${h['id']}')),
                    title: Text(payload?['text']?.toString() ?? '(no text)'),
                    subtitle: Text(group == null
                        ? 'score: ${score.toStringAsFixed(4)}'
                        : '$group · ${h['groupSize']} hit(s) · '
                            'score: ${score.toStringAsFixed(4)}'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
