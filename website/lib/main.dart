import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// Hanimo 2.0.1 official site — Flutter web, deployed to GitHub Pages.
// Dark violet/pink 2.0 design. No live catalog on this page on purpose:
// the app's catalog comes from Animeify's server, which does not send
// CORS headers, so a browser cannot read it directly. The catalog lives
// inside the Android app — this page is the download + showcase page.
const apkUrl =
    'https://github.com/benyahya7/hanimo/releases/download/v2.0.1/Hanimo-2.0.1.apk';
const repoUrl = 'https://github.com/benyahya7/hanimo';
const appVersion = '2.0.1';
const apkSize = '61 MB';

const _bg = Color(0xFF0A0A14);
const _surface = Color(0xFF14141F);
const _card = Color(0xFF1C1C2A);
const _violet = Color(0xFF7C5CFF);
const _pink = Color(0xFFFF3D7F);

void main() => runApp(const HanimoSite());

class HanimoSite extends StatelessWidget {
  const HanimoSite({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hanimo — Watch anime, your way',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
            primary: _violet, secondary: _pink, surface: _surface),
        cardTheme: const CardThemeData(color: _card),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _violet,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}

/// The new 2.0 logo, drawn in code so it never depends on an asset file:
/// violet-to-pink gradient H, pink play triangle as the crossbar.
class HanimoLogo extends StatelessWidget {
  final double size;
  const HanimoLogo({super.key, this.size = 36});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_violet, _pink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                  width: size * 0.14,
                  height: size * 0.62,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2))),
              SizedBox(width: size * 0.30),
              Container(
                  width: size * 0.14,
                  height: size * 0.62,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2))),
            ],
          ),
          Icon(Icons.play_arrow, size: size * 0.42, color: Colors.white),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _pageCtrl = PageController();
  Timer? _timer;
  int _page = 0;

  static const _hero = [
    ('assets/images/hero.webp', 'Your anime universe, in one app',
        'Series and movies, fresh from the server — trending, latest episodes, airing today.'),
    ('assets/images/cyberpunk.webp', 'Tap a title, pick a server, watch',
        'Every episode lists its servers. MediaFire HD plays right in the app.'),
    ('assets/images/fantasy.webp', 'My List & Continue Watching',
        'Save favourites, pick up exactly where you left off.'),
    ('assets/images/series.webp', 'Arabic UI, one tap',
        'Switch to عربي — full RTL, same violet-to-pink design.'),
    ('assets/images/movie.webp', 'Rebuilt from scratch — 2.0',
        'Clean architecture, nothing fails silently: every screen shows what happened and how to retry.'),
  ];

  static const _showcase = [
    ('assets/images/hero.webp', 'Home', 'Trending now, latest episodes, airing today, this season.'),
    ('assets/images/series.webp', 'Browse', 'Series and movies, genre filters, load more.'),
    ('assets/images/cyberpunk.webp', 'Search', 'Live search — type 3 letters and results appear.'),
    ('assets/images/movie.webp', 'Player', 'Tap controls, ±10s, speed, fullscreen, resume.'),
    ('assets/images/fantasy.webp', 'Admin', 'Import top anime, manage the catalog, publish updates.'),
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
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 800;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: _bg.withValues(alpha: 0.92),
            title: Row(children: [
              const HanimoLogo(size: 36),
              const SizedBox(width: 10),
              const Text('Hanimo',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: Colors.white)),
              const Text('.',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: _pink)),
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
                _showcaseSection(wide),
                _download(wide),
                _installSteps(wide),
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
                      gradient: const LinearGradient(
                          colors: [_violet, _pink]),
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

  Widget _showcaseSection(bool wide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Inside the app',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text(
              'The catalog lives inside the Android app — here is what each screen does.',
              style: TextStyle(color: Colors.white54, fontSize: 15)),
          const SizedBox(height: 18),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: wide ? 5 : 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 0.72,
            ),
            itemCount: _showcase.length,
            itemBuilder: (context, i) {
              final s = _showcase[i];
              return Container(
                decoration: BoxDecoration(
                  color: _card,
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
                      child: Image.asset(s.$1,
                          height: 150, width: double.infinity,
                          fit: BoxFit.cover),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.$2,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(s.$3,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
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
          colors: [_violet, _pink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Flex(
        direction: wide ? Axis.horizontal : Axis.vertical,
        children: [
          const HanimoLogo(size: 140),
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
                  '• Rebuilt from scratch — clean architecture, nothing fails silently\n'
                  '• Catalog, episodes and servers from Animeify — always fresh\n'
                  '• New logo and new violet-to-pink design\n'
                  '• In-app player: tap controls, ±10s, speed, fullscreen, resume\n'
                  '• My List, Continue Watching, live search, Arabic UI\n'
                  '• Admin: import top anime, manage the catalog, publish updates',
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
                  'Then sign in with Google — the owner account gets Admin automatically.',
                  style: TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _installSteps(bool wide) {
    const steps = [
      ('1', 'Download', 'Tap the download button above to get the APK.'),
      ('2', 'Install', 'Open it from Downloads and allow installs from this source once.'),
      ('3', 'Sign in', 'Google sign-in for your profile, My List and Hanimo ID.'),
      ('4', 'Watch', 'Pick a title, choose an episode and a server, press play.'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Install in 4 steps',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: wide ? 4 : 2,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.4,
            ),
            itemCount: steps.length,
            itemBuilder: (context, i) => Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: const BoxDecoration(
                      gradient:
                          LinearGradient(colors: [_violet, _pink]),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(steps[i].$1,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16)),
                  ),
                  const SizedBox(height: 10),
                  Text(steps[i].$2,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(steps[i].$3,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _features(bool wide) {
    const feats = [
      (Icons.play_circle, 'Watch in the app',
          'Episodes list their servers — MediaFire HD, SolidFiles and Drive play in the built-in player.'),
      (Icons.autorenew, 'Always fresh',
          'Home, trending, latest episodes and new seasons come straight from the server on every open.'),
      (Icons.bookmark, 'My List & resume',
          'Save favourites and continue watching exactly where you stopped.'),
      (Icons.translate, 'Arabic UI',
          'Full English / العربية switch with right-to-left layout.'),
      (Icons.admin_panel_settings, 'Owner Admin',
          'Import top anime, edit the catalog and publish update notices from inside the app.'),
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
                color: _card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(feats[i].$1, size: 32, color: _pink),
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
        'Hanimo is a personal app. The catalog inside the Android app comes '
        'from Animeify\u2019s server. The app itself bundles no streams. '
        'Made with Flutter.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white54),
      ),
    );
  }
}
