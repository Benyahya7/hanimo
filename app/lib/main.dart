import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'firebase_options.dart';

// ---------- Models ----------
class Cat {
  final String id, name, description, imageUrl;
  final int order;
  final bool isVisible;
  Cat({required this.id, required this.name, this.description = '', this.imageUrl = '', this.order = 0, this.isVisible = true});
  factory Cat.fromMap(String id, Map<String, dynamic> m) => Cat(
        id: id,
        name: (m['name'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        imageUrl: (m['imageUrl'] ?? '') as String,
        order: (m['order'] as num?)?.toInt() ?? 0,
        isVisible: (m['isVisible'] as bool?) ?? true,
      );
  Map<String, dynamic> toMap() => {'name': name, 'description': description, 'imageUrl': imageUrl, 'order': order, 'isVisible': isVisible};
}

class Item {
  final String id, categoryId, title, description, imageUrl, url, type;
  final bool isLive, isVisible;
  final int order;
  Item({required this.id, required this.categoryId, required this.title, this.description = '', this.imageUrl = '', this.url = '', this.type = 'series', this.isLive = false, this.isVisible = true, this.order = 0});
  factory Item.fromMap(String id, Map<String, dynamic> m) => Item(
        id: id,
        categoryId: (m['categoryId'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        imageUrl: (m['imageUrl'] ?? '') as String,
        url: (m['url'] ?? '') as String,
        type: (m['type'] ?? 'series') as String,
        isLive: (m['isLive'] as bool?) ?? false,
        isVisible: (m['isVisible'] as bool?) ?? true,
        order: (m['order'] as num?)?.toInt() ?? 0,
      );
  Map<String, dynamic> toMap() => {'categoryId': categoryId, 'title': title, 'description': description, 'imageUrl': imageUrl, 'url': url, 'type': type, 'isLive': isLive, 'isVisible': isVisible, 'order': order};
  Map<String, dynamic> toJson() => {...toMap(), 'id': id};
  factory Item.fromJson(Map<String, dynamic> j) => Item.fromMap(j['id'] as String? ?? '', j);
}

// Local seed — identical to the live Firestore seed, used only as fallback.
final List<Cat> seedCats = [
  Cat(id: 'anime-series', name: 'Anime Series', description: 'Series with episodes. Add your own titles, posters and links here.', order: 1),
  Cat(id: 'anime-movies', name: 'Anime Movies', description: 'Standalone movies.', order: 2),
  Cat(id: 'live-tv', name: 'Live TV', description: 'Live channels from a playlist you import yourself.', order: 3),
];
final List<Item> seedItems = [
  Item(id: 'demo-series-01', categoryId: 'anime-series', title: 'Demo Series — replace me', description: 'Demo item only, so the app is not empty on first run. Delete it in Admin and add your own item.', type: 'series', order: 1),
  Item(id: 'demo-movie-01', categoryId: 'anime-movies', title: 'Demo Movie — replace me', description: 'Demo item only. Replace with your own title, poster and link.', type: 'movie', order: 1),
];

// ---------- M3U parsing ----------
String? _attr(String line, String key) {
  final m = RegExp('$key="([^"]*)"').firstMatch(line);
  return m?.group(1);
}

List<Item> parseM3u(String text) {
  final lines = text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  final out = <Item>[];
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith('#EXTINF')) continue;
    final title = lines[i].contains(',') ? lines[i].substring(lines[i].lastIndexOf(',') + 1).trim() : 'Channel ${out.length + 1}';
    final group = _attr(lines[i], 'group-title') ?? 'Imported';
    final logo = _attr(lines[i], 'tvg-logo') ?? '';
    if (i + 1 < lines.length && !lines[i + 1].startsWith('#')) {
      out.add(Item(id: 'imp-${out.length}', categoryId: group, title: title, imageUrl: logo, url: lines[i + 1], type: 'live', isLive: true, order: out.length));
    }
  }
  return out;
}

// ---------- App state (simple, held in the root widget) ----------
class AppData extends ChangeNotifier {
  List<Cat> cats = List.of(seedCats);
  List<Item> items = List.of(seedItems);
  List<Item> imported = [];
  List<Item> recent = [];
  Set<String> favIds = {};
  Map<String, Item> favItems = {};
  bool offline = true;
  bool loading = true;
  String status = 'Loading…';
  User? user;
  bool isAdmin = false;
  String adminNote = 'Sign in to check admin status.';

  String catName(String id) => cats.firstWhere((c) => c.id == id, orElse: () => Cat(id: id, name: id)).name;

  Future<void> init() async {
    try { await GoogleSignIn.instance.initialize(); } catch (_) {}
    await _loadLocal();
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      await refreshFromFirestore();
      offline = false;
      status = 'Connected to Firebase (anime-app-556c8)';
    } catch (e) {
      offline = true;
      status = 'Offline / demo data — Firebase not connected: $e';
      cats = List.of(seedCats);
      items = List.of(seedItems);
    }
    loading = false;
    notifyListeners();
    FirebaseAuth.instance.authStateChanges().listen((u) async {
      user = u;
      await ensureProfile();
      await checkAdmin();
      notifyListeners();
    });
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final favJson = prefs.getStringList('favs') ?? [];
    favIds = {};
    favItems = {};
    for (final s in favJson) {
      try {
        final it = Item.fromJson(jsonDecode(s) as Map<String, dynamic>);
        favIds.add(it.id);
        favItems[it.id] = it;
      } catch (_) {}
    }
    final impJson = prefs.getStringList('imported') ?? [];
    imported = [];
    for (final s in impJson) {
      try {
        imported.add(Item.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } catch (_) {}
    }
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favs', favItems.values.map((e) => jsonEncode(e.toJson())).toList());
    await prefs.setStringList('imported', imported.map((e) => jsonEncode(e.toJson())).toList());
  }

  Future<void> refreshFromFirestore() async {
    final cs = await FirebaseFirestore.instance.collection('categories').get();
    final is_ = await FirebaseFirestore.instance.collection('items').get();
    final newCats = cs.docs.map((d) => Cat.fromMap(d.id, d.data())).toList()..sort((a, b) => a.order.compareTo(b.order));
    final newItems = is_.docs.map((d) => Item.fromMap(d.id, d.data())).toList()..sort((a, b) => a.order.compareTo(b.order));
    if (newCats.isNotEmpty) cats = newCats;
    if (newItems.isNotEmpty) items = newItems;
    offline = false;
    notifyListeners();
  }

  Future<void> toggleFav(Item it) async {
    if (favIds.contains(it.id)) {
      favIds.remove(it.id);
      favItems.remove(it.id);
    } else {
      favIds.add(it.id);
      favItems[it.id] = it;
    }
    await _saveLocal();
    notifyListeners();
  }

  void addRecent(Item it) {
    recent.removeWhere((e) => e.id == it.id);
    recent.insert(0, it);
    if (recent.length > 20) recent = recent.sublist(0, 20);
    notifyListeners();
  }

  Future<void> ensureProfile() async {
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).set({
        'displayName': user!.displayName ?? '',
        'email': user!.email ?? '',
        'photoURL': user!.photoURL ?? '',
        'lastSignIn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> checkAdmin() async {
    if (user == null) {
      isAdmin = false;
      adminNote = 'Not signed in.';
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('admins').doc(user!.uid).get();
      // Admin by Firestore rules: admins/{uid} OR owner email raiss95@gmail.com.
      isAdmin = doc.exists || user!.email == 'raiss95@gmail.com';
      adminNote = isAdmin
          ? 'You are an admin. You can add, edit and delete categories and items.'
          : 'You are signed in, but you are not an admin yet.';
    } catch (e) {
      // Rules still allow the owner email even if this doc read fails.
      isAdmin = user!.email == 'raiss95@gmail.com';
      adminNote = isAdmin ? 'You are an admin.' : 'Admin check failed (Firebase not connected?): $e';
    }
    notifyListeners();
  }

  // Native Android Google sign-in (no browser redirect, so it cannot hit
  // the firebaseapp.com "missing initial state" sessionStorage error).
  // Profile/favourites/messages are private: users/{uid} is owner-only in
  // Firestore rules, favourites stay on this device, and a message is
  // readable only by its sender and its recipient — never by other users.
  Future<void> signInGoogle() async {
    try {
      final googleUser = await GoogleSignIn.instance.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(idToken: googleAuth.idToken);
      await FirebaseAuth.instance.signInWithCredential(credential);
      user = FirebaseAuth.instance.currentUser;
      await ensureProfile();
      await checkAdmin();
    } catch (e) {
      adminNote = 'Google sign-in failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  Future<void> signOut() async {
    try { await GoogleSignIn.instance.signOut(); } catch (_) {}
    await FirebaseAuth.instance.signOut();
    user = null;
    isAdmin = false;
    adminNote = 'Signed out.';
    notifyListeners();
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AnimeApp());
}

class AnimeApp extends StatefulWidget {
  const AnimeApp({super.key});
  @override
  State<AnimeApp> createState() => _AnimeAppState();
}

class _AnimeAppState extends State<AnimeApp> {
  final data = AppData();
  @override
  void initState() {
    super.initState();
    data.init();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) => MaterialApp(
        title: 'Hanimo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0F0F1A),
          colorScheme: const ColorScheme.dark(primary: Color(0xFF7C4DFF), secondary: Color(0xFFFF4081), surface: Color(0xFF1E1E2E)),
          cardTheme: const CardThemeData(color: Color(0xFF1E1E2E)),
          appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF14141F)),
        ),
        home: RootPage(data: data),
      ),
    );
  }
}

