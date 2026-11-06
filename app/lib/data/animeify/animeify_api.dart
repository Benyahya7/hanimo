// Animeify API client — the only content source in Hanimo 2.0.
//
// Reverse-engineered from Animeify 3.2.0 (Xamarin/.NET, code in AQ.dll).
// Contract: ~/workspace/anime-app/ANIMEIFY_API.md. Verified live from the
// VM 2026-11-06: catalog, search, genre, home, trending, episodes,
// servers, and the MediaFire page scrape to a direct mp4.
//
// Base: https://animeify.net/animeify/apis_v4/ — every call is a POST with
// form fields UserId=0 (guest), Language=EN, Token=<hardcoded>.
// Thumbnails: https://animeify.net/animeify/files/thumbnails/<file>.
//
// This file never throws: every method returns null / [] on failure, and
// the repository turns that into a Result with a readable message.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:animeapp/core/http_client.dart';

const String animeifyBase = 'https://animeify.net/animeify/apis_v4/';
const String animeifyToken = '8cnY80AZSbUCmR26Vku1VUUY4';
const String animeifyThumbs = 'https://animeify.net/animeify/files/thumbnails/';

typedef AnimeifyPoster = Future<http.Response?> Function(Uri url, Map<String, String> fields);
typedef AnimeifyGetter = Future<String> Function(Uri url);

Future<http.Response?> _defaultPost(Uri url, Map<String, String> fields) => httpPost(url, fields);
Future<String> _defaultGet(Uri url) async {
  final res = await httpGet(url, headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36'});
  return res?.body ?? '';
}

// ---------- lenient parsers (server sends numbers as strings) ----------

int _asInt(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim()) ?? 0;
  return 0;
}

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? 0;
  return 0;
}

String _asString(dynamic v) => v == null ? '' : '$v';

List<String> _asGenres(dynamic v) {
  final s = _asString(v);
  if (s.isEmpty) return [];
  return s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

int _yearFrom(dynamic v) {
  final s = _asString(v);
  if (s.length >= 4) return int.tryParse(s.substring(s.length - 4)) ?? 0;
  return 0;
}

String animeifyCurrentSeason([DateTime? now]) {
  final d = now ?? DateTime.now();
  final season = switch (d.month) { 1 || 2 || 3 => 'Winter', 4 || 5 || 6 => 'Spring', 7 || 8 || 9 => 'Summer', _ => 'Fall' };
  return '$season ${d.year}';
}

String animeifyTodayBroadcast([DateTime? now]) {
  const days = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];
  return days[(now ?? DateTime.now()).weekday - 1];
}

// ---------- DTOs ----------

class AnimeifyAnime {
  final String animeId;
  final String title;
  final List<String> genres;
  final String thumbnail;
  final String ytTrailer;
  final String status;
  final int episodeCount;
  final double score;
  final int year;
  final String type; // 'series' or 'movie'
  final int malId;
  final String relationId;
  const AnimeifyAnime({
    required this.animeId,
    required this.title,
    this.genres = const [],
    this.thumbnail = '',
    this.ytTrailer = '',
    this.status = '',
    this.episodeCount = 0,
    this.score = 0,
    this.year = 0,
    this.type = 'series',
    this.malId = 0,
    this.relationId = '',
  });

  String get thumbnailUrl => thumbnail.isEmpty ? '' : '$animeifyThumbs$thumbnail';
  String get trailerUrl => ytTrailer.isEmpty ? '' : 'https://www.youtube.com/watch?v=$ytTrailer';

  factory AnimeifyAnime.fromJson(Map<String, dynamic> json) => AnimeifyAnime(
        animeId: _asString(json['AnimeId']),
        title: _asString(json['EN_Title']),
        genres: _asGenres(json['Genres']),
        thumbnail: _asString(json['Thumbnail']),
        ytTrailer: _asString(json['YTTrailer']),
        status: _asString(json['Status']),
        episodeCount: _asInt(json['Episodes']),
        score: _asDouble(json['Score']),
        year: _yearFrom(json['Premiered']),
        type: _asString(json['Type']).toUpperCase() == 'MOVIE' ? 'movie' : 'series',
        malId: _asInt(json['MalId']),
        relationId: _asString(json['RelationId']),
      );
}

