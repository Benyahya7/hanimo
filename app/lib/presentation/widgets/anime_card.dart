// Shared poster cards. One place, one look — every list uses these.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:animeapp/domain/anime.dart';
import 'package:animeapp/presentation/theme.dart';



/// Poster + title + score. Used in horizontal rows.
class AnimeCard extends StatelessWidget {
  final Anime anime;
  final VoidCallback onTap;
  final double width;
  const AnimeCard({super.key, required this.anime, required this.onTap, this.width = 120});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: anime.imageUrl.isEmpty
                    ? Container(color: HanimoColors.card, child: const Icon(Icons.image, color: Colors.white54))
                    : CachedNetworkImage(
                        imageUrl: anime.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: HanimoColors.card),
                        errorWidget: (_, _, _) => Container(color: HanimoColors.card, child: const Icon(Icons.broken_image, color: Colors.white54)),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(anime.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            if (anime.score > 0)
              Row(
                children: [
                  const Icon(Icons.star, size: 13, color: HanimoColors.gold),
                  const SizedBox(width: 3),
                  Text(anime.score.toStringAsFixed(1), style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Numbered Top-10 card (Trending Now).
class TrendingCard extends StatelessWidget {
  final Anime anime;
  final int rank;
  final VoidCallback onTap;
  const TrendingCard({super.key, required this.anime, required this.rank, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 160,
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const SizedBox(width: 34),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SizedBox(
                    width: 120,
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: anime.imageUrl.isEmpty
                          ? Container(color: HanimoColors.card)
                          : CachedNetworkImage(
                              imageUrl: anime.imageUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => Container(color: HanimoColors.card),
                              errorWidget: (_, _, _) => Container(color: HanimoColors.card),
                            ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              left: 0,
              bottom: -14,
              child: Text(
                '$rank',
                style: const TextStyle(fontSize: 96, fontWeight: FontWeight.w900, color: HanimoColors.pink, height: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Latest-episode card: poster with an "Ep N" badge.
class EpisodeCard extends StatelessWidget {
  final Anime anime;
  final Episode episode;
  final VoidCallback onTap;
  const EpisodeCard({super.key, required this.anime, required this.episode, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    anime.imageUrl.isEmpty
                        ? Container(color: HanimoColors.card)
                        : CachedNetworkImage(
                            imageUrl: anime.imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Container(color: HanimoColors.card),
                            errorWidget: (_, _, _) => Container(color: HanimoColors.card),
                          ),
                    Positioned(right: 6, bottom: 6, child: GradientPill(label: 'Ep ${episode.number}')),
                  ],
                ),
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

/// A horizontal row with a title header. Shows an error card + Retry when
/// the section failed to load, instead of an empty gap.
class SectionRow extends StatelessWidget {
  final String title;
  final Widget child;
  final String? error;
  final VoidCallback? onRetry;
  const SectionRow({super.key, required this.title, required this.child, this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _ErrorCard(message: error!, onRetry: onRetry),
          )
        else
          child,
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _ErrorCard({required this.message, this.onRetry});

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
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('Retry', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }
}
