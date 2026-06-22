// Minimal example: index a few notes and search them on-device.
//
// Run from the example/ directory after building the native library:
//   sh ../scripts/build-ios.sh      (or build-android.sh)
//   flutter run

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
  QdrantEdge? _db;
  final _controller = TextEditingController(text: 'brown fox');
  List<QdrantHit> _hits = [];
  String _status = 'opening...';

  static const _seed = <String>[
    'the quick brown fox jumps over the lazy dog',
    'a fast auburn fox leaps above a sleepy hound',
    'stock markets rallied on strong earnings reports',
    'the central bank held interest rates steady',
    'photosynthesis converts sunlight into chemical energy',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final dir = await getApplicationDocumentsDirectory();
    final db = QdrantEdge.open('${dir.path}/notes_db');
    if (db.count() == 0) {
      for (var i = 0; i < _seed.length; i++) {
        db.add(i + 1, _seed[i], payload: {'text': _seed[i]});
      }
      db.flush();
    }
    setState(() {
      _db = db;
      _status = '${db.count()} documents indexed';
    });
    _runSearch();
  }

  void _runSearch() {
    final db = _db;
    if (db == null) return;
    setState(() => _hits = db.search(_controller.text, limit: 5));
  }

  @override
  void dispose() {
    _db?.close();
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
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _hits.length,
                itemBuilder: (_, i) {
                  final h = _hits[i];
                  return ListTile(
                    leading: CircleAvatar(child: Text('${h.id}')),
                    title: Text(h.payload?['text']?.toString() ?? '(no text)'),
                    subtitle: Text('score: ${h.score.toStringAsFixed(4)}'),
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