// ---------- Shared widgets ----------
Widget posterWidget(Item it, {double height = 150}) {
  if (it.imageUrl.isEmpty) {
    return Container(
      height: height,
      color: const Color(0xFF2A2A3E),
      child: Center(child: Icon(it.isLive ? Icons.live_tv : Icons.movie, size: 48, color: Colors.white54)),
    );
  }
  return CachedNetworkImage(
    imageUrl: it.imageUrl,
    height: height,
    width: double.infinity,
    fit: BoxFit.cover,
    placeholder: (c, u) => Container(height: height, color: const Color(0xFF2A2A3E), child: const Center(child: CircularProgressIndicator())),
    errorWidget: (c, u, e) => Container(height: height, color: const Color(0xFF2A2A3E), child: const Center(child: Icon(Icons.broken_image, color: Colors.white54))),
  );
}

Widget catCover(Cat c, {double height = 110}) {
  if (c.imageUrl.isEmpty) {
    return Container(height: height, color: const Color(0xFF2A2A3E), child: Center(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)));
  }
  return CachedNetworkImage(imageUrl: c.imageUrl, height: height, width: double.infinity, fit: BoxFit.cover, errorWidget: (c, u, e) => Container(height: height, color: const Color(0xFF2A2A3E), child: const Icon(Icons.broken_image)));
}

