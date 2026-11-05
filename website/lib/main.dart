import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const apkUrl =
    'https://github.com/benyahya7/hanimo/releases/download/v1.0.2/Hanimo-1.0.2.apk';
const repoUrl = 'https://github.com/benyahya7/hanimo';

void main() => runApp(const HanimoSite());

class HanimoSite extends StatelessWidget {
  const HanimoSite({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hanimo — Watch anime, your way',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B0714),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF2E63),
          secondary: Color(0xFFB967FF),
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final PageController _pages;
  late final Timer _timer;
  int _page = 0;
  final _images = const [
    ('assets/images/hero.webp', 'Your anime universe, in one app'),
    ('assets/images/series.webp', 'Series, movies and live channels'),
    ('assets/images/movie.webp', 'Watch anywhere, share with friends'),
  ];

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _pages = PageController();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      _page = (_page + 1) % _images.length;
      _pages.animateToPage(_page,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _pages.dispose();
    _timer.cancel();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 800;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          _topBar(wide),
          _hero(wide),
          _carousel(),
          _features(wide),
          _howItWorks(wide),
          _version(),
          _footer(),
        ]),
      ),
    );
  }

  Widget _topBar(bool wide) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset('assets/icon/hanimo-icon.png',
              width: 48, height: 48, fit: BoxFit.cover),
        ),
        const SizedBox(width: 12),
        const Text('Hanimo',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        const Spacer(),
        if (wide) ...[
          TextButton(
              onPressed: () => _open(repoUrl), child: const Text('GitHub')),
          const SizedBox(width: 8),
        ],
        FilledButton.icon(
          onPressed: () => _open(apkUrl),
          icon: const Icon(Icons.download),
          label: const Text('Download APK'),
        ),
      ]),
    );
  }

  Widget _hero(bool wide) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final t = _pulse.value;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF2B1055).withValues(alpha: 0.9 + 0.1 * t),
                const Color(0xFF7597DE).withValues(alpha: 0.35),
                const Color(0xFFFF2E63).withValues(alpha: 0.25 + 0.15 * t),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Flex(
            direction: wide ? Axis.horizontal : Axis.vertical,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('NEW VERSION 1.0.2  •  ANDROID',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 20),
                    const Text('Hanimo',
                        style: TextStyle(
                            fontSize: 72,
                            fontWeight: FontWeight.w900,
                            height: 0.95)),
                    const Text('Watch anime,\nyour way.',
                        style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFFD166))),
                    const SizedBox(height: 16),
                    const Text(
                      'Series, movies and live channels from your own links '
                      'and playlists — with categories, posters, sharing, '
                      'profiles and messages. No account needed to browse.',
                      style: TextStyle(fontSize: 17, color: Colors.white70),
                    ),
                    const SizedBox(height: 24),
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      FilledButton.icon(
                        onPressed: () => _open(apkUrl),
                        icon: const Icon(Icons.android),
                        label: const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                          child: Text('Download Hanimo 1.0.2  •  56 MB',
                              style: TextStyle(fontSize: 16)),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _open(repoUrl),
                        icon: const Icon(Icons.code),
                        label: const Text('View on GitHub'),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    const Text(
                      'Android only for now. Install: allow "Install unknown '
                      'apps" once, then open the APK from Downloads.',
                      style:
                          TextStyle(fontSize: 13, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24, height: 24),
              Transform.translate(
                offset: Offset(0, math.sin(t * math.pi) * -12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset('assets/images/hero.webp',
                      width: wide ? 480 : double.infinity,
                      height: 340,
                      fit: BoxFit.cover),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _carousel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(children: [
        SizedBox(
          height: 360,
          child: PageView.builder(
            controller: _pages,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: _images.length,
            itemBuilder: (context, i) => Stack(
              alignment: Alignment.bottomLeft,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(_images[i].$1,
                      width: double.infinity,
                      height: 360,
                      fit: BoxFit.cover),
                ),
                Container(
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(_images[i].$2,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _images.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: _page == i ? 28 : 10,
              height: 10,
              decoration: BoxDecoration(
                color: _page == i
                    ? const Color(0xFFFF2E63)
                    : Colors.white24,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _features(bool wide) {
    const feats = [
      (Icons.tv, 'Series & Movies', 'Browse categories with posters, details and episode lists.'),
      (Icons.playlist_play, 'Your Playlists', 'Paste an M3U playlist you already have — it becomes categories and channels.'),
      (Icons.share, 'Share Anything', 'Share any title with friends from the app, in one tap.'),
      (Icons.person, 'Profiles & Messages', 'Sign in with Google for your own profile, favourites and private messages.'),
      (Icons.admin_panel_settings, 'Admin, Automatic', 'The owner account gets Admin automatically — no codes, no setup.'),
      (Icons.lock, 'Private by Design', 'Your profile and favourites are yours only. Messages are seen by sender and recipient only.'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Why Hanimo',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: wide ? 3 : 1,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: wide ? 1.5 : 2.2,
            ),
            itemCount: feats.length,
            itemBuilder: (context, i) => Card(
              color: Colors.white.withValues(alpha: 0.06),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(feats[i].$1, size: 32, color: const Color(0xFFFFD166)),
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
          ),
        ],
      ),
    );
  }

  Widget _howItWorks(bool wide) {
    const steps = [
      ('1', 'Download', 'Tap Download APK above and get Hanimo 1.0.2.'),
      ('2', 'Install', 'Open it from Downloads and allow install once.'),
      ('3', 'Browse or sign in', 'Browse right away, or sign in with Google for profile and messages.'),
      ('4', 'Watch & share', 'Play your links, import a playlist, share titles with friends.'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Get started in 4 steps',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: steps
                .map((s) => SizedBox(
                      width: wide ? 260 : double.infinity,
                      child: Card(
                        color: const Color(0xFF1B1035),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                  backgroundColor: const Color(0xFFFF2E63),
                                  child: Text(s.$1,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold))),
                              const SizedBox(height: 10),
                              Text(s.$2,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 6),
                              Text(s.$3,
                                  style: const TextStyle(
                                      color: Colors.white70)),
                            ],
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _version() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('What is new in 1.0.2',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          const Text('• Native Google sign-in — no browser page, no session errors\n'
              '• Admin is automatic for the owner account, no UID to copy\n'
              '• Profile, favourites and messages stay private — never shared with other users\n'
              '• Profile dashboard with favourites, inbox, sent messages and replies'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _open(apkUrl),
            icon: const Icon(Icons.download),
            label: const Text('Download Hanimo 1.0.2 APK'),
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
        'Made with Flutter.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white54),
      ),
    );
  }
}