class AnimeifyEpisode {
  final int number;
  final String lbLink;
  final String svLink;
  final String okLink;
  final String maLink;
  final String gdLink;
  final String frLink;
  final String sfLink;
  final String frLowQ;
  final String frFhdQ;
  final String gdFhdQ;
  const AnimeifyEpisode({
    required this.number,
    this.lbLink = '',
    this.svLink = '',
    this.okLink = '',
    this.maLink = '',
    this.gdLink = '',
    this.frLink = '',
    this.sfLink = '',
    this.frLowQ = '',
    this.frFhdQ = '',
    this.gdFhdQ = '',
  });

  factory AnimeifyEpisode.fromJson(Map<String, dynamic> json) => AnimeifyEpisode(
        number: _asInt(json['Episode']),
        lbLink: _asString(json['LBLink']),
        svLink: _asString(json['SVLink']),
        okLink: _asString(json['OKLink']),
        maLink: _asString(json['MALink']),
        gdLink: _asString(json['GDLink']),
        frLink: _asString(json['FRLink']),
        sfLink: _asString(json['SFLink']),
        frLowQ: _asString(json['FRLowQ']),
        frFhdQ: _asString(json['FRFhdQ']),
        gdFhdQ: _asString(json['GDFhdQ']),
      );
}

class AnimeifyServers {
  final AnimeifyEpisode? current;
  final AnimeifyEpisode? previous;
  final AnimeifyEpisode? next;
  const AnimeifyServers({this.current, this.previous, this.next});
}

class AnimeifyHome {
  final List<AnimeifyAnime> latestAnime;
  final List<(AnimeifyAnime, AnimeifyEpisode)> latestEpisodes;
  final List<AnimeifyAnime> broadcast;
  final List<AnimeifyAnime> premiere;
  const AnimeifyHome({this.latestAnime = const [], this.latestEpisodes = const [], this.broadcast = const [], this.premiere = const []});
}

class AnimeifyTrendingItem {
  final String type; // ANIME / EPISODE / ...
  final AnimeifyAnime? anime;
  final AnimeifyEpisode? episode;
  const AnimeifyTrendingItem({required this.type, this.anime, this.episode});
}

// ---------- One server row ----------

class AnimeifyServer {
  final String host;
  final String quality;
  final String id;
  final String kind; // 'direct' | 'external'
  const AnimeifyServer({required this.host, this.quality = '', required this.id, required this.kind});

  String get driveUrl => 'https://drive.google.com/uc?id=$id&export=download';
  String get okEmbedUrl => 'https://ok.ru/videoembed/$id';
  String get megaUrl {
    final parts = id.split('!');
    return parts.length == 2 ? 'https://mega.nz/file/${parts[0]}#${parts[1]}' : 'https://mega.nz/file/$id';
  }

  String get label => quality.isEmpty ? host : '$host $quality';
}

// ---------- Pure extractors (Animeify's own scraping, same regexes) ----------

String? extractMediaFireDirect(String html) {
  final m = RegExp("https://download[^\\s\"']+").firstMatch(html);
  return m?.group(0);
}

String? extractMediaFireScrambled(String html) {
  final m = RegExp(r'data-scrambled-url\s*=\s*"([^"]+)"').firstMatch(html);
  if (m == null) return null;
  final raw = m.group(1)!;
  if (raw.startsWith('http')) return raw;
  try {
    final decoded = utf8.decode(base64.decode(raw));
    if (decoded.startsWith('http')) return decoded;
  } catch (_) {}
  return null;
}

String? extractSolidFilesDirect(String html) {
  final m = RegExp(r'''streamUrl\\?":\\?"(https?://[^"\\]+)''').firstMatch(html);
  return m?.group(1);
}