// ---------- Root ----------
class RootPage extends StatefulWidget {
  final AppData data;
  const RootPage({super.key, required this.data});
  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final pages = [HomePage(data: d, goTab: (i) => setState(() => tab = i)), BrowsePage(data: d), SearchPage(data: d), MyListPage(data: d), ImportPage(data: d), ProfilePage(data: d), AdminPage(data: d)];
    return Scaffold(
      appBar: AppBar(
          title: Row(mainAxisSize: MainAxisSize.min, children: [ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/icon/hanimo-icon.png', width: 32, height: 32, fit: BoxFit.cover)), const SizedBox(width: 10), const Text('Hanimo')]),
          actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () async { try { await d.refreshFromFirestore(); } catch (_) {} })]),
      body: d.loading ? const Center(child: CircularProgressIndicator()) : pages[tab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: tab,
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF14141F),
        selectedItemColor: const Color(0xFF7C4DFF),
        unselectedItemColor: Colors.white54,
        onTap: (i) => setState(() => tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'Browse'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'My List'),
          BottomNavigationBarItem(icon: Icon(Icons.playlist_add), label: 'Import'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          BottomNavigationBarItem(icon: Icon(Icons.admin_panel_settings), label: 'Admin'),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  final AppData data;
  final void Function(int) goTab;
  const HomePage({super.key, required this.data, required this.goTab});
  @override
  Widget build(BuildContext context) {
    final d = data;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (d.offline)
          Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)), child: Text('Offline / demo data — ${d.status}', style: const TextStyle(color: Colors.amber)))
        else
          Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)), child: Text(d.status, style: const TextStyle(color: Colors.greenAccent))),
        const SizedBox(height: 12),
        GestureDetector(onTap: () => goTab(2), child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFF1E1E2E), borderRadius: BorderRadius.circular(12)), child: const Row(children: [Icon(Icons.search, color: Colors.white54), SizedBox(width: 8), Text('Search titles…', style: TextStyle(color: Colors.white54))]))),
        const SizedBox(height: 16),
        const Text('Categories', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.4, crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: d.cats.length,
          itemBuilder: (c, i) {
            final cat = d.cats[i];
            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryPage(data: d, cat: cat))),
              child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Stack(children: [catCover(cat, height: double.infinity), Positioned(left: 10, bottom: 10, child: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold, shadows: [Shadow(blurRadius: 6, color: Colors.black)])))])),
            );
          },
        ),
        if (d.recent.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Continue watching', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(height: 190, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: d.recent.length, itemBuilder: (c, i) => _itemCard(context, d, d.recent[i], width: 130))),
        ],
        if (d.imported.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('Imported', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SizedBox(height: 190, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: d.imported.length, itemBuilder: (c, i) => _itemCard(context, d, d.imported[i], width: 130))),
        ],
        const SizedBox(height: 12),
        const Text('No streams are bundled. Only the demo items above are included. Add your own categories, items and links in Admin.', style: TextStyle(color: Colors.white54)),
      ]),
    );
  }
}

