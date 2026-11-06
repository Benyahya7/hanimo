// Browse: the Animeify catalog. Series / Movies toggle, genre chips,
// poster grid, Load more. A failed load shows its error with Retry.
import 'package:flutter/material.dart';

import 'package:animeapp/data/animeify/animeify_repository.dart';
import 'package:animeapp/domain/anime.dart';
import 'package:animeapp/l10n/gen/app_localizations.dart';
import 'package:animeapp/presentation/screens/item_page.dart';
import 'package:animeapp/presentation/theme.dart';
import 'package:animeapp/presentation/widgets/anime_card.dart';

const _genres = ['', 'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy', 'Romance', 'Sci-Fi'];

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});

  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final _repo = AnimeifyRepository();
  String _type = ''; // '' = all, 'SERIES', 'MOVIE'
  String _genre = '';
  List<Anime> _items = [];
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  bool _hasMore = true;
  int _from = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _from = 0;
        _hasMore = true;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    final res = await _repo.getCatalog(type: _type, genre: _genre, from: _from);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadingMore = false;
      if (res.isOk) {
        final list = res.valueOrNull!;
        if (reset) {
          _items = list;
        } else {
          _items = [..._items, ...list];
        }
        _from += list.length;
        _hasMore = list.isNotEmpty;
        _error = null;
      } else {
        _error = res.errorOrNull;
        if (!reset) _hasMore = false;
      }
    });
  }

  String _genreLabel(BuildContext context, String g) {
    final l10n = AppLocalizations.of(context)!;
    return switch (g) {
      '' => l10n.all,
      'Action' => l10n.action,
      'Adventure' => l10n.adventure,
      'Comedy' => l10n.comedy,
      'Drama' => l10n.drama,
      'Fantasy' => l10n.fantasy,
      'Romance' => l10n.romance,
      'Sci-Fi' => l10n.sciFi,
      _ => g,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.browse)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<String>(
              style: SegmentedButton.styleFrom(selectedBackgroundColor: HanimoColors.violet, selectedForegroundColor: Colors.white),
              segments: [
                ButtonSegment(value: '', label: Text(l10n.all)),
                ButtonSegment(value: 'SERIES', label: Text(l10n.series)),
                ButtonSegment(value: 'MOVIE', label: Text(l10n.movies)),
              ],
              selected: {_type},
              onSelectionChanged: (s) {
                setState(() => _type = s.first);
                _load(reset: true);
              },
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final g in _genres)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(_genreLabel(context, g)),
                      selectedColor: HanimoColors.violet,
                      selected: _genre == g,
                      onSelected: (_) {
                        setState(() => _genre = g);
                        _load(reset: true);
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _items.isEmpty
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
                              FilledButton(onPressed: () => _load(reset: true), child: Text(l10n.retry)),
                            ],
                          ),
                        ),
                      )
                    : _items.isEmpty
                        ? Center(child: Text(l10n.noResults))
                        : GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              childAspectRatio: 0.52,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: _items.length + (_hasMore ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i == _items.length) {
                                return Center(
                                  child: _loadingMore
                                      ? const CircularProgressIndicator()
                                      : FilledButton.tonal(onPressed: () => _load(reset: false), child: Text(l10n.loadMore)),
                                );
                              }
                              final anime = _items[i];
                              return AnimeCard(
                                anime: anime,
                                width: double.infinity,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(builder: (_) => ItemPage(anime: anime)),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