/// Server rows for one episode, best first. FileLions/SendVid are only
/// listed when the value actually looks like a URL — SendVid's "1" is a
/// flag, not a link.
List<AnimeifyServer> serversForEpisode(AnimeifyEpisode ep) {
  final out = <AnimeifyServer>[];
  void add(String host, String quality, String id, String kind) {
    if (id.isNotEmpty) out.add(AnimeifyServer(host: host, quality: quality, id: id, kind: kind));
  }

  add('MediaFire', 'FHD', ep.frFhdQ, 'direct');
  add('MediaFire', 'HD', ep.frLink, 'direct');
  add('MediaFire', 'Low', ep.frLowQ, 'direct');
  add('SolidFiles', '', ep.sfLink, 'direct');
  add('Google Drive', 'FHD', ep.gdFhdQ, 'direct');
  add('Google Drive', '', ep.gdLink, 'direct');
  if (ep.lbLink.startsWith('http')) add('FileLions', '', ep.lbLink, 'direct');
  if (ep.svLink.startsWith('http')) add('SendVid', '', ep.svLink, 'direct');
  add('OK.ru', '', ep.okLink, 'external');
  add('Mega', '', ep.maLink, 'external');
  return out;
}

// ---------- The client ----------

class AnimeifyApi {
  final AnimeifyPoster post;
  final AnimeifyGetter get;
  AnimeifyApi({AnimeifyPoster? poster, AnimeifyGetter? getter})
      : post = poster ?? _defaultPost,
        get = getter ?? _defaultGet;

  Map<String, String> _fields([Map<String, String>? extra]) =>
      {'UserId': '0', 'Language': 'EN', 'Token': animeifyToken, ...?extra};

  Future<dynamic> _postJson(String path, Map<String, String> fields) async {
    final res = await post(Uri.parse('$animeifyBase$path'), _fields(fields));
    if (res == null || res.statusCode != 200) return null;
    return decodeJsonLoose(res.body);
  }

  List<AnimeifyAnime> _animeList(dynamic v) {
    if (v is! List) return [];
    return v.whereType<Map<String, dynamic>>().map(AnimeifyAnime.fromJson).where((a) => a.animeId.isNotEmpty).toList();
  }

  /// Catalog, paged by [from]. Filters: GENRE / STUDIOS / PREMIERED /
  /// SORT / SEARCH via [filterType]/[filterData]; [type] SERIES / MOVIE / ''.
  Future<List<AnimeifyAnime>> fetchCatalog({String filterType = '', String filterData = '', String type = '', int from = 0}) async {
    final decoded = await _postJson('anime/load_anime_list_v2.php', {
      'FilterType': filterType,
      'FilterData': filterData,
      'Type': type,
      'From': '$from',
    });
    return _animeList(decoded);
  }

  Future<List<AnimeifyAnime>> search(String query) async {
    final q = query.trim();
    if (q.length <= 2) return [];
    // Unfiltered type first, then SERIES — mirrors Animeify's own search.
    final first = await fetchCatalog(filterType: 'SEARCH', filterData: q);
    if (first.isNotEmpty) return first;
    return fetchCatalog(filterType: 'SEARCH', filterData: q, type: 'SERIES');
  }

  Future<AnimeifyHome> fetchHome() async {
    final decoded = await _postJson('home/load_home.php', {
      'Broadcast': animeifyTodayBroadcast(),
      'Premiered': animeifyCurrentSeason(),
    });
    if (decoded is! Map) return const AnimeifyHome();
    final m = Map<String, dynamic>.from(decoded);
    final latestEpisodes = <(AnimeifyAnime, AnimeifyEpisode)>[];
    final rawEps = m['LatestEpisodes'];
    if (rawEps is List) {
      for (final row in rawEps) {
        if (row is! Map) continue;
        final anime = AnimeifyAnime.fromJson(Map<String, dynamic>.from(row['Anime'] ?? {}));
        final ep = AnimeifyEpisode.fromJson(Map<String, dynamic>.from(row['Episode'] ?? {}));
        if (anime.animeId.isNotEmpty && ep.number > 0) latestEpisodes.add((anime, ep));
      }
    }
    return AnimeifyHome(
      latestAnime: _animeList(m['LatestAnime']),
      latestEpisodes: latestEpisodes,
      broadcast: _animeList(m['Broadcast']),
      premiere: _animeList(m['Premiere']),
    );
  }

