import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Cinejoy-style Hanimo site: dark, poster rows with ratings, genre chips,
// live catalog from Jikan (no key), and a big 1.0.6 download section.
const apkUrl =
    'https://github.com/benyahya7/hanimo/releases/download/v1.0.6/Hanimo-1.0.6.apk';
const repoUrl = 'https://github.com/benyahya7/hanimo';
const appVersion = '1.0.6';
const apkSize = '63 MB';

void main() => runApp(const HanimoSite());

class HanimoSite extends StatelessWidget {
  const HanimoSite({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hanimo — Watch anime, your way',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0B10),
        colorScheme: const ColorScheme.dark(
            primary: Color(0xFFE50914), secondary: Color(0xFFE50914)),
        cardTheme: const CardThemeData(color: Color(0xFF16161F)),
      ),
      home: const HomePage(),
    );
  }
}

class Anime {
  final int malId;
  final String title;
  final String image;
  final double score;
  final int year;
  final String type;
  final List<String> genres;
  final String url;
  Anime.fromJson(Map<String, dynamic> j)
      : malId = (j['mal_id'] as num?)?.toInt() ?? 0,
        title = (j['title'] as String?) ?? '',
        image = ((j['images'] as Map?)?['jpg'] as Map?)?['large_image_url'] as String? ?? '',
        score = ((j['score'] as num?)?.toDouble()) ?? 0,
        year = (j['year'] as num?)?.toInt() ?? 0,
        type = (j['type'] as String?) ?? '',
        genres = ((j['genres'] as List?) ?? [])
            .map((g) => (g as Map)['name'] as String)
            .toList(),
        url = (j['url'] as String?) ?? '';
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchCtrl = TextEditingController();
  final _pageCtrl = PageController();
  Timer? _timer;
  int _page = 0;
  String _genre = 'All';
  String _query = '';
  bool _loading = true;
  String _err = '';
  List<Anime> _top = [];
  List<Anime> _movies = [];
  List<Anime> _series = [];

  static const _genres = [
    'All',
    'Action',
    'Adventure',
    'Comedy',
    'Drama',
    'Fantasy',
    'Romance',
    'Sci-Fi',
    'Horror',
  ];