Widget _itemCard(BuildContext context, AppData d, Item it, {double width = 160}) {
  return GestureDetector(
    onTap: () {
      d.addRecent(it);
      Navigator.push(context, MaterialPageRoute(builder: (_) => ItemPage(data: d, item: it)));
    },
    child: Container(width: width, margin: const EdgeInsets.only(right: 10), child: Card(clipBehavior: Clip.antiAlias, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [posterWidget(it, height: 120), Padding(padding: const EdgeInsets.all(8), child: Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)))]))),
  );
}

class BrowsePage extends StatelessWidget {
  final AppData data;
  const BrowsePage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: data.cats.length,
      itemBuilder: (c, i) {
        final cat = data.cats[i];
        final count = data.items.where((e) => e.categoryId == cat.id).length;
        return Card(child: ListTile(leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 56, height: 56, child: catCover(cat, height: 56))), title: Text(cat.name), subtitle: Text('$count items • ${cat.description}'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryPage(data: data, cat: cat)))));
      },
    );
  }
}

class CategoryPage extends StatelessWidget {
  final AppData data;
  final Cat cat;
  const CategoryPage({super.key, required this.data, required this.cat});
  @override
  Widget build(BuildContext context) {
    final list = data.items.where((e) => e.categoryId == cat.id).toList()..sort((a, b) => a.order.compareTo(b.order));
    final imp = data.imported.where((e) => e.categoryId == cat.id || e.categoryId == cat.name).toList();
    final all = [...list, ...imp];
    return Scaffold(
      appBar: AppBar(title: Text(cat.name)),
      body: all.isEmpty
          ? const Center(child: Text('No items in this category yet. Add some in Admin.'))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.75, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: all.length,
              itemBuilder: (c, i) => _itemCard(context, data, all[i], width: double.infinity),
            ),
    );
  }
}

class ItemPage extends StatelessWidget {
  final AppData data;
  final Item item;
  const ItemPage({super.key, required this.data, required this.item});
  @override
  Widget build(BuildContext context) {
    final fav = data.favIds.contains(item.id);
    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          posterWidget(item, height: 240),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [Chip(label: Text(item.type)), if (item.isLive) const Chip(label: Text('LIVE')), Chip(label: Text(data.catName(item.categoryId)))]),
              const SizedBox(height: 12),
              Text(item.description.isEmpty ? 'No description yet.' : item.description),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.play_arrow), label: const Text('Play'), onPressed: () {
                  data.addRecent(item);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(item: item)));
                })),
                const SizedBox(width: 10),
                IconButton(icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? Colors.pink : null), onPressed: () => data.toggleFav(item)),
                IconButton(icon: const Icon(Icons.share), onPressed: () async {
                  final text = item.url.isEmpty ? '${item.title} — Hanimo' : '${item.title}\n${item.url}';
                  await SharePlus.instance.share(ShareParams(text: text));
                }),
              ]),
              if (item.url.isEmpty) const Padding(padding: EdgeInsets.only(top: 12), child: Text('No link yet — add one in Admin.', style: TextStyle(color: Colors.amber))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class PlayerPage extends StatefulWidget {
  final Item item;
  const PlayerPage({super.key, required this.item});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? ctrl;
  String? err;
  @override
  void initState() {
    super.initState();
    final url = widget.item.url;
    if (url.isEmpty) return;
    final lower = url.toLowerCase();
    final isVideo = lower.endsWith('.mp4') || lower.endsWith('.m3u8') || lower.contains('.m3u8') || lower.endsWith('.mov') || lower.endsWith('.webm');
    if (isVideo) {
      ctrl = VideoPlayerController.networkUrl(Uri.parse(url))
        ..initialize().then((_) {
          if (mounted) setState(() {});
          ctrl?.play();
        }).catchError((e) {
          if (mounted) setState(() => err = 'Could not play this stream: $e');
        });
    }
  }

  @override
  void dispose() {
    ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.item.url;
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.title)),
      body: Center(
        child: url.isEmpty
            ? const Padding(padding: EdgeInsets.all(20), child: Text('No link yet — add one in Admin.', textAlign: TextAlign.center))
            : err != null
                ? Padding(padding: const EdgeInsets.all(20), child: Text(err!, textAlign: TextAlign.center))
                : ctrl == null
                    ? Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('This looks like a web link, not a direct video file.'),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(icon: const Icon(Icons.open_in_browser), label: const Text('Open in browser'), onPressed: () async {
                          final uri = Uri.tryParse(url);
                          if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }),
                        const SizedBox(height: 8),
                        SelectableText(url),
                      ])
                    : ctrl!.value.isInitialized
                        ? Column(mainAxisSize: MainAxisSize.min, children: [
                            AspectRatio(aspectRatio: ctrl!.value.aspectRatio, child: VideoPlayer(ctrl!)),
                            const SizedBox(height: 12),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              IconButton(icon: Icon(ctrl!.value.isPlaying ? Icons.pause : Icons.play_arrow), iconSize: 36, onPressed: () => setState(() => ctrl!.value.isPlaying ? ctrl!.pause() : ctrl!.play())),
                              IconButton(icon: const Icon(Icons.replay_10), onPressed: () => ctrl!.seekTo(ctrl!.value.position - const Duration(seconds: 10))),
                              IconButton(icon: const Icon(Icons.forward_10), onPressed: () => ctrl!.seekTo(ctrl!.value.position + const Duration(seconds: 10))),
                            ]),
                          ])
                        : const CircularProgressIndicator(),
      ),
    );
  }
}

