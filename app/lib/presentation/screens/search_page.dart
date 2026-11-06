// Search: live Animeify search (debounced, >2 characters), results first,
// with the owner's Firestore library underneath as local matches.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:animeapp/data/animeify/animeify_repository.dart';
import 'package:animeapp/domain/anime.dart';
import 'package:animeapp/l10n/gen/app_localizations.dart';
import 'package:animeapp/presentation/app_state.dart';
import 'package:animeapp/presentation/screens/item_page.dart';
import 'package:animeapp/presentation/theme.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _repo = AnimeifyRepository();
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Anime> _results = [];
  bool _searching = false;
  String? _error;
  bool _searched = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length <= 2) {
      setState(() {
        _results = [];
        _error = null;
        _searched = false;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _run(q));
  }

  Future<void> _run(String q) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    final res = await _repo.search(q);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _searched = true;
      if (res.isOk) {
        _results = res.valueOrNull!;
        _error = null;
      } else {
        _results = [];
        _error = res.errorOrNull;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final d = context.watch<AppState>();
    final local = _controller.text.trim().isEmpty
        ? <CatalogItem>[]
        : d.items.where((i) => i.title.toLowerCase().contains(_controller.text.trim().toLowerCase())).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.search)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      ),
              ),
              onChanged: _onChanged,
            ),
          ),
          if (_searching) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: () => _run(_controller.text), child: Text(l10n.retry)),
                        ],
                      ),
                    ),
                  )
                : _results.isEmpty && local.isEmpty
                    ? Center(child: Text(_searched ? l10n.noResults : l10n.searchHint))
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: [
                          for (final anime in _results)
                            ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 44,
                                  height: 66,
                                  child: anime.imageUrl.isEmpty
                                      ? Container(color: HanimoColors.card)
                                      : Image.network(anime.imageUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => Container(color: HanimoColors.card)),
                                ),
                              ),
                              title: Text(anime.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                [
                                  if (anime.score > 0) '★ ${anime.score.toStringAsFixed(1)}',
                                  if (anime.year > 0) '${anime.year}',
                                  anime.isMovie ? l10n.movies : l10n.series,
                                ].join('  ·  '),
                              ),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ItemPage(anime: anime))),
                            ),
                          if (local.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(l10n.myList, style: const TextStyle(fontWeight: FontWeight.bold)),
                            for (final item in local)
                              ListTile(
                                title: Text(item.title),
                                subtitle: Text(item.animeifyId.isEmpty ? item.type : 'Animeify'),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => ItemPage(
                                      anime: Anime(id: item.animeifyId, title: item.title, imageUrl: item.imageUrl, type: item.type),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}
