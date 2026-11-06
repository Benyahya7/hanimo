// Item detail: poster, score/year/genres, plot (from Animeify details),
// episodes (Animeify), servers sheet per episode, favourite + share.
// A failed episode load shows its error with Retry — never a dead tap.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:animeapp/data/animeify/animeify_repository.dart';
import 'package:animeapp/domain/anime.dart';
import 'package:animeapp/l10n/gen/app_localizations.dart';
import 'package:animeapp/presentation/app_state.dart';
import 'package:animeapp/presentation/widgets/servers_sheet.dart';
import 'package:animeapp/presentation/theme.dart';

class ItemPage extends StatefulWidget {
  final Anime anime;
  const ItemPage({super.key, required this.anime});

  @override
  State<ItemPage> createState() => _ItemPageState();
}

class _ItemPageState extends State<ItemPage> {
  final _repo = AnimeifyRepository();
  Anime? _anime;
  List<Episode> _episodes = [];
  bool _episodesLoading = false;
  String? _episodesError;
  List<Anime> _related = [];
  bool _detailsLoaded = false;

  Anime get anime => _anime ?? widget.anime;

  @override
  void initState() {
    super.initState();
    _anime = widget.anime;
    _loadEpisodes();
    _loadDetails();
  }

  Future<void> _loadEpisodes() async {
    setState(() {
      _episodesLoading = true;
      _episodesError = null;
    });
    final res = await _repo.getEpisodes(widget.anime.id);
    if (!mounted) return;
    setState(() {
      _episodesLoading = false;
      if (res.isOk) {
        _episodes = res.valueOrNull!;
        _episodesError = null;
      } else {
        _episodes = [];
        _episodesError = res.errorOrNull;
      }
    });
  }

  Future<void> _loadDetails() async {
    final res = await _repo.getDetails(widget.anime);
    final rel = await _repo.getRelated(widget.anime);
    if (!mounted) return;
    setState(() {
      if (res.isOk) _anime = res.valueOrNull;
      if (rel.isOk) _related = rel.valueOrNull!;
      _detailsLoaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final d = context.watch<AppState>();
    final a = anime;
    final fav = d.isFavourite(a.id);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              background: a.imageUrl.isEmpty
                  ? Container(color: HanimoColors.card)
                  : CachedNetworkImage(
                      imageUrl: a.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(color: HanimoColors.card),
                      errorWidget: (_, _, _) => Container(color: HanimoColors.card),
                    ),
            ),
            actions: [
              IconButton(
                icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? Colors.red : null),
                onPressed: () => d.toggleFavourite(a),
                tooltip: l10n.favourites,
              ),
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () => SharePlus.instance.share(ShareParams(text: 'Watch ${a.title} on Hanimo')),
                tooltip: 'Share',
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (a.score > 0) _Chip(Icons.star, a.score.toStringAsFixed(1)),
                      if (a.year > 0) _Chip(Icons.calendar_today, '${a.year}'),
                      _Chip(Icons.movie, a.isMovie ? l10n.movies : l10n.series),
                      if (a.episodeCount > 0) _Chip(Icons.list, l10n.episodesCount(a.episodeCount)),
                    ],
                  ),
                  if (a.genres.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      children: [for (final g in a.genres) Chip(label: Text(g), visualDensity: VisualDensity.compact)],
                    ),
                  ],
                  const SizedBox(height: 12),
                  if (a.description.isNotEmpty)
                    Text(a.description, style: const TextStyle(fontSize: 14, height: 1.5))
                  else if (!_detailsLoaded)
                    const Text('…', style: TextStyle(color: Colors.white54)),
                  if (a.trailerUrl.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => launchUrl(Uri.parse(a.trailerUrl), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Trailer'),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: GradientButton(
                          onPressed: () {
                            if (a.isMovie) {
                              showServersSheet(context, anime: a, episodeNumber: 1);
                            } else if (_episodes.isNotEmpty) {
                              showServersSheet(context, anime: a, episodeNumber: _episodes.first.number);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(_episodesError ?? l10n.noResults)),
                              );
                            }
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [const Icon(Icons.play_arrow, color: Colors.white), const SizedBox(width: 8), Text(l10n.watch)],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(l10n.episodes, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (_episodesLoading)
                    const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                  else if (_episodesError != null)
                    _InlineError(message: _episodesError!, onRetry: _loadEpisodes, l10n: l10n)
                  else if (_episodes.isEmpty)
                    Text(l10n.noResults, style: const TextStyle(color: Colors.white54))
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _episodes.length,
                      itemBuilder: (_, i) {
                        final ep = _episodes[i];
                        return ListTile(
                          leading: CircleAvatar(child: Text('${ep.number}')),
                          title: Text('${l10n.episodes} ${ep.number}'),
                          trailing: const Icon(Icons.play_circle_fill, color: HanimoColors.pink),
                          onTap: () => showServersSheet(context, anime: a, episodeNumber: ep.number),
                        );
                      },
                    ),
                  if (_related.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(l10n.relatedTitles, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 210,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _related.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (_, i) => _RelatedCard(
                          anime: _related[i],
                          onTap: () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(builder: (_) => ItemPage(anime: _related[i])),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: HanimoColors.card, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final AppLocalizations l10n;
  const _InlineError({required this.message, required this.onRetry, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF2A1A1A), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
          TextButton(onPressed: onRetry, child: Text(l10n.retry, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
  }
}

class _RelatedCard extends StatelessWidget {
  final Anime anime;
  final VoidCallback onTap;
  const _RelatedCard({required this.anime, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 120,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: anime.imageUrl.isEmpty
                    ? Container(color: HanimoColors.card)
                    : CachedNetworkImage(imageUrl: anime.imageUrl, fit: BoxFit.cover, errorWidget: (_, _, _) => Container(color: HanimoColors.card)),
              ),
            ),
            const SizedBox(height: 6),
            Text(anime.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