class SearchPage extends StatefulWidget {
  final AppData data;
  const SearchPage({super.key, required this.data});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  String q = '';
  @override
  Widget build(BuildContext context) {
    final all = [...widget.data.items, ...widget.data.imported];
    final res = q.isEmpty ? all : all.where((e) => e.title.toLowerCase().contains(q.toLowerCase())).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: TextField(decoration: const InputDecoration(hintText: 'Search titles…', border: OutlineInputBorder(), prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => q = v))),
      Expanded(child: ListView.builder(itemCount: res.length, itemBuilder: (c, i) => ListTile(leading: const Icon(Icons.play_circle), title: Text(res[i].title), subtitle: Text(widget.data.catName(res[i].categoryId)), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemPage(data: widget.data, item: res[i])))))),
    ]);
  }
}

class MyListPage extends StatelessWidget {
  final AppData data;
  const MyListPage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    final list = data.favItems.values.toList();
    if (list.isEmpty) return const Center(child: Text('No favourites yet. Tap the heart on any item.'));
    return ListView.builder(itemCount: list.length, itemBuilder: (c, i) => ListTile(leading: const Icon(Icons.favorite, color: Colors.pink), title: Text(list[i].title), trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () => data.toggleFav(list[i])), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemPage(data: data, item: list[i])))));
  }
}

