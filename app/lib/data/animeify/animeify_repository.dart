// The typed API the UI uses. Every method returns a Result — an empty
// list from a live server is NOT an error (the catalog can legitimately
// be empty for a filter), a failed/empty response IS, with a message.
import 'package:animeapp/core/result.dart';
import 'package:animeapp/domain/anime.dart';

import 'animeify_api.dart';

const _serverDown = 'Animeify did not answer. Check your connection and try again.';
const _noResults = 'Nothing found on Animeify for that.';

class AnimeifyRepository {
  final AnimeifyApi api;
  AnimeifyRepository({AnimeifyApi? api}) : api = api ?? AnimeifyApi();

  Anime _toDomain(AnimeifyAnime a) => Anime(
        id: a.animeId,
        title: a.title,
        imageUrl: a.thumbnailUrl,
        score: a.score,
        year: a.year,
        genres: a.genres,
        episodeCount: a.episodeCount,
        type: a.type,
        malId: a.malId,
        trailerUrl: a.trailerUrl,
      );

  Future<Result<HomeFeed>> getHome() async {
    try {
      final home = await api.fetchHome();
      final trending = await api.fetchTrending();
      final trendingAnime = trending.map((t) => t.anime).whereType<AnimeifyAnime>().map(_toDomain).toList();
      final feed = HomeFeed(
        latestAnime: home.latestAnime.map(_toDomain).toList(),
        latestEpisodes: home.latestEpisodes.map((r) => (_toDomain(r.$1), Episode(r.$2.number))).toList(),
        broadcast: home.broadcast.map(_toDomain).toList(),
        premiere: home.premiere.map(_toDomain).toList(),
      );
      if (feed.latestAnime.isEmpty && feed.latestEpisodes.isEmpty && feed.broadcast.isEmpty && feed.premiere.isEmpty && trendingAnime.isEmpty) {
        return const Err(_serverDown);
      }
      return Result.ok(feed);
    } catch (e) {
      return Err('Could not load the home feed: $e');
    }
  }

  Future<Result<List<Anime>>> getTrending() async {
    try {
      final items = await api.fetchTrending();
      final list = items.map((t) => t.anime).whereType<AnimeifyAnime>().map(_toDomain).toList();
      if (list.isEmpty) return const Err(_serverDown);
      return Result.ok(list);
    } catch (e) {
      return Err('Could not load trending: $e');
    }
  }

  Future<Result<List<Anime>>> getCatalog({String type = '', String genre = '', int from = 0}) async {
    try {
      final list = await api.fetchCatalog(
        filterType: genre.isEmpty ? '' : 'GENRE',
        filterData: genre,
        type: type,
        from: from,
      );
      if (list.isEmpty) {
        return from == 0 ? const Err(_noResults) : const Ok(<Anime>[]);
      }
      return Result.ok(list.map(_toDomain).toList());
    } catch (e) {
      return Err('Could not load the catalog: $e');
    }
  }

  Future<Result<List<Anime>>> search(String query) async {
    try {
      final list = await api.search(query);
      if (list.isEmpty) return const Err(_noResults);
      return Result.ok(list.map(_toDomain).toList());
    } catch (e) {
      return Err('Search failed: $e');
    }
  }

  Future<Result<List<Episode>>> getEpisodes(String animeId) async {
    try {
      final eps = await api.fetchEpisodes(animeId);
      if (eps.isEmpty) return const Err('No episodes listed on Animeify for this title yet.');
      return Result.ok(eps.map((e) => Episode(e.number)).toList());
    } catch (e) {
      return Err('Could not load episodes: $e');
    }
  }

  Future<Result<List<Server>>> getServers({required String animeId, required int episode, required String animeType}) async {
    try {
      final servers = await api.fetchServers(animeId: animeId, episode: episode, animeType: animeType);
      final ep = servers?.current;
      if (ep == null) return const Err('No servers listed on Animeify for this episode yet.');
      final rows = serversForEpisode(ep);
      if (rows.isEmpty) return const Err('No servers listed on Animeify for this episode yet.');
      return Result.ok(rows
          .map((s) => Server(host: s.host, quality: s.quality, id: s.id, kind: s.kind))
          .toList());
    } catch (e) {
      return Err('Could not load servers: $e');
    }
  }

  /// Resolve one server row to a playable URL (or null + a message).
  Future<Result<String>> resolveServer(Server server, {String fileName = ''}) async {
    try {
      final row = AnimeifyServer(host: server.host, quality: server.quality, id: server.id, kind: server.kind);
      final url = await api.resolveServer(row, fileName: fileName);
      if (url == null || url.isEmpty) {
        return Err('${server.host} could not give a playable link right now — try another server.');
      }
      return Result.ok(url);
    } catch (e) {
      return Err('Could not open ${server.host}: $e');
    }
  }

  Future<Result<Anime>> getDetails(Anime anime) async {
    try {
      final details = await api.fetchDetails(anime.id);
      return Result.ok(anime.copyWith(description: details.plot));
    } catch (e) {
      return Result.ok(anime); // details are a bonus, never a failure
    }
  }

  Future<Result<List<Anime>>> getRelated(Anime anime) async {
    try {
      final details = await api.fetchDetails(anime.id);
      if (details.related.isEmpty) return const Ok(<Anime>[]);
      return Result.ok(details.related.map(_toDomain).toList());
    } catch (e) {
      return const Ok(<Anime>[]);
    }
  }
}
