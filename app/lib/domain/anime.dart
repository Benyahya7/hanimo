// Domain entities — plain classes, no codegen, no Firebase, no HTTP.
// The UI and AppState only ever see these; the Animeify DTOs stay in the
// data layer.

// One anime title.
class Anime {
  final String id; // Animeify AnimeId, e.g. 'xOnePiece'
  final String title;
  final String imageUrl;
  final double score; // 0-10
  final int year;
  final List<String> genres;
  final int episodeCount;
  final String type; // 'series' or 'movie'
  final int malId;
  final String trailerUrl; // YouTube watch URL, or ''
  final String description; // '' until details are loaded

  const Anime({
    required this.id,
    required this.title,
    this.imageUrl = '',
    this.score = 0,
    this.year = 0,
    this.genres = const [],
    this.episodeCount = 0,
    this.type = 'series',
    this.malId = 0,
    this.trailerUrl = '',
    this.description = '',
  });

  bool get isMovie => type == 'movie';

  Anime copyWith({String? description}) => Anime(
        id: id,
        title: title,
        imageUrl: imageUrl,
        score: score,
        year: year,
        genres: genres,
        episodeCount: episodeCount,
        type: type,
        malId: malId,
        trailerUrl: trailerUrl,
        description: description ?? this.description,
      );
}

// One episode of a title. The server links live on the servers call,
// fetched per episode when the user opens it.
class Episode {
  final int number;
  const Episode(this.number);
}

// One playable server for an episode.
class Server {
  final String host; // 'MediaFire', 'Google Drive', 'OK.ru', ...
  final String quality; // 'FHD', 'HD', 'Low', or ''
  final String id; // the file-host id (or external URL for OK.ru/Mega)
  final String kind; // 'direct' (plays in Hanimo) or 'external' (opens outside)

  const Server({required this.host, this.quality = '', required this.id, required this.kind});

  bool get playsInApp => kind == 'direct';

  String get label => quality.isEmpty ? host : '$host $quality';
}

// The home feed: everything the Home screen shows, in one call.
class HomeFeed {
  final List<Anime> latestAnime;
  final List<(Anime, Episode)> latestEpisodes;
  final List<Anime> broadcast; // airing today
  final List<Anime> premiere; // this season
  const HomeFeed({
    this.latestAnime = const [],
    this.latestEpisodes = const [],
    this.broadcast = const [],
    this.premiere = const [],
  });
}

// A category in the owner's Firestore catalog (Admin-managed).
class Category {
  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final int order;
  const Category({required this.id, this.name = '', this.description = '', this.imageUrl = '', this.order = 0});

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'imageUrl': imageUrl,
        'order': order,
      };

  factory Category.fromMap(String id, Map<String, dynamic> m) => Category(
        id: id,
        name: (m['name'] as String?) ?? '',
        description: (m['description'] as String?) ?? '',
        imageUrl: (m['imageUrl'] as String?) ?? '',
        order: (m['order'] as num?)?.toInt() ?? 0,
      );
}

// One item in the owner's Firestore catalog (Admin-managed or imported).
// Same shape as the 1.x Item so old docs still parse.
class CatalogItem {
  final String id;
  final String categoryId;
  final String title;
  final String description;
  final String imageUrl;
  final String url;
  final String type;
  final int malId;
  final String animeifyId;
  final double score;
  final int year;
  final List<String> genres;
  final int episodeCount;
  final int order;

  const CatalogItem({
    required this.id,
    required this.categoryId,
    required this.title,
    this.description = '',
    this.imageUrl = '',
    this.url = '',
    this.type = 'series',
    this.malId = 0,
    this.animeifyId = '',
    this.score = 0,
    this.year = 0,
    this.genres = const [],
    this.episodeCount = 0,
    this.order = 0,
  });

  factory CatalogItem.fromAnime(Anime a, {required String categoryId, int order = 0}) => CatalogItem(
        id: 'animeify-${a.id}',
        categoryId: categoryId,
        title: a.title,
        imageUrl: a.imageUrl,
        type: a.type,
        malId: a.malId,
        animeifyId: a.id,
        score: a.score,
        year: a.year,
        genres: a.genres,
        episodeCount: a.episodeCount,
        order: order,
      );

  Map<String, dynamic> toMap() => {
        'categoryId': categoryId,
        'title': title,
        'description': description,
        'imageUrl': imageUrl,
        'url': url,
        'type': type,
        'malId': malId,
        'animeifyId': animeifyId,
        'score': score,
        'year': year,
        'genres': genres,
        'episodeCount': episodeCount,
        'order': order,
      };

  factory CatalogItem.fromMap(String id, Map<String, dynamic> m) {
    // Lenient parsing: one bad field never throws — it falls back to a
    // default, so one malformed document cannot break a whole list.
    num? asNum(dynamic v) => v is num ? v : (v is String ? num.tryParse(v) : null);
    List<String> asStrings(dynamic v) {
      if (v is List) return v.map((e) => '$e').toList();
      if (v is String && v.isNotEmpty) return [v];
      return [];
    }

    return CatalogItem(
      id: id,
      categoryId: (m['categoryId'] as String?) ?? '',
      title: (m['title'] as String?) ?? '',
      description: (m['description'] as String?) ?? '',
      imageUrl: (m['imageUrl'] as String?) ?? '',
      url: (m['url'] as String?) ?? '',
      type: (m['type'] as String?) ?? 'series',
      malId: asNum(m['malId'])?.toInt() ?? 0,
      animeifyId: (m['animeifyId'] as String?) ?? '',
      score: asNum(m['score'])?.toDouble() ?? 0,
      year: asNum(m['year'])?.toInt() ?? 0,
      genres: asStrings(m['genres']),
      episodeCount: asNum(m['episodeCount'])?.toInt() ?? 0,
      order: asNum(m['order'])?.toInt() ?? 0,
    );
  }
}

// An update notice (Firestore 'updates') for the Updates inbox.
class UpdateNotice {
  final String id;
  final String versionName;
  final String notes;
  final String downloadUrl;
  final int build;
  const UpdateNotice({required this.id, this.versionName = '', this.notes = '', this.downloadUrl = '', this.build = 0});

  factory UpdateNotice.fromMap(String id, Map<String, dynamic> m) => UpdateNotice(
        id: id,
        versionName: (m['versionName'] as String?) ?? '',
        notes: (m['notes'] as String?) ?? '',
        downloadUrl: (m['downloadUrl'] as String?) ?? '',
        build: (m['build'] as num?)?.toInt() ?? 0,
      );
}