class ImportPage extends StatefulWidget {
  final AppData data;
  const ImportPage({super.key, required this.data});
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  final urlCtrl = TextEditingController();
  final textCtrl = TextEditingController();
  String msg = '';
  @override
  void dispose() {
    urlCtrl.dispose();
    textCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => msg = 'Fetching…');
    try {
      final res = await http.get(Uri.parse(urlCtrl.text.trim()));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final parsed = parseM3u(res.body);
      setState(() {
        widget.data.imported = parsed;
        msg = 'Imported ${parsed.length} channels (local only).';
      });
      await widget.data._saveLocal();
    } catch (e) {
      setState(() => msg = 'Fetch failed: $e');
    }
  }

  void _parseText() {
    final parsed = parseM3u(textCtrl.text);
    setState(() {
      widget.data.imported = parsed;
      msg = 'Imported ${parsed.length} channels (local only).';
    });
    widget.data._saveLocal();
  }

  Future<void> _saveToFirestore() async {
    if (!widget.data.isAdmin) {
      setState(() => msg = 'Not an admin — cannot write to Firestore. Sign in with an admin account.');
      return;
    }
    try {
      final db = FirebaseFirestore.instance;
      for (final it in widget.data.imported) {
        final catId = it.categoryId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '-').toLowerCase();
        await db.collection('categories').doc(catId).set({'name': it.categoryId, 'description': 'Imported playlist group', 'imageUrl': '', 'order': 99, 'isVisible': true}, SetOptions(merge: true));
        await db.collection('items').add(it.toMap()..['categoryId'] = catId);
      }
      setState(() => msg = 'Saved ${widget.data.imported.length} imported items to Firestore.');
      await widget.data.refreshFromFirestore();
    } catch (e) {
      setState(() => msg = 'Save failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Playlist import (IPTV-style)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Paste a playlist URL you already have, or paste M3U text. Imported channels stay local unless you are an admin and choose Save to Firestore. Nothing is bundled in the app.'),
        const SizedBox(height: 12),
        TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'M3U URL', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        ElevatedButton.icon(icon: const Icon(Icons.download), label: const Text('Fetch playlist'), onPressed: _fetch),
        const SizedBox(height: 12),
        TextField(controller: textCtrl, maxLines: 6, decoration: const InputDecoration(labelText: 'Or paste M3U text here', border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(children: [
          ElevatedButton(onPressed: _parseText, child: const Text('Parse text')),
          const SizedBox(width: 10),
          ElevatedButton(onPressed: _saveToFirestore, child: const Text('Save to Firestore (admin only)')),
          const SizedBox(width: 10),
          TextButton(onPressed: () async { setState(() => d.imported = []); await d._saveLocal(); }, child: const Text('Clear')),
        ]),
        if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(msg)),
        const SizedBox(height: 12),
        Text('Imported: ${d.imported.length} channels', style: const TextStyle(fontWeight: FontWeight.bold)),
        ...d.imported.take(50).map((it) => ListTile(leading: const Icon(Icons.live_tv), title: Text(it.title), subtitle: Text(it.categoryId), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemPage(data: d, item: it))))),
        if (d.imported.length > 50) Text('…and ${d.imported.length - 50} more'),
      ]),
    );
  }
}

// ---------- Profile dashboard + messages ----------
class ProfilePage extends StatelessWidget {
  final AppData data;
  const ProfilePage({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    final d = data;
    final u = d.user;
    final favs = d.favItems.values.toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: (u?.photoURL != null && u!.photoURL!.isNotEmpty) ? NetworkImage(u.photoURL!) : null,
                child: (u?.photoURL == null || u!.photoURL!.isEmpty) ? Text((u?.displayName ?? u?.email ?? 'G').substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 24)) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u?.displayName?.isNotEmpty == true ? u!.displayName! : (u?.email ?? 'Guest'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  if (u?.email != null) Text(u!.email!, style: const TextStyle(color: Colors.white70)),
                  if (d.isAdmin) const Text('Admin account', style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                  if (d.isAdmin) const Padding(padding: EdgeInsets.only(top: 4), child: Chip(label: Text('Admin'))),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        if (u == null) ...[
          const Text('Your profile is created automatically when you sign in with Google — the same Google account works on any device. Without signing in, you can still browse and keep favourites on this phone only.'),
          const SizedBox(height: 10),
          ElevatedButton.icon(icon: const Icon(Icons.login), label: const Text('Sign in with Google'), onPressed: () async { try { await d.signInGoogle(); } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-in failed: $e'))); } }),
        ] else ...[
          Row(children: [
            ElevatedButton.icon(icon: const Icon(Icons.message), label: const Text('Messages'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MessagesPage(data: d)))),
            const SizedBox(width: 10),
            TextButton.icon(icon: const Icon(Icons.logout), label: const Text('Sign out'), onPressed: () => d.signOut()),
          ]),
          const SizedBox(height: 6),
          const Text('Messages from other users appear in Messages. To message someone, open Messages and send to their email — they will see it when they sign in with that Google account.'),
        ],
        const SizedBox(height: 20),
        Text('My favourites (${favs.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        if (favs.isEmpty) const Text('No favourites yet. Tap the heart on any item.'),
        ...favs.map((it) => ListTile(leading: const Icon(Icons.favorite, color: Colors.pink), title: Text(it.title), subtitle: Text(d.catName(it.categoryId)), trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () => d.toggleFav(it)), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemPage(data: d, item: it))))),
      ]),
    );
  }
}

