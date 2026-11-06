// Home: hero carousel, update banner, and the Animeify lists —
// Trending Now, Latest Episodes, Latest Updates, Airing Today, This Season.
// A failed load shows its error with Retry, never an empty gap.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:animeapp/app_constants.dart';
import 'package:animeapp/data/animeify/animeify_api.dart';
import 'package:animeapp/domain/anime.dart';
import 'package:animeapp/l10n/gen/app_localizations.dart';
import 'package:animeapp/presentation/app_state.dart';
import 'package:animeapp/presentation/screens/item_page.dart';
import 'package:animeapp/presentation/widgets/anime_card.dart';
import 'package:animeapp/presentation/theme.dart';

const _banners = [
  'assets/banners/hero.webp',
  'assets/banners/series.webp',
  'assets/banners/movie.webp',
  'assets/banners/fantasy.webp',
  'assets/banners/cyberpunk.webp',
];

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  void _openAnime(BuildContext context, Anime anime) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ItemPage(anime: anime)));
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<AppState>();
    final l10n = AppLocalizations.of(context)!;
    final feed = d.homeFeed;
    final today = animeifyTodayBroadcast();
    final todayLabel = today[0] + today.substring(1).toLowerCase();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/icon/hanimo-icon.png', width: 28, height: 28),
            const SizedBox(width: 8),
            const Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'HANIMO', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white)),
                  TextSpan(text: '.', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2, color: HanimoColors.pink)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none),
            onPressed: () => Navigator.of(context).pushNamed('/updates'),
            tooltip: l10n.updates,
          ),
        ],
      ),
      body: d.homeLoading && feed.latestAnime.isEmpty && feed.latestEpisodes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => d.refreshHome(),
              child: ListView(
                children: [
                  if (d.hasUpdate) _UpdateBanner(d: d, l10n: l10n),
                  _HeroCarousel(onTap: () {}),
                  if (d.homeError != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: _HomeErrorCard(message: d.homeError!, onRetry: () => d.refreshHome(), l10n: l10n),
                    ),
                  if (d.trendingAnime.isNotEmpty)
                    SectionRow(
                      title: l10n.trending,
                      child: SizedBox(
                        height: 210,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: d.trendingAnime.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (_, i) => TrendingCard(
                            anime: d.trendingAnime[i],
                            rank: i + 1,
                            onTap: () => _openAnime(context, d.trendingAnime[i]),
                          ),
                        ),
                      ),
                    ),
                  if (feed.latestEpisodes.isNotEmpty)
                    SectionRow(
                      title: l10n.latestEpisodes,
                      child: SizedBox(
                        height: 150,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: feed.latestEpisodes.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (_, i) {
                            final (anime, episode) = feed.latestEpisodes[i];
                            return EpisodeCard(anime: anime, episode: episode, onTap: () => _openAnime(context, anime));
                          },
                        ),
                      ),
                    ),
                  if (feed.latestAnime.isNotEmpty)
                    SectionRow(
                      title: l10n.latestUpdates,
                      child: SizedBox(
                        height: 210,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: feed.latestAnime.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (_, i) => AnimeCard(anime: feed.latestAnime[i], onTap: () => _openAnime(context, feed.latestAnime[i])),
                        ),
                      ),
                    ),
                  if (feed.broadcast.isNotEmpty)
                    SectionRow(
                      title: '${l10n.airingToday} ($todayLabel)',
                      child: SizedBox(
                        height: 210,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: feed.broadcast.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (_, i) => AnimeCard(anime: feed.broadcast[i], onTap: () => _openAnime(context, feed.broadcast[i])),
                        ),
                      ),
                    ),
                  if (feed.premiere.isNotEmpty)
                    SectionRow(
                      title: '${l10n.thisSeason} (${animeifyCurrentSeason()})',
                      child: SizedBox(
                        height: 210,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: feed.premiere.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (_, i) => AnimeCard(anime: feed.premiere[i], onTap: () => _openAnime(context, feed.premiere[i])),
                        ),
                      ),
                    ),
                  if (d.progress.isNotEmpty)
                    SectionRow(
                      title: l10n.continueWatching,
                      child: SizedBox(
                        height: 150,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: d.progress.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (_, i) {
                            final id = d.progress.keys.elementAt(i);
                            final anime = Anime(id: id, title: d.progressTitles[id] ?? id, imageUrl: '');
                            return EpisodeCard(
                              anime: anime,
                              episode: const Episode(1),
                              onTap: () => _openAnime(context, anime),
                            );
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _HeroCarousel extends StatefulWidget {
  final VoidCallback onTap;
  const _HeroCarousel({required this.onTap});

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 210,
          child: Stack(
            children: [
              PageView.builder(
            controller: _controller,
            itemCount: _banners.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => GestureDetector(
              onTap: widget.onTap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(_banners[i], fit: BoxFit.cover),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.9)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
              Positioned(
                bottom: 10,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _banners.length; i++)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: i == _page ? HanimoColors.pink : Colors.white54),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  final AppState d;
  final AppLocalizations l10n;
  const _UpdateBanner({required this.d, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(gradient: HanimoGradients.brand, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Icon(Icons.system_update, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Hanimo ${d.latestVersionName.isEmpty ? '2.0' : d.latestVersionName} is out (build ${d.latestBuild}, you have $kCurrentBuild)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () async {
              if (d.updateDownloadUrl.isEmpty) return;
              await launchUrl(Uri.parse(d.updateDownloadUrl), mode: LaunchMode.externalApplication);
            },
            child: const Text('Update', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

class _HomeErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final AppLocalizations l10n;
  const _HomeErrorCard({required this.message, required this.onRetry, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFF2A1A1A), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade900)),
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