  static const _hero = [
    ('assets/images/hero.webp', 'Your anime universe, in one app',
        'Series, movies and live — from your own links and playlists.'),
    ('assets/images/cyberpunk.webp', 'Watch Together',
        'Start a party, invite a friend by Hanimo ID, watch in sync.'),
    ('assets/images/fantasy.webp', 'Friends & chat',
        'Every user gets a Hanimo ID. See who is online, chat by ID.'),
    ('assets/images/series.webp', 'Arabic UI, glass design',
        'Switch to عربي in one tap. Animefy-style transparent look.'),
    ('assets/images/movie.webp', 'Chromecast built in',
        'Cast any stream to your TV, straight from the player.'),
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      _page = (_page + 1) % _hero.length;
      _pageCtrl.animateToPage(_page,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut);
    });
    _loadCatalog();
  }

  Future<List<Anime>> _fetchTop(String query) async {
    final res = await http
        .get(Uri.parse('https://api.jikan.moe/v4/top/anime?$query'))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('Jikan ${res.statusCode}');
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return ((body['data'] as List?) ?? [])
        .map((e) => Anime.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _loadCatalog() async {
    try {
      final top = await _fetchTop('limit=20&filter=bypopularity');
      await Future.delayed(const Duration(milliseconds: 400));
      final movies = await _fetchTop('limit=20&type=movie&filter=bypopularity');
      await Future.delayed(const Duration(milliseconds: 400));
      final series = await _fetchTop('limit=20&type=tv&filter=bypopularity');
      if (mounted) {
        setState(() {
          _top = top;
          _movies = movies;
          _series = series;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _err = '$e'; });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  List<Anime> _filter(List<Anime> list) {
    var out = list;
    if (_genre != 'All') {
      out = out.where((a) => a.genres.contains(_genre)).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      out = out.where((a) => a.title.toLowerCase().contains(q)).toList();
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 800;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xFF0B0B10).withValues(alpha: 0.92),
            title: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset('assets/icon/hanimo-icon.png',
                    width: 36, height: 36, fit: BoxFit.cover),
              ),
              const SizedBox(width: 10),
              const Text('Hanimo',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFE50914))),
            ]),
            actions: [
              if (wide) ...[
                TextButton(
                    onPressed: () => _open(repoUrl),
                    child: const Text('GitHub')),
                const SizedBox(width: 4),
              ],
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: FilledButton.icon(
                  onPressed: () => _open(apkUrl),
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('Download App'),
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _heroCarousel(wide),
                _genreChips(),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_err.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Catalog could not load right now ($_err). The app and download below still work.',
                      style: const TextStyle(color: Colors.white54),
                    ),
                  )
                else ...[
                  _row('Top Rated Anime', _filter(_top)),
                  _row('Top Movies', _filter(_movies)),
                  _row('Top Series', _filter(_series)),
                  _row(
                    'Award-Winning Classics',
                    _filter(_top.where((a) => a.year > 0 && a.year <= 2010).toList()),
                  ),
                ],
                _categories(wide),
                _download(wide),
                _features(wide),
                _footer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroCarousel(bool wide) {
    return SizedBox(
      height: wide ? 460 : 380,
      child: PageView.builder(
        controller: _pageCtrl,
        onPageChanged: (i) => setState(() => _page = i),
        itemCount: _hero.length,
        itemBuilder: (context, i) {
          final h = _hero[i];
          return Stack(fit: StackFit.expand, children: [
            Image.asset(h.$1, fit: BoxFit.cover),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.black87, Colors.black45, Colors.transparent],
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE50914),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('NEW  •  HANIMO $appVersion  •  ANDROID',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 12),
                  Text(h.$2,
                      style: TextStyle(
                          fontSize: wide ? 44 : 30,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text(h.$3,
                      style:
                          const TextStyle(fontSize: 16, color: Colors.white70)),
                  const SizedBox(height: 16),
                  Wrap(spacing: 12, children: [
                    FilledButton.icon(
                      onPressed: () => _open(apkUrl),
                      icon: const Icon(Icons.download),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 8),
                        child: Text(
                            'Download Hanimo $appVersion  •  $apkSize',
                            style: const TextStyle(fontSize: 15)),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _open(repoUrl),
                      icon: const Icon(Icons.code),
                      label: const Text('View on GitHub'),
                    ),
                  ]),
                ],
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _genreChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 10),
          child: Text('Browse by Genre',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        ),
        SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: _genres.length,
            itemBuilder: (context, i) {
              final g = _genres[i];
              final sel = _genre == g;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(g),
                  selected: sel,
                  selectedColor: const Color(0xFFE50914),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  labelStyle: TextStyle(
                      color: sel ? Colors.white : Colors.white70,
                      fontWeight:
                          sel ? FontWeight.bold : FontWeight.normal),
                  side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.08)),
                  onSelected: (_) => setState(() => _genre = g),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.trim()),
            decoration: InputDecoration(
              hintText: 'Search titles…',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ),
      ],
    );
  }

  Widget _row(String title, List<Anime> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
          child: Row(children: [
            Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                    color: const Color(0xFFE50914),
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 10),
            Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w900))),
            Text('${items.length} titles',
                style: const TextStyle(color: Colors.white54)),
          ]),
        ),
        SizedBox(
          height: 250,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final a = items[i];
              return GestureDetector(
                onTap: () => _open(a.url),
                child: Container(
                  width: 150,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16)),
                        child: a.image.isEmpty
                            ? Container(
                                height: 180,
                                color: const Color(0xFF2A2A3E),
                                child: const Icon(Icons.movie, size: 40))
                            : Image.network(a.image,
                                height: 180,
                                width: 150,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) => Container(
                                    height: 180,
                                    color: const Color(0xFF2A2A3E),
                                    child: const Icon(Icons.broken_image))),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(a.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: Row(children: [
                          if (a.score > 0) ...[
                            const Icon(Icons.star,
                                size: 14, color: Colors.amber),
                            Text(' ${a.score.toStringAsFixed(1)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                          ],
                          if (a.year > 0)
                            Text('${a.year}',
                                style: const TextStyle(
                                    color: Colors.white54)),
                          const Spacer(),
                          if (a.type.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE50914),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(a.type,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ),
                        ]),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _categories(bool wide) {
    final counts = <String, int>{};
    for (final a in [..._top, ..._movies, ..._series]) {
      for (final g in a.genres) {
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    const cats = [
      ('Action', Icons.flash_on),
      ('Adventure', Icons.explore),
      ('Comedy', Icons.emoji_emotions),
      ('Drama', Icons.theater_comedy),
      ('Fantasy', Icons.auto_awesome),
      ('Romance', Icons.favorite),
      ('Sci-Fi', Icons.rocket),
      ('Horror', Icons.nightlight),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Categories',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: wide ? 4 : 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.6,
            ),
            itemCount: cats.length,
            itemBuilder: (context, i) {
              final c = cats[i];
              final n = counts[c.$1];
              return GestureDetector(
                onTap: () => setState(() => _genre = c.$1),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: _genre == c.$1
                            ? const Color(0xFFE50914)
                            : Colors.white.withValues(alpha: 0.08),
                        width: _genre == c.$1 ? 2 : 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(c.$2,
                          color: const Color(0xFFE50914), size: 28),
                      const SizedBox(height: 8),
                      Text(c.$1,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(n == null ? 'Tap to browse' : '$n titles',
                          style:
                              const TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _download(bool wide) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE50914), Color(0xFF7A0A12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Flex(
        direction: wide ? Axis.horizontal : Axis.vertical,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset('assets/icon/hanimo-icon.png',
                width: 140, height: 140, fit: BoxFit.cover),
          ),
          const SizedBox(width: 24, height: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Get Hanimo on Android',
                    style:
                        TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                    'Version $appVersion  •  $apkSize  •  Free  •  Android 8+',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                const Text(
                  'What is new in $appVersion:\n'
                  '• Watch Together — watch in sync with a friend\n'
                  '• Friends with Hanimo IDs, online & last-seen\n'
                  '• Arabic UI with full RTL, glass Animefy-style design\n'
                  '• New-episode alerts, trailers & recommendations\n'
                  '• Real Chromecast, user dashboard, Jikan episodes',
                  style: TextStyle(fontSize: 15, color: Colors.white),
                ),
                const SizedBox(height: 18),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black),
                    onPressed: () => _open(apkUrl),
                    icon: const Icon(Icons.android),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 10),
                      child: Text('Download Hanimo $appVersion APK',
                          style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white)),
                    onPressed: () => _open(repoUrl),
                    icon: const Icon(Icons.code),
                    label: const Text('Source on GitHub'),
                  ),
                ]),
                const SizedBox(height: 12),
                const Text(
                  'Install: open the APK from Downloads and allow "Install unknown apps" once. '
                  'Then sign in with Google, open Admin, and tap "Import top anime (Jikan)".',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _features(bool wide) {
    const feats = [
      (Icons.group, 'Watch Together',
          'Start a party, share the code, and playback stays in sync with your friends.'),
      (Icons.people, 'Friends by Hanimo ID',
          'Every user gets an ID like HNM-K7X2P9. Add friends, see who is online, chat by ID.'),
      (Icons.translate, 'Arabic UI',
          'Full English / العربية switch with right-to-left layout.'),
      (Icons.cast, 'Chromecast',
          'Cast any stream to your TV straight from the player.'),
      (Icons.notifications_active, 'New-episode alerts',
          'Your favourites are checked — get told when a new episode drops.'),
      (Icons.lock, 'Private by Design',
          'Your profile and favourites are yours only. Messages are seen by sender and recipient only.'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Why Hanimo',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: wide ? 3 : 1,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: wide ? 1.6 : 2.4,
            ),
            itemCount: feats.length,
            itemBuilder: (context, i) => Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(feats[i].$1,
                      size: 32, color: const Color(0xFFE50914)),
                  const SizedBox(height: 10),
                  Text(feats[i].$2,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(feats[i].$3,
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Text(
        'Hanimo is a personal app. Content comes from links and playlists '
        'the owner adds — the app itself bundles no streams. '
        'Catalog data on this page comes from MyAnimeList via Jikan. '
        'Made with Flutter.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white54),
      ),
    );
  }
}