class MessagesPage extends StatefulWidget {
  final AppData data;
  const MessagesPage({super.key, required this.data});
  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final toCtrl = TextEditingController();
  final msgCtrl = TextEditingController();
  String status = '';
  @override
  void dispose() {
    toCtrl.dispose();
    msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _send({String? toEmail, String? text}) async {
    final d = widget.data;
    final u = d.user;
    if (u == null) return;
    final to = (toEmail ?? toCtrl.text.trim()).toLowerCase();
    final body = (text ?? msgCtrl.text.trim());
    if (to.isEmpty || body.isEmpty) { setState(() => status = 'Enter a recipient email and a message.'); return; }
    try {
      await FirebaseFirestore.instance.collection('messages').add({
        'fromUid': u.uid,
        'fromName': u.displayName ?? '',
        'fromEmail': (u.email ?? '').toLowerCase(),
        'toEmail': to,
        'text': body,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      setState(() { status = 'Message sent to $to.'; if (toEmail == null) msgCtrl.clear(); });
    } catch (e) {
      setState(() => status = 'Send failed: $e');
    }
  }

  Future<void> _reply(Map<String, dynamic> m) async {
    final replyCtrl = TextEditingController(text: '');
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Reply to ${m['fromEmail'] ?? ''}'), content: TextField(controller: replyCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Your reply', border: OutlineInputBorder())), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send'))]));
    if (ok == true && replyCtrl.text.trim().isNotEmpty) {
      await _send(toEmail: (m['fromEmail'] as String? ?? ''), text: replyCtrl.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final u = d.user;
    if (u == null) {
      return Scaffold(appBar: AppBar(title: const Text('Messages')), body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Sign in to see your messages.'), const SizedBox(height: 12), ElevatedButton.icon(icon: const Icon(Icons.login), label: const Text('Sign in with Google'), onPressed: () async { try { await d.signInGoogle(); setState(() {}); } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-in failed: $e'))); } })])));
    }
    final email = (u.email ?? '').toLowerCase();
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Send a message', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: toCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Recipient email (their Google account)', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: msgCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          ElevatedButton.icon(icon: const Icon(Icons.send), label: const Text('Send'), onPressed: () => _send()),
          if (status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(status)),
          const SizedBox(height: 20),
          const Text('Inbox — messages sent to you', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('messages').where('toEmail', isEqualTo: email).orderBy('createdAt', descending: true).snapshots(),
            builder: (c, snap) {
              if (snap.hasError) return Text('Inbox could not load: ${snap.error}');
              if (!snap.hasData) return const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Padding(padding: EdgeInsets.only(top: 8), child: Text('No messages yet.'));
              return Column(children: docs.map((doc) {
                final m = doc.data() as Map<String, dynamic>;
                final isRead = m['read'] == true;
                return Card(child: ListTile(
                  leading: Icon(isRead ? Icons.mail : Icons.mark_email_unread, color: isRead ? Colors.white54 : Colors.amber),
                  title: Text('${m['fromName'] ?? ''} (${m['fromEmail'] ?? ''})'),
                  subtitle: Text(m['text']?.toString() ?? ''),
                  onTap: () async { try { if (!isRead) await doc.reference.update({'read': true}); } catch (_) {} await _reply(m); },
                ));
              }).toList());
            },
          ),
          const SizedBox(height: 20),
          const Text('Sent', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('messages').where('fromUid', isEqualTo: u.uid).orderBy('createdAt', descending: true).snapshots(),
            builder: (c, snap) {
              if (snap.hasError) return Text('Sent could not load: ${snap.error}');
              if (!snap.hasData) return const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Padding(padding: EdgeInsets.only(top: 8), child: Text('Nothing sent yet.'));
              return Column(children: docs.map((doc) {
                final m = doc.data() as Map<String, dynamic>;
                return ListTile(leading: const Icon(Icons.send), title: Text('To: ${m['toEmail'] ?? ''}'), subtitle: Text(m['text']?.toString() ?? ''));
              }).toList());
            },
          ),
        ]),
      ),
    );
  }
}