  Future<List<AnimeifyTrendingItem>> fetchTrending() async {
    final decoded = await _postJson('home/load_trending.php', {});
    if (decoded is! List) return [];
    final out = <AnimeifyTrendingItem>[];
    for (final row in decoded) {
      if (row is! Map) continue;
      final m = Map<String, dynamic>.from(row);
      final type = _asString(m['Type']);
      AnimeifyAnime? anime;
      AnimeifyEpisode? episode;
      final a = m['Anime'];
      if (a is Map) {
        final cand = AnimeifyAnime.fromJson(Map<String, dynamic>.from(a));
        if (cand.animeId.isNotEmpty) anime = cand;
      }
      final e = m['Episode'];
      if (e is Map) {
        final cand = AnimeifyEpisode.fromJson(Map<String, dynamic>.from(e));
        if (cand.number > 0) episode = cand;
      }
      if (anime != null || episode != null) out.add(AnimeifyTrendingItem(type: type, anime: anime, episode: episode));
    }
    return out;
  }

  Future<List<AnimeifyEpisode>> fetchEpisodes(String animeId) async {
    final decoded = await _postJson('episodes/load_episodes.php', {'AnimeID': animeId});
    if (decoded is! List) return [];
    final eps = decoded.whereType<Map<String, dynamic>>().map(AnimeifyEpisode.fromJson).where((e) => e.number > 0).toList();
    eps.sort((a, b) => a.number.compareTo(b.number));
    return eps;
  }

  Future<AnimeifyServers?> fetchServers({required String animeId, required int episode, required String animeType}) async {
    final decoded = await _postJson('anime/load_servers.php', {
      'AnimeId': animeId,
      'Episode': '$episode',
      'AnimeType': animeType,
    });
    if (decoded is! Map) return null;
    final m = Map<String, dynamic>.from(decoded);
    AnimeifyEpisode? read(String key) {
      final v = m[key];
      if (v is! Map) return null;
      final ep = AnimeifyEpisode.fromJson(Map<String, dynamic>.from(v));
      return ep.number > 0 ? ep : null;
    }

    return AnimeifyServers(current: read('CurrentEpisode'), previous: read('PreviousEpisode'), next: read('NextEpisode'));
  }

  /// Plot + related titles. Defaced plots are dropped, never shown.
  Future<({String plot, List<AnimeifyAnime> related})> fetchDetails(String animeId, {String relationId = ''}) async {
    try {
      final decoded = await _postJson('anime/load_anime_details.php', {'AnimeId': animeId, 'AnimeRelationId': relationId});
      if (decoded is Map) {
        final m = Map<String, dynamic>.from(decoded);
        var plot = _asString(m['Plot']).trim();
        if (plot.contains('HACKED_BY_CTF')) plot = '';
        return (plot: plot, related: _animeList(m['RelatedAnime']));
      }
    } catch (_) {}
    return (plot: '', related: const <AnimeifyAnime>[]);
  }

  // ---------- Turning server ids into playable links ----------

  Future<String?> resolveMediaFire(String id) async {
    final html = await get(Uri.parse('https://www.mediafire.com/file/$id'));
    return extractMediaFireDirect(html) ?? extractMediaFireScrambled(html);
  }

  Future<String?> resolveSolidFiles(String id) async {
    final html = await get(Uri.parse('http://www.solidfiles.com/v/$id'));
    return extractSolidFilesDirect(html);
  }

  /// Resolve one server row to a playable URL, or null when it cannot be
  /// resolved right now (the sheet tells the user to try another server).
  Future<String?> resolveServer(AnimeifyServer server, {String fileName = ''}) async {
    switch (server.host) {
      case 'MediaFire':
        return resolveMediaFire(server.id);
      case 'SolidFiles':
        final direct = await resolveSolidFiles(server.id);
        if (direct == null) return null;
        // Animeify appends the file name the same way.
        return fileName.isEmpty ? direct : '$direct/[Animeify]$fileName.mp4';
      case 'Google Drive':
        return server.driveUrl;
      case 'OK.ru':
        return server.okEmbedUrl;
      case 'Mega':
        return server.megaUrl;
      default:
        return server.id.startsWith('http') ? server.id : null;
    }
  }
}