class AdminPage extends StatefulWidget {
  final AppData data;
  const AdminPage({super.key, required this.data});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  String msg = '';
  Future<void> _editCat(BuildContext context, Cat? existing) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final img = TextEditingController(text: existing?.imageUrl ?? '');
    final desc = TextEditingController(text: existing?.description ?? '');
    final order = TextEditingController(text: '${existing?.order ?? 0}');
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(existing == null ? 'Add category' : 'Edit category'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')), TextField(controller: img, decoration: const InputDecoration(labelText: 'Cover image URL (optional)')), TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description')), TextField(controller: order, decoration: const InputDecoration(labelText: 'Order'), keyboardType: TextInputType.number)])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))]));
    if (ok != true) return;
    try {
      final id = existing?.id ?? name.text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]'), '-');
      await FirebaseFirestore.instance.collection('categories').doc(id).set({'name': name.text.trim(), 'imageUrl': img.text.trim(), 'description': desc.text.trim(), 'order': int.tryParse(order.text) ?? 0, 'isVisible': true}, SetOptions(merge: true));
      await widget.data.refreshFromFirestore();
      setState(() => msg = 'Category saved.');
    } catch (e) {
      setState(() => msg = 'Save failed: $e');
    }
  }

  Future<void> _editItem(BuildContext context, Item? existing) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final img = TextEditingController(text: existing?.imageUrl ?? '');
    final desc = TextEditingController(text: existing?.description ?? '');
    final url = TextEditingController(text: existing?.url ?? '');
    final type = TextEditingController(text: existing?.type ?? 'series');
    final cat = TextEditingController(text: existing?.categoryId ?? (widget.data.cats.isNotEmpty ? widget.data.cats.first.id : ''));
    final order = TextEditingController(text: '${existing?.order ?? 0}');
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(existing == null ? 'Add item' : 'Edit item'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')), TextField(controller: cat, decoration: const InputDecoration(labelText: 'Category ID (e.g. anime-series)')), TextField(controller: img, decoration: const InputDecoration(labelText: 'Poster image URL (optional)')), TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description')), TextField(controller: url, decoration: const InputDecoration(labelText: 'Link / stream URL (optional)')), TextField(controller: type, decoration: const InputDecoration(labelText: 'Type: series / movie / live')), TextField(controller: order, decoration: const InputDecoration(labelText: 'Order'), keyboardType: TextInputType.number)])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))]));
    if (ok != true) return;
    try {
      final data = {'categoryId': cat.text.trim(), 'title': title.text.trim(), 'imageUrl': img.text.trim(), 'description': desc.text.trim(), 'url': url.text.trim(), 'type': type.text.trim(), 'order': int.tryParse(order.text) ?? 0, 'isVisible': true, 'isLive': type.text.trim() == 'live'};
      if (existing == null) {
        await FirebaseFirestore.instance.collection('items').add(data);
      } else {
        await FirebaseFirestore.instance.collection('items').doc(existing.id).set(data, SetOptions(merge: true));
      }
      await widget.data.refreshFromFirestore();
      setState(() => msg = 'Item saved.');
    } catch (e) {
      setState(() => msg = 'Save failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Admin', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (d.user == null)
          ElevatedButton.icon(icon: const Icon(Icons.login), label: const Text('Sign in with Google'), onPressed: () async {
            try {
              await d.signInGoogle();
            } catch (_) {
              setState(() => msg = d.adminNote);
            }
          })
        else
          Row(children: [Expanded(child: Text('Signed in as ${d.user!.email ?? d.user!.uid}')), TextButton(onPressed: () => d.signOut(), child: const Text('Sign out'))]),
        if (d.user != null) ...[
          const SizedBox(height: 10),
          // Admin is automatic for the owner account — no UID step is shown.
          Text(d.adminNote),
        ],
        if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(msg)),
        if (d.offline) const Padding(padding: EdgeInsets.only(top: 10), child: Text('Firebase is not connected in this build — Admin writes need a live connection. See README.', style: TextStyle(color: Colors.amber))),
        const SizedBox(height: 16),
        if (d.isAdmin) ...[
          Row(children: [ElevatedButton.icon(icon: const Icon(Icons.add), label: const Text('Add category'), onPressed: () => _editCat(context, null)), const SizedBox(width: 10), ElevatedButton.icon(icon: const Icon(Icons.add), label: const Text('Add item'), onPressed: () => _editItem(context, null))]),
          const SizedBox(height: 12),
          const Text('Categories', style: TextStyle(fontWeight: FontWeight.bold)),
          ...d.cats.map((c) => ListTile(title: Text(c.name), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.edit), onPressed: () => _editCat(context, c)), IconButton(icon: const Icon(Icons.delete), onPressed: () async { await FirebaseFirestore.instance.collection('categories').doc(c.id).delete(); await d.refreshFromFirestore(); })]))),
          const Text('Items', style: TextStyle(fontWeight: FontWeight.bold)),
          ...d.items.map((it) => ListTile(title: Text(it.title), subtitle: Text(it.categoryId), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.edit), onPressed: () => _editItem(context, it)), IconButton(icon: const Icon(Icons.delete), onPressed: () async { await FirebaseFirestore.instance.collection('items').doc(it.id).delete(); await d.refreshFromFirestore(); })]))),
        ] else
          const Padding(padding: EdgeInsets.only(top: 12), child: Text('Admin editing is hidden until you are an admin. Sign in with an admin account. Until then, catalog reads still work and the app shows demo data if Firebase is offline.')),
      ]),
    );
  }
}
