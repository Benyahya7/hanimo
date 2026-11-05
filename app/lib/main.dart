import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:easy_chromecast_plugin/easy_chromecast_plugin.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final String id, categoryId, title, description, imageUrl, url, type, subtitleUrl;
  final bool isLive, isVisible;
  final int order;
  final int malId; // MyAnimeList id (Jikan) — 0 when not a Jikan title
  final double score; // MAL score, 0 when unknown
  final int year;
  final List<String> genres;
  final int episodeCount;
  Item({required this.id, required this.categoryId, required this.title, this.description = '', this.imageUrl = '', this.url = '', this.type = 'series', this.subtitleUrl = '', this.isLive = false, this.isVisible = true, this.order = 0, this.malId = 0, this.score = 0, this.year = 0, this.genres = const [], this.episodeCount = 0});
  bool get isTorrent => url.toLowerCase().startsWith('magnet:') || url.toLowerCase().endsWith('.torrent');
  factory Item.fromMap(String id, Map<String, dynamic> m) => Item(
        id: id,
        categoryId: (m['categoryId'] ?? '') as String,
        title: (m['title'] ?? '') as String,
        description: (m['description'] ?? '') as String,
        imageUrl: (m['imageUrl'] ?? '') as String,
        url: (m['url'] ?? '') as String,
        type: (m['type'] ?? 'series') as String,
        subtitleUrl: (m['subtitleUrl'] ?? '') as String,
        malId: (m['malId'] as num?)?.toInt() ?? 0,
        score: (m['score'] as num?)?.toDouble() ?? 0,
        year: (m['year'] as num?)?.toInt() ?? 0,
        genres: List<String>.from((m['genres'] as List?) ?? []),
        episodeCount: (m['episodeCount'] as num?)?.toInt() ?? 0,
        isLive: (m['isLive'] as bool?) ?? false,
        isVisible: (m['isVisible'] as bool?) ?? true,
        order: (m['order'] as num?)?.toInt() ?? 0,
      );
  Map<String, dynamic> toMap() => {'categoryId': categoryId, 'title': title, 'description': description, 'imageUrl': imageUrl, 'url': url, 'type': type, 'subtitleUrl': subtitleUrl, 'isLive': isLive, 'isVisible': isVisible, 'order': order, 'malId': malId, 'score': score, 'year': year, 'genres': genres, 'episodeCount': episodeCount};
  Map<String, dynamic> toJson() => {...toMap(), 'id': id};
  factory Item.fromJson(Map<String, dynamic> j) => Item.fromMap(j['id'] as String? ?? '', j);
}

// Carousel banner — editable from Admin (Firestore 'banners').
// imageUrl may be a web URL, or 'asset:hero.webp' for a built-in banner.
class BannerSlide {
  final String id, imageUrl, title, subtitle, targetCategoryId;
  final int order;
  BannerSlide({required this.id, required this.imageUrl, this.title = '', this.subtitle = '', this.targetCategoryId = '', this.order = 0});
  factory BannerSlide.fromMap(String id, Map<String, dynamic> m) => BannerSlide(id: id, imageUrl: (m['imageUrl'] ?? '') as String, title: (m['title'] ?? '') as String, subtitle: (m['subtitle'] ?? '') as String, targetCategoryId: (m['targetCategoryId'] ?? '') as String, order: (m['order'] as num?)?.toInt() ?? 0);
  Map<String, dynamic> toMap() => {'imageUrl': imageUrl, 'title': title, 'subtitle': subtitle, 'targetCategoryId': targetCategoryId, 'order': order};
}

// Add-on — Stremio-style manifest (Firestore 'addons').
// A manifest is JSON with id, name, version and catalogs. Catalogs become
// browseable lists; streams are fetched on demand. Torrent streams
// (infoHash / magnet) are opened in an external torrent app, not played in-app.
class Addon {
  final String id, name, manifestUrl, description;
  final bool enabled;
  Addon({required this.id, required this.name, required this.manifestUrl, this.description = '', this.enabled = true});
  factory Addon.fromMap(String id, Map<String, dynamic> m) => Addon(id: id, name: (m['name'] ?? '') as String, manifestUrl: (m['manifestUrl'] ?? '') as String, description: (m['description'] ?? '') as String, enabled: (m['enabled'] as bool?) ?? true);
  Map<String, dynamic> toMap() => {'name': name, 'manifestUrl': manifestUrl, 'description': description, 'enabled': enabled};
}

// Update notice — Firestore 'updates', shown in the Updates inbox (bell).
class UpdateNotice {
  final String id, versionName, notes, downloadUrl;
  final int build;
  UpdateNotice({required this.id, required this.versionName, required this.notes, required this.downloadUrl, required this.build});
  factory UpdateNotice.fromMap(String id, Map<String, dynamic> m) => UpdateNotice(id: id, versionName: (m['versionName'] ?? '') as String, notes: (m['notes'] ?? '') as String, downloadUrl: (m['downloadUrl'] ?? '') as String, build: (m['build'] as num?)?.toInt() ?? 0);
  Map<String, dynamic> toMap() => {'versionName': versionName, 'notes': notes, 'downloadUrl': downloadUrl, 'build': build};
}

// Episode — a custom link for one episode, set by Admin in
// Firestore items/{itemId}/episodes/{episodeNumber}. The episode list
// itself (numbers, titles, air dates) comes live from Jikan when the
// item has a malId; custom links attach to it by episode number.
class Episode {
  final int number;
  final String title, url, subtitleUrl;
  Episode({required this.number, this.title = '', this.url = '', this.subtitleUrl = ''});
  factory Episode.fromMap(int number, Map<String, dynamic> m) => Episode(number: number, title: (m['title'] ?? '') as String, url: (m['url'] ?? '') as String, subtitleUrl: (m['subtitleUrl'] ?? '') as String);
  Map<String, dynamic> toMap() => {'title': title, 'url': url, 'subtitleUrl': subtitleUrl};
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

// Jikan (MyAnimeList) public API — no key. Episode list for one title.
Future<List<Map<String, dynamic>>> fetchJikanEpisodes(int malId) async {
  final out = <Map<String, dynamic>>[];
  var page = 1;
  while (page <= 5) {
    final res = await http.get(Uri.parse('https://api.jikan.moe/v4/anime/$malId/episodes?page=$page'));
    if (res.statusCode != 200) break;
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final data = (body['data'] as List?) ?? [];
    for (final e in data) {
      out.add({'number': (e['mal_id'] as num?)?.toInt() ?? 0, 'title': (e['title'] ?? '') as String, 'aired': (e['aired'] ?? '') as String});
    }
    final pagination = body['pagination'] as Map<String, dynamic>?;
    if (pagination == null || (pagination['has_next_page'] as bool?) != true) break;
    page++;
    await Future.delayed(const Duration(milliseconds: 400)); // Jikan rate limit: 3 req/sec
  }
  return out;
}

// ---------- App state (simple, held in the root widget) ----------
const int kCurrentBuild = 7; // must match pubspec build number (1.0.6+7)

class AppData extends ChangeNotifier {
  List<Cat> cats = List.of(seedCats);
  List<Item> items = List.of(seedItems);
  List<BannerSlide> banners = [];
  List<Addon> addons = [];
  List<UpdateNotice> updateNotices = [];
  int unreadUpdates = 0;
  List<Item> imported = [];
  List<Item> recent = [];
  // Watch progress: key "itemId:episodeNumber" -> position in seconds.
  // Local only (same privacy rule as favourites), used by Continue Watching.
  Map<String, int> progress = {};
  Map<String, int> progressDuration = {};
  Map<String, int> lastEpisode = {};
  Set<String> favIds = {};
  Map<String, Item> favItems = {};
  bool offline = true;
  bool loading = true;
  String status = 'Loading…';
  // In-app update (Telegram-style): set in Firestore config/app_update.
  // Banner shows only when latestBuild > kCurrentBuild.
  int latestBuild = 0;
  String latestVersionName = '';
  String updateUrl = '';
  String updateNotes = '';
  int dismissedUpdateBuild = 0;
  User? user;
  bool isAdmin = false;
  String adminNote = 'Sign in to check admin status.';

  String catName(String id) => cats.firstWhere((c) => c.id == id, orElse: () => Cat(id: id, name: id)).name;

  Future<void> init() async {
    // google_sign_in 7 on Android REQUIRES serverClientId: without it,
    // authenticate() throws clientConfigurationError ("serverClientId
    // must be provided on Android, null") — the exact 1.0.2 failure.
    // This is the Firebase auto-created Web client for anime-app-556c8
    // (a public Client ID, not a secret), verified in Cloud Console.
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId:
            '176785196605-osm2pkehqes1p5npu9e3pbqrgecsjd19.apps.googleusercontent.com',
      );
    } catch (_) {}
    await _loadLocal();
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      await Future.wait([refreshFromFirestore(), checkUpdate()]);
      offline = false;
      status = 'Ready';
    } catch (e) {
      offline = true;
      status = 'Ready';
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

  // Language: 'en' or 'ar'. Arabic flips the whole app to RTL.
  String lang = 'en';
  static const _strings = <String, Map<String, String>>{
    'home': {'en': 'Home', 'ar': 'الرئيسية'},
    'browse': {'en': 'Browse', 'ar': 'تصفح'},
    'search': {'en': 'Search', 'ar': 'بحث'},
    'favourites': {'en': 'Favourites', 'ar': 'المفضلة'},
    'profile': {'en': 'Profile', 'ar': 'الملف الشخصي'},
    'admin': {'en': 'Admin', 'ar': 'المسؤول'},
    'friends': {'en': 'Friends', 'ar': 'الأصدقاء'},
    'messages': {'en': 'Messages', 'ar': 'الرسائل'},
    'updates': {'en': 'Updates', 'ar': 'التحديثات'},
    'settings': {'en': 'Settings', 'ar': 'الإعدادات'},
    'myAccount': {'en': 'My account', 'ar': 'حسابي'},
    'animeList': {'en': 'Anime list', 'ar': 'قائمة الأنمي'},
    'latestEpisodes': {'en': 'Latest episodes', 'ar': 'آخر الحلقات'},
    'watchHistory': {'en': 'Watch history', 'ar': 'سجل المشاهدة'},
    'currentlyWatching': {'en': 'Currently watching', 'ar': 'أشاهد حالياً'},
    'completed': {'en': 'Completed', 'ar': 'مكتملة'},
    'watchLater': {'en': 'Watch Later', 'ar': 'للمشاهدة لاحقاً'},
    'myFavourites': {'en': 'My Favourites', 'ar': 'أنمياتي المفضلة'},
    'continueWatching': {'en': 'Continue Watching', 'ar': 'متابعة المشاهدة'},
    'latestUpdates': {'en': 'Latest Updates', 'ar': 'آخر التحديثات'},
    'airingToday': {'en': 'Airing Today', 'ar': 'يعرض اليوم'},
    'fall2026': {'en': 'Fall 2026', 'ar': 'خريف 2026'},
    'latestNews': {'en': 'Latest Anime News', 'ar': 'آخر أخبار الأنمي'},
    'trendingNow': {'en': 'Trending Now', 'ar': 'الرائج الآن'},
    'signOut': {'en': 'Sign out', 'ar': 'تسجيل الخروج'},
    'signIn': {'en': 'Sign in with Google', 'ar': 'تسجيل الدخول عبر Google'},
    'officialWebsite': {'en': 'Official website', 'ar': 'الموقع الرسمي'},
    'contactUs': {'en': 'Contact us', 'ar': 'راسلنا'},
    'privacyPolicy': {'en': 'Privacy policy', 'ar': 'سياسة الخصوصية'},
    'watching': {'en': 'Watching', 'ar': 'أشاهد'},
    'history': {'en': 'History', 'ar': 'السجل'},
    'episodes': {'en': 'Episodes', 'ar': 'الحلقات'},
    'watched': {'en': 'Watched', 'ar': 'شوهد'},
    'dashboard': {'en': 'Dashboard', 'ar': 'لوحة التحكم'},
    'viewAll': {'en': 'View all ›', 'ar': 'عرض الكل ‹'},
    'searchTitles': {'en': 'Search titles…', 'ar': 'ابحث عن عنوان…'},
  };
  String tr(String key) => _strings[key]?[lang] ?? _strings[key]?['en'] ?? key;

  Future<void> setLang(String l) async {
    lang = l;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lang', l);
    notifyListeners();
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    lang = prefs.getString('lang') ?? 'en';
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
    final lastEpJson = prefs.getString('lastEp') ?? '';
    for (final part in lastEpJson.split(',')) {
      final kv = part.split('=');
      if (kv.length == 2) lastEpisode[kv[0]] = int.tryParse(kv[1]) ?? 0;
    }
    final progJson = prefs.getString('progress') ?? '';
    for (final part in progJson.split(',')) {
      final kv = part.split('=');
      if (kv.length == 2) progress[kv[0]] = int.tryParse(kv[1]) ?? 0;
    }
    final progDurJson = prefs.getString('progressDur') ?? '';
    for (final part in progDurJson.split(',')) {
      final kv = part.split('=');
      if (kv.length == 2) progressDuration[kv[0]] = int.tryParse(kv[1]) ?? 0;
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
    final results = await Future.wait([
      FirebaseFirestore.instance.collection('categories').get(),
      FirebaseFirestore.instance.collection('items').get(),
      FirebaseFirestore.instance.collection('banners').get(),
      FirebaseFirestore.instance.collection('addons').get(),
      FirebaseFirestore.instance.collection('updates').orderBy('createdAt', descending: true).limit(20).get(),
    ]);
    final cs = results[0];
    final is_ = results[1];
    final bs = results[2];
    final as_ = results[3];
    final us = results[4];
    final newCats = cs.docs.map((d) => Cat.fromMap(d.id, d.data())).toList()..sort((a, b) => a.order.compareTo(b.order));
    final newItems = is_.docs.map((d) => Item.fromMap(d.id, d.data())).toList()..sort((a, b) => a.order.compareTo(b.order));
    if (newCats.isNotEmpty) cats = newCats;
    if (newItems.isNotEmpty) items = newItems;
    try {
      banners = bs.docs.map((d) => BannerSlide.fromMap(d.id, d.data())).toList()..sort((a, b) => a.order.compareTo(b.order));
      addons = as_.docs.map((d) => Addon.fromMap(d.id, d.data())).toList();
      updateNotices = us.docs.map((d) => UpdateNotice.fromMap(d.id, d.data())).toList();
      final prefs = await SharedPreferences.getInstance();
      final lastSeen = prefs.getInt('lastSeenUpdateBuild') ?? 0;
      unreadUpdates = updateNotices.where((u) => u.build > lastSeen).length;
    } catch (_) {}
    offline = false;
    notifyListeners();
    checkNewEpisodes(); // favourites with new episodes (Jikan, once per session)
  }

  // New-episode alerts: for favourites with a MyAnimeList ID, compare the
  // live episode count on Jikan with the stored one. If it grew, show a
  // local alert and (for admins) update the stored count so badges refresh.
  List<Map<String, dynamic>> newEpAlerts = [];
  bool _checkedNewEps = false;

  Future<void> checkNewEpisodes() async {
    if (_checkedNewEps) return;
    _checkedNewEps = true;
    final favs = favItems.values.where((it) => it.malId > 0 && it.type != 'movie').take(5).toList();
    for (final it in favs) {
      try {
        final res = await http.get(Uri.parse('https://api.jikan.moe/v4/anime/${it.malId}'));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final live = ((data['data'] as Map<String, dynamic>?)?['episodes'] as num?)?.toInt();
        if (live != null && it.episodeCount > 0 && live > it.episodeCount) {
          newEpAlerts.add({'item': it, 'oldCount': it.episodeCount, 'newCount': live});
          if (isAdmin) {
            try {
              await FirebaseFirestore.instance.collection('items').doc(it.id).set({'episodeCount': live}, SetOptions(merge: true));
            } catch (_) {}
          }
        }
        await Future.delayed(const Duration(milliseconds: 400));
      } catch (_) {}
    }
    if (newEpAlerts.isNotEmpty) notifyListeners();
  }

  // In-app update check: reads Firestore config/app_update.
  // Missing doc or latestBuild <= current build means no banner.
  Future<void> checkUpdate() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('config').doc('app_update').get();
      if (!doc.exists) return;
      final data = doc.data() ?? {};
      latestBuild = (data['latestBuild'] as num?)?.toInt() ?? 0;
      latestVersionName = (data['latestVersionName'] as String?) ?? '';
      updateUrl = (data['downloadUrl'] as String?) ?? '';
      updateNotes = (data['notes'] as String?) ?? '';
      final prefs = await SharedPreferences.getInstance();
      dismissedUpdateBuild = prefs.getInt('dismissedUpdateBuild') ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> dismissUpdate() async {
    dismissedUpdateBuild = latestBuild;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('dismissedUpdateBuild', latestBuild);
    notifyListeners();
  }

  bool get hasUpdate => latestBuild > kCurrentBuild && updateUrl.isNotEmpty && dismissedUpdateBuild != latestBuild;

  Future<void> markUpdatesRead() async {
    final prefs = await SharedPreferences.getInstance();
    final maxBuild = updateNotices.fold<int>(0, (m, u) => u.build > m ? u.build : m);
    await prefs.setInt('lastSeenUpdateBuild', maxBuild);
    unreadUpdates = 0;
    notifyListeners();
  }

  String _progressKey(String itemId, int ep) => '$itemId:$ep';

  Future<void> saveProgress(String itemId, int ep, int seconds, int durationSeconds) async {
    final key = _progressKey(itemId, ep);
    progress[key] = seconds;
    progressDuration[key] = durationSeconds;
    lastEpisode[itemId] = ep;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('progress', progress.entries.map((e) => '${e.key}=${e.value}').join(','));
    await prefs.setString('progressDur', progressDuration.entries.map((e) => '${e.key}=${e.value}').join(','));
    await prefs.setString('lastEp', lastEpisode.entries.map((e) => '${e.key}=${e.value}').join(','));
    notifyListeners();
  }

  double progressFraction(String itemId, int ep) {
    final d = progressDuration[_progressKey(itemId, ep)] ?? 0;
    if (d <= 0) return 0;
    return ((progress[_progressKey(itemId, ep)] ?? 0) / d).clamp(0.0, 1.0);
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

  // Every signed-in user gets a public Hanimo ID (HNM-XXXXXX) so friends
  // can find and chat with them without sharing an email address.
  String? hanimoId;
  List<Map<String, dynamic>> friends = [];

  String _makeHanimoId(String uid) {
    final h = uid.hashCode.abs().toRadixString(36).toUpperCase().padLeft(6, '0');
    return 'HNM-${h.substring(0, 6)}';
  }

  Future<void> ensureProfile() async {
    if (user == null) return;
    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(user!.uid);
      final snap = await ref.get();
      hanimoId = (snap.data()?['hanimoId'] as String?) ?? _makeHanimoId(user!.uid);
      await ref.set({
        'displayName': user!.displayName ?? '',
        'email': user!.email ?? '',
        'photoURL': user!.photoURL ?? '',
        'hanimoId': hanimoId,
        'lastSignIn': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await setPresence(true);
      await loadFriends();
    } catch (_) {}
    notifyListeners();
  }

  // Presence lives in a separate public collection so friends can see
  // online / last-seen without reading anyone's private profile.
  Future<void> setPresence(bool online) async {
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('presence').doc(user!.uid).set({
        'hanimoId': hanimoId ?? _makeHanimoId(user!.uid),
        'displayName': user!.displayName ?? '',
        'photoURL': user!.photoURL ?? '',
        'online': online,
        'lastSeen': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> loadFriends() async {
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('friends').get();
      friends = snap.docs.map((d) => {'uid': d.id, ...d.data()}).toList();
    } catch (_) {}
    notifyListeners();
  }

  // Returns a status message for the UI.
  Future<String> addFriendById(String rawId) async {
    if (user == null) return 'Sign in first.';
    final id = rawId.trim().toUpperCase();
    if (id.isEmpty) return 'Enter a Hanimo ID.';
    try {
      final q = await FirebaseFirestore.instance.collection('presence').where('hanimoId', isEqualTo: id).limit(1).get();
      if (q.docs.isEmpty) return 'No user with ID $id.';
      final doc = q.docs.first;
      if (doc.id == user!.uid) return 'That is your own ID.';
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('friends').doc(doc.id).set({
        'friendUid': doc.id,
        'hanimoId': id,
        'displayName': doc.data()['displayName'] ?? '',
        'photoURL': doc.data()['photoURL'] ?? '',
        'addedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await loadFriends();
      return 'Added ${doc.data()['displayName'] ?? id} as a friend.';
    } catch (e) {
      return 'Could not add friend: $e';
    }
  }

  Future<void> removeFriend(String friendUid) async {
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('friends').doc(friendUid).delete();
      await loadFriends();
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
      adminNote = isAdmin ? 'You are an admin.' : 'Admin check failed. Try again.';
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

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Background notifications are shown by the system when the message
  // carries a notification payload. Tapping it opens the app with
  // message.data['downloadUrl'], handled in _setupPush below.
}

Future<void> _setupPush(AppData data) async {
  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    await messaging.subscribeToTopic('app_updates');
    FirebaseMessaging.onMessage.listen((m) async {
      await data.checkUpdate();
      await data.refreshFromFirestore();
    });
    FirebaseMessaging.onMessageOpenedApp.listen((m) async {
      final url = m.data['downloadUrl'] as String?;
      if (url != null && url.isNotEmpty) {
        final uri = Uri.tryParse(url);
        if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri);
      }
    });
    final initial = await messaging.getInitialMessage();
    final url = initial?.data['downloadUrl'] as String?;
    if (url != null && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri);
    }
  } catch (_) {}
}

final EasyChromecastPlugin castPlugin = EasyChromecastPlugin();

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
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    _setupPush(data);
    castPlugin.initializeCast(); // Google Cast framework — device picker + real Chromecast
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: data,
      builder: (context, _) => MaterialApp(
        title: 'Hanimo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF0B0B10),
          colorScheme: const ColorScheme.dark(primary: Color(0xFFE50914), secondary: Color(0xFFE50914), surface: Color(0xFF16161F)),
          cardTheme: const CardThemeData(color: Color(0xFF16161F)),
          appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
        ),
        locale: Locale(data.lang),
        builder: (context, child) => Directionality(
          textDirection: data.lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
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
    memCacheWidth: 260,
    memCacheHeight: 360,
    fadeInDuration: const Duration(milliseconds: 150),
    placeholder: (c, u) => Container(height: height, color: const Color(0xFF2A2A3E)),
    errorWidget: (c, u, e) => Container(height: height, color: const Color(0xFF2A2A3E), child: const Center(child: Icon(Icons.broken_image, color: Colors.white54))),
  );
}

Widget catCover(Cat c, {double height = 110}) {
  if (c.imageUrl.isEmpty) {
    return Container(height: height, color: const Color(0xFF2A2A3E), child: Center(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center)));
  }
  return CachedNetworkImage(imageUrl: c.imageUrl, height: height, width: double.infinity, fit: BoxFit.cover, memCacheWidth: 120, memCacheHeight: 120, fadeInDuration: const Duration(milliseconds: 150), errorWidget: (c, u, e) => Container(height: height, color: const Color(0xFF2A2A3E), child: const Icon(Icons.broken_image)));
}

// ---------- Glass (Animefy-style transparent effect) ----------
// Translucent surface + hairline border + blur, used for cards, chips,
// the top bar and the bottom bar so content shows through faintly.
BoxDecoration glassDeco({double radius = 16}) => BoxDecoration(
      color: Colors.white.withOpacity(0.06),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withOpacity(0.08)),
    );

Widget sectionHeader(String title, {VoidCallback? onViewAll}) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 8),
      child: Row(children: [
        Container(width: 4, height: 20, decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
        if (onViewAll != null) GestureDetector(onTap: onViewAll, child: const Text('View all ›', style: TextStyle(color: Colors.white54))),
      ]),
    );

// ---------- Root ----------
class RootPage extends StatefulWidget {
  final AppData data;
  const RootPage({super.key, required this.data});
  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.data.setPresence(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.data.setPresence(true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.detached) {
      widget.data.setPresence(false);
    }
  }

  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    // Admin tab is hidden for normal users — it appears only once the
    // owner/admin account is signed in, exactly like a regular user sees it.
    final pages = <Widget>[HomePage(data: d, goTab: (i) => setState(() => tab = i)), BrowsePage(data: d), SearchPage(data: d), MyListPage(data: d), ImportPage(data: d), ProfilePage(data: d)];
    final navItems = <BottomNavigationBarItem>[
      BottomNavigationBarItem(icon: const Icon(Icons.home), label: d.tr('home')),
      BottomNavigationBarItem(icon: const Icon(Icons.grid_view), label: d.tr('browse')),
      BottomNavigationBarItem(icon: const Icon(Icons.search), label: d.tr('search')),
      BottomNavigationBarItem(icon: const Icon(Icons.favorite), label: d.tr('favourites')),
      const BottomNavigationBarItem(icon: Icon(Icons.playlist_add), label: 'Import'),
      BottomNavigationBarItem(icon: const Icon(Icons.person), label: d.tr('profile')),
    ];
    if (d.isAdmin) {
      pages.add(AdminPage(data: d));
      navItems.add(BottomNavigationBarItem(icon: const Icon(Icons.admin_panel_settings), label: d.tr('admin')));
    }
    if (tab >= pages.length) tab = 0;
    return Scaffold(
      extendBody: true,
      drawer: _HanimoDrawer(data: d, goTab: (i) => setState(() => tab = i)),
      appBar: AppBar(
          flexibleSpace: ClipRect(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: Container(color: Colors.black.withOpacity(0.45)))),
          title: Row(mainAxisSize: MainAxisSize.min, children: [ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/icon/hanimo-icon.png', width: 32, height: 32, fit: BoxFit.cover)), const SizedBox(width: 10), const Text('Hanimo', style: TextStyle(color: Color(0xFFE50914), fontWeight: FontWeight.w900))]),
          actions: [
            Stack(children: [
              IconButton(icon: const Icon(Icons.notifications), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UpdatesPage(data: d)))),
              if (d.unreadUpdates > 0)
                Positioned(right: 6, top: 6, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Color(0xFFE50914), shape: BoxShape.circle), child: Text('${d.unreadUpdates}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))),
            ]),
            IconButton(icon: const Icon(Icons.refresh), onPressed: () async { try { await d.refreshFromFirestore(); await d.checkUpdate(); } catch (_) {} }),
          ]),
      body: d.loading ? const Center(child: CircularProgressIndicator()) : IndexedStack(index: tab, children: pages),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        // Telegram-style in-app update: tappable, Update opens the new APK.
        if (d.hasUpdate)
          Container(
            width: double.infinity,
            color: const Color(0xFFE50914),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              const Icon(Icons.system_update, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: GestureDetector(
                onTap: () async { final uri = Uri.parse(d.updateUrl); if (await canLaunchUrl(uri)) await launchUrl(uri); },
                child: Text('New update available — Hanimo ${d.latestVersionName.isEmpty ? '' : d.latestVersionName} Tap to update', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )),
              TextButton(onPressed: () async { final uri = Uri.parse(d.updateUrl); if (await canLaunchUrl(uri)) await launchUrl(uri); }, child: const Text('Update', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              TextButton(onPressed: () => d.dismissUpdate(), child: const Text('Later', style: TextStyle(color: Colors.white70))),
            ]),
          ),
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: BottomNavigationBar(
              currentIndex: tab,
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.black.withOpacity(0.55),
              selectedItemColor: const Color(0xFFE50914),
              unselectedItemColor: Colors.white54,
              elevation: 0,
              onTap: (i) => setState(() => tab = i),
              items: navItems,
            ),
          ),
        ),
      ]),
    );
  }
}

// ---------- Side drawer (Animefy-style) ----------
class _HanimoDrawer extends StatelessWidget {
  final AppData data;
  final void Function(int) goTab;
  const _HanimoDrawer({required this.data, required this.goTab});

  Widget _row(BuildContext context, IconData icon, String label, {String? badge, VoidCallback? onTap}) => ListTile(
        leading: Icon(icon, color: Colors.white70),
        title: Text(label),
        trailing: badge == null ? null : Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(10)), child: Text(badge, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
        onTap: () { Navigator.pop(context); onTap?.call(); },
      );

  @override
  Widget build(BuildContext context) {
    final d = data;
    final u = d.user;
    final watching = d.progress.keys.where((k) => (d.progressDuration[k] ?? 0) > 0 && d.progressFraction(k.split(':').first, int.tryParse(k.split(':').last) ?? 0) < 0.95).length;
    final completed = d.progress.keys.where((k) => d.progressFraction(k.split(':').first, int.tryParse(k.split(':').last) ?? 0) >= 0.95).length;
    return Drawer(
      backgroundColor: const Color(0xFF12121A),
      child: ListView(padding: EdgeInsets.zero, children: [
        DrawerHeader(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFE50914), Color(0xFF7A0A12)])),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 32,
              backgroundImage: (u?.photoURL != null && u!.photoURL!.isNotEmpty) ? NetworkImage(u.photoURL!) : null,
              child: (u?.photoURL == null || u!.photoURL!.isEmpty) ? Text((u?.displayName ?? u?.email ?? 'H').substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)) : null,
            ),
            const SizedBox(height: 10),
            Text(u?.displayName ?? u?.email ?? 'Guest', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (u?.email != null) Text(u!.email!, style: const TextStyle(color: Colors.white70)),
            if (d.isAdmin) const Chip(label: Text('Admin'), backgroundColor: Colors.white24),
          ]),
        ),
        _row(context, Icons.person, d.tr('myAccount'), onTap: () => goTab(5)),
        _row(context, Icons.people, d.tr('friends'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FriendsPage(data: data)))),
        _row(context, Icons.local_fire_department, d.tr('latestEpisodes'), badge: d.items.where((e) => e.malId > 0).isEmpty ? null : '${d.items.where((e) => e.malId > 0).length}', onTap: () => goTab(0)),
        _row(context, Icons.home, d.tr('home'), onTap: () => goTab(0)),
        _row(context, Icons.tv, d.tr('animeList'), onTap: () => goTab(1)),
        _row(context, Icons.favorite, d.tr('myFavourites'), badge: d.favItems.isEmpty ? null : '${d.favItems.length}', onTap: () => goTab(3)),
        _row(context, Icons.history, d.tr('watchHistory'), badge: d.recent.isEmpty ? null : '${d.recent.length}', onTap: () => goTab(3)),
        _row(context, Icons.bolt, d.tr('currentlyWatching'), badge: watching == 0 ? null : '$watching', onTap: () => goTab(0)),
        _row(context, Icons.check_circle, d.tr('completed'), badge: completed == 0 ? null : '$completed', onTap: () => goTab(0)),
        const Divider(color: Colors.white12),
        _row(context, Icons.settings, d.tr('settings'), onTap: () => goTab(5)),
        _row(context, Icons.language, d.tr('officialWebsite'), onTap: () async { final uri = Uri.parse('https://benyahya7.github.io/hanimo/'); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }),
        _row(context, Icons.mail, d.tr('contactUs'), onTap: () async { final uri = Uri.parse('https://github.com/Benyahya7/hanimo'); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }),
        _row(context, Icons.privacy_tip, d.tr('privacyPolicy'), onTap: () => showDialog(context: context, builder: (c) => const AlertDialog(title: Text('Privacy policy'), content: SingleChildScrollView(child: Text('Hanimo stores your favourites and watch progress only on your device. Your profile is visible only to you, and messages are readable only by their sender and recipient. The owner never shares your info with other users.'))))),
        ListTile(
          leading: const Icon(Icons.translate, color: Colors.white70),
          title: const Text('Language / اللغة'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            ChoiceChip(label: const Text('EN'), selected: d.lang == 'en', onSelected: (_) => d.setLang('en')),
            const SizedBox(width: 6),
            ChoiceChip(label: const Text('عربي'), selected: d.lang == 'ar', onSelected: (_) => d.setLang('ar')),
          ]),
        ),
        if (u != null) _row(context, Icons.logout, d.tr('signOut'), onTap: () => d.signOut()),
      ]),
    );
  }
}

// ---------- Updates inbox (Telegram-style) ----------
class UpdatesPage extends StatefulWidget {
  final AppData data;
  const UpdatesPage({super.key, required this.data});
  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.data.markUpdatesRead());
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Scaffold(
      appBar: AppBar(title: const Text('Updates')),
      body: d.updateNotices.isEmpty
          ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No updates yet. When a new version is published, it will appear here — tap it to download.', textAlign: TextAlign.center)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: d.updateNotices.length,
              itemBuilder: (c, i) {
                final u = d.updateNotices[i];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.system_update, color: Color(0xFFE50914)),
                    title: Text('Hanimo ${u.versionName}'),
                    subtitle: Text(u.notes.isEmpty ? 'A new version is available.' : u.notes),
                    trailing: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)),
                      onPressed: () async { final uri = Uri.tryParse(u.downloadUrl); if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri); },
                      child: const Text('Download'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}


// Home hero carousel — its own widget, so the 4-second auto-slide timer
// only rebuilds the carousel, not the whole Home page (that was the main
// cause of the slowness: every slide change rebuilt every row and poster).
class _HomeCarousel extends StatefulWidget {
  final AppData data;
  final void Function(int) goTab;
  const _HomeCarousel({required this.data, required this.goTab});
  @override
  State<_HomeCarousel> createState() => _HomeCarouselState();
}

class _HomeCarouselState extends State<_HomeCarousel> {
  late final PageController _ctrl;
  Timer? _timer;
  int _slide = 0;
  static const _banners = [
    ('assets/banners/hero.webp', 'Hanimo Originals', 'Your anime universe, in one app'),
    ('assets/banners/cyberpunk.webp', 'Cyber City', 'Neon nights, high stakes, non-stop action'),
    ('assets/banners/fantasy.webp', 'Sky Kingdom', 'Dragons, castles and an epic quest'),
    ('assets/banners/series.webp', 'Top Series', 'Series everyone is watching right now'),
    ('assets/banners/movie.webp', 'Movie Night', 'Big-screen anime, cozy at home'),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = PageController();
    // Only the first banner is decoded up front; the rest load as you swipe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) precacheImage(const AssetImage('assets/banners/hero.webp'), context);
    });
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final count = widget.data.banners.isNotEmpty ? widget.data.banners.length : _banners.length;
      _slide = (_slide + 1) % count;
      _ctrl.animateToPage(_slide, duration: const Duration(milliseconds: 700), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // --- Hero carousel / slider ---
    return SizedBox(
          height: 400,
          child: Stack(children: [
            PageView.builder(
              controller: _ctrl,
              onPageChanged: (i) => setState(() => _slide = i),
              itemCount: widget.data.banners.isNotEmpty ? widget.data.banners.length : _banners.length,
              itemBuilder: (context, i) {
                final useRemote = widget.data.banners.isNotEmpty;
                final slide = useRemote ? widget.data.banners[i] : null;
                final title = useRemote ? slide!.title : _banners[i].$2;
                final subtitle = useRemote ? slide!.subtitle : _banners[i].$3;
                final image = useRemote
                    ? (slide!.imageUrl.startsWith('asset:') ? Image.asset('assets/banners/${slide.imageUrl.substring(6)}', fit: BoxFit.cover, cacheWidth: 1080) : CachedNetworkImage(imageUrl: slide.imageUrl, fit: BoxFit.cover, memCacheWidth: 1080, errorWidget: (c, u, e) => Image.asset(_banners[0].$1, fit: BoxFit.cover, cacheWidth: 1080)))
                    : Image.asset(_banners[i].$1, fit: BoxFit.cover, cacheWidth: 1080);
                return GestureDetector(
                onTap: () {
                  if (useRemote && slide!.targetCategoryId.isNotEmpty) {
                    final cat = widget.data.cats.firstWhere((c) => c.id == slide.targetCategoryId, orElse: () => widget.data.cats.first);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryPage(data: widget.data, cat: cat)));
                  } else {
                    widget.goTab(1);
                  }
                },
                child: Stack(fit: StackFit.expand, children: [
                  image,
                  Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black54, Color(0xFF141414)]))),
                  Positioned(
                    left: 16, right: 16, bottom: 48,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(4)), child: const Text('NEW', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12))),
                      const SizedBox(height: 8),
                      Text(title, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, shadows: [Shadow(blurRadius: 8, color: Colors.black)])),
                      Text(subtitle, style: const TextStyle(fontSize: 15, color: Colors.white70)),
                      const SizedBox(height: 12),
                      Row(children: [
                        ElevatedButton.icon(icon: const Icon(Icons.play_arrow, color: Colors.black), label: const Text('Play', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), style: ElevatedButton.styleFrom(backgroundColor: Colors.white), onPressed: () => widget.goTab(1)),
                        const SizedBox(width: 10),
                        OutlinedButton.icon(icon: const Icon(Icons.add, color: Colors.white), label: const Text('My List', style: TextStyle(color: Colors.white)), onPressed: () => widget.goTab(3)),
                      ]),
                    ]),
                  ),
                ]),
              );
              },
            ),
            Positioned(
              left: 0, right: 0, bottom: 12,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(widget.data.banners.isNotEmpty ? widget.data.banners.length : _banners.length, (i) => AnimatedContainer(duration: const Duration(milliseconds: 300), margin: const EdgeInsets.symmetric(horizontal: 3), width: _slide == i ? 22 : 8, height: 8, decoration: BoxDecoration(color: _slide == i ? const Color(0xFFE50914) : Colors.white54, borderRadius: BorderRadius.circular(4))))),
            ),
          ]),
        );
  }
}

class HomePage extends StatefulWidget {
  final AppData data;
  final void Function(int) goTab;
  const HomePage({super.key, required this.data, required this.goTab});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _genre = 'All';
  static const _genres = ['All', 'Action', 'Adventure', 'Comedy', 'Drama', 'Fantasy'];
  static const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final trending = d.items.take(10).toList();
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _HomeCarousel(data: d, goTab: widget.goTab),
        // --- Tappable update message (also in the bottom banner) ---
        if (d.hasUpdate)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: GestureDetector(
              onTap: () async { final uri = Uri.parse(d.updateUrl); if (await canLaunchUrl(uri)) await launchUrl(uri); },
              child: Container(width: double.infinity, padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFE50914), borderRadius: BorderRadius.circular(12)), child: Row(children: [const Icon(Icons.system_update, color: Colors.white), const SizedBox(width: 10), Expanded(child: Text('New update available — Hanimo ${d.latestVersionName} Tap to update', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))), const Icon(Icons.arrow_forward, color: Colors.white)])),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
          child: GestureDetector(onTap: () => widget.goTab(2), child: Container(padding: const EdgeInsets.all(14), decoration: glassDeco(radius: 12), child: Row(children: [Icon(Icons.search, color: Colors.white54), SizedBox(width: 8), Text(d.tr('searchTitles'), style: const TextStyle(color: Colors.white54))]))),
        ),
        // --- New-episode alerts ---
        if (d.newEpAlerts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFE50914).withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE50914))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [Icon(Icons.notifications_active, color: Color(0xFFE50914)), SizedBox(width: 8), Text('New episodes!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))]),
                ...d.newEpAlerts.map((a) {
                  final it = a['item'] as Item;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.play_circle, color: Color(0xFFE50914)),
                    title: Text('${it.title} — now ${a['newCount']} episodes'),
                    subtitle: Text('Was ${a['oldCount']} episodes'),
                    onTap: () { d.addRecent(it); Navigator.push(context, MaterialPageRoute(builder: (_) => ItemPage(data: d, item: it))); },
                  );
                }),
              ]),
            ),
          ),
        // --- Genre chips (Animefy-style) ---
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            itemCount: _genres.length,
            itemBuilder: (c, i) {
              final g = _genres[i];
              final sel = _genre == g;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(g),
                  selected: sel,
                  selectedColor: const Color(0xFFE50914),
                  backgroundColor: Colors.white.withOpacity(0.06),
                  labelStyle: TextStyle(color: sel ? Colors.white : Colors.white70, fontWeight: sel ? FontWeight.bold : FontWeight.normal),
                  side: BorderSide(color: Colors.white.withOpacity(0.08)),
                  onSelected: (_) => setState(() => _genre = g),
                ),
              );
            },
          ),
        ),
        if (_genre != 'All') ...[
          sectionHeader(_genre),
          Builder(builder: (c) {
            final list = d.items.where((e) => e.genres.contains(_genre)).toList();
            if (list.isEmpty) return const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 8), child: Text('No titles in this genre yet.', style: TextStyle(color: Colors.white54)));
            return SizedBox(height: 190, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: list.length, itemBuilder: (c, i) => _itemCard(context, d, list[i], width: 130)));
          }),
        ],
        // --- Latest Updates (Animefy-style, episode badges) ---
        Builder(builder: (c) {
          final updates = d.items.where((e) => e.malId > 0).toList()..sort((a, b) => b.score.compareTo(a.score));
          if (updates.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            sectionHeader(d.tr('latestUpdates'), onViewAll: () => widget.goTab(1)),
            SizedBox(height: 190, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: updates.take(10).length, itemBuilder: (c, i) => _itemCard(context, d, updates[i], width: 130))),
          ]);
        }),
        // --- Airing Today ---
        Builder(builder: (c) {
          final today = _weekdays[DateTime.now().weekday - 1];
          final airing = d.items.where((e) => e.score > 0).toList()..sort((a, b) => b.score.compareTo(a.score));
          if (airing.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            sectionHeader('${d.tr('airingToday')} ($today)', onViewAll: () => widget.goTab(1)),
            SizedBox(height: 190, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: airing.take(10).length, itemBuilder: (c, i) => _itemCard(context, d, airing[i], width: 130))),
          ]);
        }),
        // --- Fall 2026 season ---
        Builder(builder: (c) {
          final season = d.items.where((e) => e.year >= 2025).toList();
          if (season.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            sectionHeader(d.tr('fall2026'), onViewAll: () => widget.goTab(1)),
            SizedBox(height: 190, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: season.length, itemBuilder: (c, i) => _itemCard(context, d, season[i], width: 130))),
          ]);
        }),
        // --- Trending Now (Netflix Top 10 style) ---
        if (trending.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.fromLTRB(12, 18, 12, 8), child: Text(d.tr('trendingNow'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
          SizedBox(
            height: 190,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: trending.length,
              itemBuilder: (c, i) => Row(children: [
                Text('${i + 1}', style: TextStyle(fontSize: 110, fontWeight: FontWeight.w900, color: Colors.black, shadows: [const Shadow(blurRadius: 1, color: Colors.white54, offset: Offset(1, 1)), const Shadow(blurRadius: 1, color: Colors.white54, offset: Offset(-1, -1))])),
                _itemCard(context, d, trending[i], width: 130),
              ]),
            ),
          ),
        ],
        // --- Rows by category ---
        for (final cat in d.cats) ...[
          Padding(padding: const EdgeInsets.fromLTRB(12, 18, 12, 8), child: Text(cat.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
          Builder(builder: (c) {
            final list = d.items.where((e) => e.categoryId == cat.id).toList();
            return SizedBox(
              height: 190,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: list.length,
                itemBuilder: (c, i) => _itemCard(context, d, list[i], width: 130),
              ),
            );
          }),
        ],
        _AnimeNewsSection(data: d),
        if (d.recent.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.fromLTRB(12, 18, 12, 8), child: Text(d.tr('continueWatching'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
          SizedBox(height: 190, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: d.recent.length, itemBuilder: (c, i) => _itemCard(context, d, d.recent[i], width: 130))),
        ],
        if (d.imported.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.fromLTRB(12, 18, 12, 8), child: Text('Imported', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900))),
          SizedBox(height: 190, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: d.imported.length, itemBuilder: (c, i) => _itemCard(context, d, d.imported[i], width: 130))),
        ],
        const SizedBox(height: 24),
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
    child: Container(
      width: width,
      margin: const EdgeInsets.only(right: 10),
      decoration: glassDeco(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), child: posterWidget(it, height: 120)),
          if (it.episodeCount > 0)
            Positioned(left: 6, top: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(8)), child: Text('Ep ${it.episodeCount}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)))),
          if (it.score > 0)
            Positioned(right: 6, bottom: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(8)), child: Text('★ ${it.score.toStringAsFixed(1)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber)))),
        ]),
        Padding(padding: const EdgeInsets.all(8), child: Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
        if ((d.lastEpisode[it.id] ?? 0) > 0 && d.progressFraction(it.id, d.lastEpisode[it.id]!) > 0)
          Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: LinearProgressIndicator(value: d.progressFraction(it.id, d.lastEpisode[it.id]!), backgroundColor: Colors.white24, color: const Color(0xFFE50914))),
      ]),
    ),
  );
}

// ---------- Anime news (Jikan, no key) ----------
class _AnimeNewsSection extends StatefulWidget {
  final AppData data;
  const _AnimeNewsSection({required this.data});
  @override
  State<_AnimeNewsSection> createState() => _AnimeNewsSectionState();
}

class _AnimeNewsSectionState extends State<_AnimeNewsSection> {
  List<Map<String, String>> news = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = widget.data.items.where((e) => e.malId > 0).take(3).map((e) => e.malId).toList();
    final out = <Map<String, String>>[];
    for (final id in ids) {
      try {
        final res = await http.get(Uri.parse('https://api.jikan.moe/v4/anime/$id/news?limit=2'));
        if (res.statusCode != 200) continue;
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        for (final n in (body['data'] as List?) ?? []) {
          out.add({'title': (n['title'] ?? '') as String, 'date': ((n['date'] ?? '') as String).split('T').first, 'url': (n['forum_url'] ?? '') as String});
        }
        await Future.delayed(const Duration(milliseconds: 400));
      } catch (_) {}
    }
    if (mounted && out.isNotEmpty) setState(() => news = out.take(5).toList());
  }

  @override
  Widget build(BuildContext context) {
    if (news.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sectionHeader(widget.data.tr('latestNews')),
      ...news.map((n) => Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: GestureDetector(
              onTap: () async { final uri = Uri.tryParse(n['url'] ?? ''); if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); },
              child: Container(padding: const EdgeInsets.all(14), decoration: glassDeco(), child: Row(children: [const Icon(Icons.article, color: Color(0xFFE50914)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(n['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)), Text(n['date'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12))]))])),
            ),
          )),
    ]);
  }
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
          ? const Center(child: Text('No items in this category yet.'))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.75, crossAxisSpacing: 10, mainAxisSpacing: 10),
              itemCount: all.length,
              itemBuilder: (c, i) => _itemCard(context, data, all[i], width: double.infinity),
            ),
    );
  }
}

class ItemPage extends StatefulWidget {
  final AppData data;
  final Item item;
  const ItemPage({super.key, required this.data, required this.item});
  @override
  State<ItemPage> createState() => _ItemPageState();
}

class _ItemPageState extends State<ItemPage> {
  List<Map<String, dynamic>> jikanEpisodes = [];
  Map<int, Episode> customEpisodes = {};
  String epMsg = '';
  bool epLoading = false;
  String? trailerUrl;
  List<Map<String, dynamic>> jikanRecs = [];

  @override
  void initState() {
    super.initState();
    _loadEpisodes();
  }

  Future<void> _loadEpisodes() async {
    if (widget.item.type == 'movie') return;
    setState(() => epLoading = true);
    try {
      final custom = await FirebaseFirestore.instance.collection('items').doc(widget.item.id).collection('episodes').get();
      customEpisodes = {for (final d in custom.docs) int.tryParse(d.id) ?? 0: Episode.fromMap(int.tryParse(d.id) ?? 0, d.data())};
    } catch (_) {}
    if (widget.item.malId > 0) {
      try {
        jikanEpisodes = await fetchJikanEpisodes(widget.item.malId);
      } catch (e) {
        epMsg = 'Episode list could not be loaded: $e';
      }
      // Trailer + MyAnimeList recommendations.
      try {
        final res = await http.get(Uri.parse('https://api.jikan.moe/v4/anime/${widget.item.malId}'));
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          trailerUrl = ((body['data'] as Map<String, dynamic>?)?['trailer'] as Map<String, dynamic>?)?['url'] as String?;
        }
        await Future.delayed(const Duration(milliseconds: 400));
        final rec = await http.get(Uri.parse('https://api.jikan.moe/v4/anime/${widget.item.malId}/recommendations'));
        if (rec.statusCode == 200) {
          final body = jsonDecode(rec.body) as Map<String, dynamic>;
          jikanRecs = ((body['data'] as List?) ?? []).take(6).map((e) {
            final entry = (e as Map<String, dynamic>)['entry'] as Map<String, dynamic>;
            return {'malId': entry['mal_id'], 'title': entry['title'], 'image': ((entry['images'] as Map?)?['jpg'] as Map?)?['image_url'] ?? '', 'url': entry['url'] ?? ''};
          }).toList();
        }
      } catch (_) {}
    }
    if (mounted) setState(() => epLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final item = widget.item;
    final fav = data.favIds.contains(item.id);
    // Episode numbers: Jikan list first, then any custom-only episodes.
    final numbers = <int>{};
    for (final e in jikanEpisodes) { numbers.add((e['number'] as int?) ?? 0); }
    numbers.addAll(customEpisodes.keys);
    numbers.remove(0);
    final sorted = numbers.toList()..sort();
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
              Wrap(spacing: 8, children: [
                Chip(label: Text(item.type)),
                if (item.isLive) const Chip(label: Text('LIVE')),
                Chip(label: Text(data.catName(item.categoryId))),
                if (item.score > 0) Chip(label: Text('★ ${item.score.toStringAsFixed(1)}')),
                if (item.year > 0) Chip(label: Text('${item.year}')),
                ...item.genres.take(4).map((g) => Chip(label: Text(g))),
              ]),
              const SizedBox(height: 12),
              Text(item.description.isEmpty ? 'No description yet.' : item.description),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.play_arrow), label: Text(item.type == 'movie' ? 'Play' : 'Play Ep 1'), onPressed: () {
                  data.addRecent(item);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(item: item, data: data, episodeNumber: item.type == 'movie' ? 0 : 1)));
                })),
                const SizedBox(width: 10),
                IconButton(icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? Colors.pink : null), onPressed: () => data.toggleFav(item)),
                IconButton(icon: const Icon(Icons.share), onPressed: () async {
                  final text = item.url.isEmpty ? '${item.title} — Hanimo' : '${item.title}\n${item.url}';
                  await SharePlus.instance.share(ShareParams(text: text));
                }),
              ]),
              if (trailerUrl != null && trailerUrl!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: OutlinedButton.icon(icon: const Icon(Icons.movie), label: const Text('Watch trailer'), onPressed: () async { final uri = Uri.tryParse(trailerUrl!); if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }),
                ),
              if (item.url.isEmpty && item.type == 'movie') const Padding(padding: EdgeInsets.only(top: 12), child: Text('No link yet.', style: TextStyle(color: Colors.amber))),
              if (item.type != 'movie') ...[
                const SizedBox(height: 20),
                Text('Episodes ${sorted.isEmpty ? '' : '(${sorted.length})'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                if (epLoading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
                if (epMsg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(epMsg)),
                if (!epLoading && sorted.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('No episodes yet. Admin can add episode links, or set a MyAnimeList ID on the item to load its episode list.')),
                ...sorted.map((n) {
                  final j = jikanEpisodes.firstWhere((e) => e['number'] == n, orElse: () => {'number': n, 'title': '', 'aired': ''});
                  final custom = customEpisodes[n];
                  final hasLink = (custom?.url.isNotEmpty == true) || item.url.isNotEmpty;
                  final frac = data.progressFraction(item.id, n);
                  return ListTile(
                    leading: CircleAvatar(child: Text('$n')),
                    title: Text((j['title'] as String).isEmpty ? 'Episode $n' : (j['title'] as String)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if ((j['aired'] as String).isNotEmpty) Text((j['aired'] as String).split('T').first),
                      if (frac > 0) LinearProgressIndicator(value: frac, backgroundColor: Colors.white24, color: const Color(0xFFE50914)),
                      if (!hasLink) const Text('No link yet', style: TextStyle(color: Colors.amber)),
                    ]),
                    trailing: Icon(frac >= 0.95 ? Icons.check_circle : Icons.play_circle, color: frac >= 0.95 ? Colors.green : const Color(0xFFE50914)),
                    onTap: () {
                      data.addRecent(item);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(item: item, data: data, episodeNumber: n, episodeTitle: (j['title'] as String), overrideUrl: custom?.url, overrideSubtitleUrl: custom?.subtitleUrl)));
                    },
                  );
                }),
              ],
              // --- More like this (same genres, local) ---
              Builder(builder: (c) {
                final recs = data.items.where((e) => e.id != item.id && e.genres.any((g) => item.genres.contains(g))).toList()..sort((a, b) => b.score.compareTo(a.score));
                if (recs.isEmpty) return const SizedBox.shrink();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  sectionHeader('More like this'),
                  SizedBox(height: 190, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: recs.take(10).length, itemBuilder: (c, i) => _itemCard(context, data, recs[i], width: 130))),
                ]);
              }),
              // --- Recommended by MyAnimeList ---
              if (jikanRecs.isNotEmpty) ...[
                sectionHeader('Recommended by MyAnimeList'),
                SizedBox(
                  height: 190,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: jikanRecs.length,
                    itemBuilder: (c, i) {
                      final r = jikanRecs[i];
                      return GestureDetector(
                        onTap: () async { final uri = Uri.tryParse(r['url'] ?? ''); if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); },
                        child: Container(
                          width: 130,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: glassDeco(),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), child: SizedBox(height: 120, width: 130, child: (r['image'] as String).isEmpty ? const Icon(Icons.movie, size: 40) : CachedNetworkImage(imageUrl: r['image'], fit: BoxFit.cover, memCacheWidth: 260, memCacheHeight: 360, placeholder: (c, u) => const SizedBox(), errorWidget: (c, u, e) => const Icon(Icons.broken_image)))),
                            Padding(padding: const EdgeInsets.all(8), child: Text(r['title'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

class PlayerPage extends StatefulWidget {
  final Item item;
  final AppData? data;
  final int episodeNumber;
  final String episodeTitle;
  final String? overrideUrl;
  final String? overrideSubtitleUrl;
  final String? partyId; // guest joins an existing watch party with this code
  const PlayerPage({super.key, required this.item, this.data, this.episodeNumber = 0, this.episodeTitle = '', this.overrideUrl, this.overrideSubtitleUrl, this.partyId});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? ctrl;
  String? err;
  bool _showControls = true;
  bool _fullscreen = false;
  bool _captionsOn = true;
  double _speed = 1.0;
  double _volume = 1.0;
  bool _casting = false;
  Timer? _hideTimer;
  Duration _pos = Duration.zero;
  Duration _dur = Duration.zero;
  // Watch Together: host pushes position/playing every 5s; guests follow.
  String? _partyCode;
  bool _isHost = false;
  StreamSubscription<DocumentSnapshot>? _partySub;
  Timer? _syncTimer;

  Future<ClosedCaptionFile> _loadCaptions(String url) async {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return url.toLowerCase().endsWith('.vtt') ? WebVTTCaptionFile(res.body) : SubRipCaptionFile(res.body);
  }

  int _lastSavedSec = -1;
  @override
  void initState() {
    super.initState();
    if (widget.partyId != null) _joinParty(widget.partyId!);
    final url = widget.overrideUrl ?? widget.item.url;
    if (url.isEmpty || widget.item.isTorrent) return;
    final lower = url.toLowerCase();
    final isVideo = lower.endsWith('.mp4') || lower.contains('.m3u8') || lower.endsWith('.mov') || lower.endsWith('.webm') || lower.endsWith('.mkv');
    if (!isVideo) return;
    final subUrl = widget.overrideSubtitleUrl ?? widget.item.subtitleUrl;
    ctrl = subUrl.isNotEmpty
        ? VideoPlayerController.networkUrl(Uri.parse(url), closedCaptionFile: _loadCaptions(subUrl))
        : VideoPlayerController.networkUrl(Uri.parse(url));
    ctrl!.addListener(() {
      if (!mounted) return;
      final v = ctrl!.value;
      if (v.position.inSeconds != _pos.inSeconds || v.duration != _dur) setState(() { _pos = v.position; _dur = v.duration; });
      // Save resume position every 15s while playing (local only).
      if (widget.data != null && v.isPlaying && v.position.inSeconds - _lastSavedSec >= 15 && v.duration.inSeconds > 0) {
        _lastSavedSec = v.position.inSeconds;
        widget.data!.saveProgress(widget.item.id, widget.episodeNumber, v.position.inSeconds, v.duration.inSeconds);
      }
    });
    ctrl!.initialize().then((_) {
      if (mounted) setState(() {});
      ctrl?.setVolume(_volume);
      // Resume where the user stopped, unless almost finished.
      final saved = widget.data?.progress['${widget.item.id}:${widget.episodeNumber}'] ?? 0;
      final dur = ctrl!.value.duration.inSeconds;
      if (saved > 10 && dur > 0 && saved < dur - 10) ctrl!.seekTo(Duration(seconds: saved));
      ctrl?.play();
      _startHideTimer();
    }).catchError((e) {
      if (mounted) setState(() => err = 'Could not play this stream: $e');
    });
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () { if (mounted) setState(() => _showControls = false); });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _seek(Duration d) {
    if (ctrl == null) return;
    final target = ctrl!.value.position + d;
    ctrl!.seekTo(target < Duration.zero ? Duration.zero : target);
  }

  Future<void> _toggleFullscreen() async {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _castToTv() async {
    final url = widget.overrideUrl ?? widget.item.url;
    if (url.isEmpty || url.startsWith('magnet:')) return;
    try {
      await castPlugin.showCastDialog(); // native device picker
      final connected = await castPlugin.isConnected();
      if (!connected) return;
      await castPlugin.playMedia(url: url, title: widget.episodeNumber > 0 ? '${widget.item.title} — Ep ${widget.episodeNumber}' : widget.item.title);
      ctrl?.pause(); // local player hands over to the TV
      if (mounted) setState(() => _casting = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cast failed: $e')));
    }
  }

  Future<void> _stopCasting() async {
    try {
      await castPlugin.stopMedia();
    } catch (_) {}
    if (mounted) setState(() => _casting = false);
    ctrl?.play();
  }

  Future<void> _startParty() async {
    final d = widget.data;
    if (d == null || d.user == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sign in to start a watch party.')));
      return;
    }
    final code = ('${DateTime.now().millisecondsSinceEpoch}${d.user!.uid}').hashCode.abs().toRadixString(36).toUpperCase().padLeft(6, '0').substring(0, 6);
    try {
      await FirebaseFirestore.instance.collection('parties').doc(code).set({
        'hostUid': d.user!.uid,
        'hostName': d.user!.displayName ?? '',
        'itemId': widget.item.id,
        'title': widget.episodeNumber > 0 ? '${widget.item.title} — Ep ${widget.episodeNumber}' : widget.item.title,
        'episodeNumber': widget.episodeNumber,
        'url': widget.overrideUrl ?? widget.item.url,
        'position': ctrl?.value.position.inSeconds ?? 0,
        'playing': true,
        'participants': [d.user!.uid],
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() { _partyCode = code; _isHost = true; });
      _syncTimer?.cancel();
      _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pushPartyState());
      _showPartyDialog();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start party: $e')));
    }
  }

  Future<void> _pushPartyState() async {
    if (!_isHost || _partyCode == null || ctrl == null || !ctrl!.value.isInitialized) return;
    try {
      await FirebaseFirestore.instance.collection('parties').doc(_partyCode!).set({
        'position': ctrl!.value.position.inSeconds,
        'playing': ctrl!.value.isPlaying,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _joinParty(String code) {
    setState(() { _partyCode = code; _isHost = false; });
    _partySub?.cancel();
    _partySub = FirebaseFirestore.instance.collection('parties').doc(code).snapshots().listen((snap) {
      if (!mounted || ctrl == null || !ctrl!.value.isInitialized) return;
      if (!snap.exists) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Watch party ended.')));
        setState(() => _partyCode = null);
        return;
      }
      final data = snap.data() as Map<String, dynamic>;
      final pos = (data['position'] as num?)?.toInt() ?? 0;
      final playing = data['playing'] == true;
      if ((ctrl!.value.position.inSeconds - pos).abs() > 3) ctrl!.seekTo(Duration(seconds: pos));
      if (playing && !ctrl!.value.isPlaying) ctrl!.play();
      if (!playing && ctrl!.value.isPlaying) ctrl!.pause();
    });
  }

  Future<void> _inviteFriendToParty(Map<String, dynamic> f) async {
    final d = widget.data;
    if (d == null || d.user == null || _partyCode == null) return;
    try {
      await FirebaseFirestore.instance.collection('parties').doc(_partyCode!).set({
        'participants': FieldValue.arrayUnion([f['uid']]),
      }, SetOptions(merge: true));
      await FirebaseFirestore.instance.collection('messages').add({
        'fromUid': d.user!.uid,
        'fromName': d.user!.displayName ?? '',
        'fromHanimoId': d.hanimoId ?? '',
        'toUid': f['uid'],
        'toHanimoId': f['hanimoId'] ?? '',
        'text': '🎬 ${d.user!.displayName ?? 'A friend'} invited you to watch ${widget.item.title} together! Party code: $_partyCode — open Friends → Join a watch party and enter the code.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invited ${f['displayName'] ?? f['hanimoId']}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invite failed: $e')));
    }
  }

  Future<void> _endParty() async {
    _syncTimer?.cancel();
    _partySub?.cancel();
    if (_isHost && _partyCode != null) {
      try { await FirebaseFirestore.instance.collection('parties').doc(_partyCode!).delete(); } catch (_) {}
    }
    if (mounted) setState(() { _partyCode = null; _isHost = false; });
  }

  void _showPartyDialog() {
    final d = widget.data;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_isHost ? 'Watch Together — party $_partyCode' : 'Watch Together'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_isHost ? 'Share this code with a friend — they join from Friends → Join a watch party. Your playback stays in sync with theirs.' : 'You are watching in sync with the host.'),
            const SizedBox(height: 10),
            Row(children: [
              Chip(label: Text('Code: ${_partyCode ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.copy), onPressed: () async { if (_partyCode != null) await Clipboard.setData(ClipboardData(text: _partyCode!)); }),
            ]),
            if (_isHost && d != null && d.friends.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text('Invite a friend:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...d.friends.map((f) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person),
                    title: Text(f['displayName'] ?? f['hanimoId'] ?? ''),
                    trailing: TextButton(child: const Text('Invite'), onPressed: () => _inviteFriendToParty(f)),
                  )),
            ],
          ]),
        ),
        actions: [
          TextButton(child: const Text('Close'), onPressed: () => Navigator.pop(c)),
          TextButton(child: Text(_isHost ? 'End party' : 'Leave party'), onPressed: () async { Navigator.pop(c); await _endParty(); }),
        ],
      ),
    );
  }

  void _showCast() {
    final url = widget.overrideUrl ?? widget.item.url;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Watch on TV'),
        content: const Text('Pick your Chromecast / Google TV below. Your phone and TV must be on the same Wi-Fi. The TV loads the stream itself, so the link must be reachable from the TV.'),
        actions: [
          TextButton(child: const Text('Cast to Chromecast'), onPressed: () async { Navigator.pop(c); await _castToTv(); }),
          if (_casting) TextButton(child: const Text('Stop casting'), onPressed: () async { Navigator.pop(c); await _stopCasting(); }),
          TextButton(child: const Text('Share link to TV'), onPressed: () async { Navigator.pop(c); await SharePlus.instance.share(ShareParams(text: '${widget.item.title}\n$url')); }),
          TextButton(child: const Text('Open in external player'), onPressed: () async { Navigator.pop(c); final uri = Uri.tryParse(url); if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication); }),
          TextButton(child: const Text('Copy link'), onPressed: () async { await Clipboard.setData(ClipboardData(text: url)); if (mounted) Navigator.pop(c); }),
          TextButton(child: const Text('Close'), onPressed: () => Navigator.pop(c)),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _syncTimer?.cancel();
    _partySub?.cancel();
    if (_isHost && _partyCode != null) {
      FirebaseFirestore.instance.collection('parties').doc(_partyCode!).delete().catchError((_) {});
    }
    if (ctrl != null && ctrl!.value.isInitialized && widget.data != null) {
      final v = ctrl!.value;
      if (v.position.inSeconds > 10 && v.duration.inSeconds > 0 && v.position.inSeconds < v.duration.inSeconds - 10) {
        widget.data!.saveProgress(widget.item.id, widget.episodeNumber, v.position.inSeconds, v.duration.inSeconds);
      }
    }
    ctrl?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.overrideUrl ?? widget.item.url;
    // Torrent links: no in-app streaming — hand off to a torrent app.
    if (widget.item.isTorrent || url.toLowerCase().startsWith('magnet:') || url.toLowerCase().endsWith('.torrent')) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.item.title)),
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Torrent link', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Hanimo does not stream torrents inside the app. Open this link in your torrent app, or add it through an add-on that provides a direct HTTP stream for it.'),
            const SizedBox(height: 16),
            ElevatedButton.icon(icon: const Icon(Icons.download), label: const Text('Open in torrent app'), onPressed: () async { final uri = Uri.tryParse(url); if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication); }),
            const SizedBox(height: 8),
            OutlinedButton.icon(icon: const Icon(Icons.copy), label: const Text('Copy link'), onPressed: () async { await Clipboard.setData(ClipboardData(text: url)); }),
            const SizedBox(height: 12),
            SelectableText(url),
          ]),
        ),
      );
    }
    final title = widget.episodeNumber > 0 ? '${widget.item.title} — Ep ${widget.episodeNumber}' : widget.item.title;
    if (url.isEmpty) {
      return Scaffold(appBar: AppBar(title: Text(title)), body: const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No link yet for this episode. Admin can add a link for it.', textAlign: TextAlign.center))));
    }
    if (err != null) {
      return Scaffold(appBar: AppBar(title: Text(widget.item.title)), body: Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(err!, textAlign: TextAlign.center))));
    }
    if (ctrl == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.item.title)),
        body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('This looks like a web link, not a direct video file.'),
          const SizedBox(height: 12),
          ElevatedButton.icon(icon: const Icon(Icons.open_in_browser), label: const Text('Open in browser'), onPressed: () async { final uri = Uri.tryParse(url); if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication); }),
          const SizedBox(height: 8),
          OutlinedButton.icon(icon: const Icon(Icons.cast), label: const Text('Watch on TV'), onPressed: _showCast),
          const SizedBox(height: 8),
          SelectableText(url),
        ])),
      );
    }
    if (!ctrl!.value.isInitialized) {
      return Scaffold(appBar: AppBar(title: Text(widget.item.title)), body: const Center(child: CircularProgressIndicator()));
    }
    final v = ctrl!.value;
    final caption = _captionsOn ? v.caption.text : '';
    final video = AspectRatio(aspectRatio: v.aspectRatio, child: VideoPlayer(ctrl!));
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _fullscreen ? null : AppBar(title: Text(title), backgroundColor: Colors.black, actions: [
            IconButton(icon: Icon(Icons.group_add, color: _partyCode != null ? const Color(0xFFE50914) : Colors.white), tooltip: 'Watch together', onPressed: () { if (_partyCode != null) { _showPartyDialog(); } else { _startParty(); } }),
            IconButton(icon: Icon(_casting ? Icons.cast_connected : Icons.cast, color: _casting ? const Color(0xFFE50914) : Colors.white), tooltip: 'Watch on TV', onPressed: _showCast),
          ]),
      body: Center(
        child: GestureDetector(
          onTap: _toggleControls,
          onDoubleTapDown: (d) {
            final w = MediaQuery.of(context).size.width;
            _seek(d.globalPosition.dx < w / 2 ? const Duration(seconds: -10) : const Duration(seconds: 10));
          },
          child: Stack(alignment: Alignment.center, children: [
            _fullscreen ? SizedBox.expand(child: FittedBox(fit: BoxFit.contain, child: SizedBox(width: v.size.width, height: v.size.height, child: VideoPlayer(ctrl!)))) : video,
            if (caption.isNotEmpty)
              Positioned(bottom: _showControls ? 110 : 20, left: 16, right: 16, child: Text(caption, textAlign: TextAlign.center, style: const TextStyle(backgroundColor: Colors.black54, fontSize: 16))),
            if (_showControls)
              Container(
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black87])),
                child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Row(children: [
                    IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () async { if (_fullscreen) await _toggleFullscreen(); if (mounted) Navigator.pop(context); }),
                    Expanded(child: Text(widget.item.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                    IconButton(icon: const Icon(Icons.cast, color: Colors.white), tooltip: 'Watch on TV', onPressed: _showCast),
                  ]),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(icon: const Icon(Icons.replay_10, color: Colors.white), iconSize: 44, onPressed: () => _seek(const Duration(seconds: -10))),
                    IconButton(icon: Icon(v.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled, color: Colors.white), iconSize: 64, onPressed: () => setState(() => v.isPlaying ? ctrl!.pause() : ctrl!.play())),
                    IconButton(icon: const Icon(Icons.forward_10, color: Colors.white), iconSize: 44, onPressed: () => _seek(const Duration(seconds: 10))),
                  ]),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Column(children: [
                      Row(children: [
                        Text(_fmt(_pos), style: const TextStyle(color: Colors.white)),
                        Expanded(child: Slider(value: _pos.inMilliseconds.toDouble().clamp(0, _dur.inMilliseconds.toDouble()), max: _dur.inMilliseconds.toDouble() > 0 ? _dur.inMilliseconds.toDouble() : 1, activeColor: const Color(0xFFE50914), onChanged: (nv) => ctrl!.seekTo(Duration(milliseconds: nv.toInt())))),
                        Text(_fmt(_dur), style: const TextStyle(color: Colors.white)),
                      ]),
                      Row(children: [
                        PopupMenuButton<double>(
                          icon: Text('${_speed}x', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          onSelected: (nv) => setState(() { _speed = nv; ctrl!.setPlaybackSpeed(nv); }),
                          itemBuilder: (c) => [0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((s) => PopupMenuItem(value: s, child: Text('${s}x'))).toList(),
                        ),
                        IconButton(icon: const Icon(Icons.volume_up, color: Colors.white), onPressed: () => setState(() { _volume = _volume > 0 ? 0 : 1; ctrl!.setVolume(_volume); })),
                        SizedBox(width: 90, child: Slider(value: _volume, activeColor: Colors.white, onChanged: (nv) => setState(() { _volume = nv; ctrl!.setVolume(nv); }))),
                        if (widget.item.subtitleUrl.isNotEmpty)
                          IconButton(icon: Icon(Icons.closed_caption, color: _captionsOn ? const Color(0xFFE50914) : Colors.white), tooltip: 'Subtitles', onPressed: () => setState(() => _captionsOn = !_captionsOn)),
                        const Spacer(),
                        IconButton(icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white), tooltip: 'Fullscreen', onPressed: _toggleFullscreen),
                      ]),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
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

  Item? _find(AppData d, String id) {
    for (final it in [...d.items, ...d.imported, ...d.favItems.values]) {
      if (it.id == id) return it;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final u = d.user;
    final favs = d.favItems.values.toList();
    // Dashboard stats, computed live from local data (private to this device).
    final watchingKeys = d.progress.keys.where((k) {
      final parts = k.split(':');
      return (d.progressDuration[k] ?? 0) > 0 && d.progressFraction(parts.first, int.tryParse(parts.last) ?? 0) < 0.95;
    }).toList();
    final completedKeys = d.progress.keys.where((k) {
      final parts = k.split(':');
      return d.progressFraction(parts.first, int.tryParse(parts.last) ?? 0) >= 0.95;
    }).toList();
    final totalSeconds = d.progress.values.fold<int>(0, (a, b) => a + b);
    final hours = (totalSeconds / 3600).toStringAsFixed(1);
    final watchLater = favs.where((it) => (d.lastEpisode[it.id] ?? 0) == 0).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // --- Dashboard header (glass, Animefy-style) ---
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFE50914), Color(0xFF7A0A12)]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 32,
              backgroundImage: (u?.photoURL != null && u!.photoURL!.isNotEmpty) ? NetworkImage(u.photoURL!) : null,
              backgroundColor: Colors.white24,
              child: (u?.photoURL == null || u!.photoURL!.isEmpty) ? Text((u?.displayName ?? u?.email ?? 'H').substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)) : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u?.displayName?.isNotEmpty == true ? u!.displayName! : (u?.email ?? 'Guest'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                if (u?.email != null) Text(u!.email!, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                Row(children: [
                  if (d.isAdmin) const Chip(label: Text('Admin'), backgroundColor: Colors.white24),
                  if (d.isAdmin) const SizedBox(width: 6),
                  Chip(label: Text(d.unreadUpdates > 0 ? '${d.unreadUpdates} update(s)' : 'Up to date'), backgroundColor: Colors.white24),
                ]),
                if (d.hanimoId != null) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: d.hanimoId!));
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied your Hanimo ID: ${d.hanimoId}')));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [Text('My Hanimo ID: ${d.hanimoId}', style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(width: 6), const Icon(Icons.copy, size: 14)]),
                    ),
                  ),
                ],
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // --- Stats grid ---
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.25,
          children: [
            _dashStat(Icons.favorite, '${favs.length}', d.tr('favourites')),
            _dashStat(Icons.bolt, '${watchingKeys.length}', d.tr('watching')),
            _dashStat(Icons.check_circle, '${completedKeys.length}', d.tr('completed')),
            _dashStat(Icons.history, '${d.recent.length}', d.tr('history')),
            _dashStat(Icons.people, '${d.friends.length}', 'Friends'),
            _dashStat(Icons.play_circle, '${d.progress.length}', d.tr('episodes')),
            _dashStat(Icons.timer, '${hours}h', d.tr('watched')),
          ],
        ),
        const SizedBox(height: 12),
        // --- Quick actions ---
        Wrap(spacing: 10, runSpacing: 10, children: [
          if (u == null)
            ElevatedButton.icon(icon: const Icon(Icons.login), label: const Text('Sign in with Google'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)), onPressed: () async { try { await d.signInGoogle(); } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-in failed: $e'))); } })
          else ...[
            ElevatedButton.icon(icon: const Icon(Icons.message), label: const Text('Messages'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MessagesPage(data: d)))),
            ElevatedButton.icon(icon: const Icon(Icons.people), label: const Text('Friends'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FriendsPage(data: d)))),
            ElevatedButton.icon(icon: const Icon(Icons.notifications), label: const Text('Updates'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UpdatesPage(data: d)))),
            TextButton.icon(icon: const Icon(Icons.logout), label: const Text('Sign out'), onPressed: () => d.signOut()),
          ],
        ]),
        if (u == null) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Your profile is created automatically when you sign in — the same Google account works on any device. Without signing in, your favourites and watch progress stay on this phone only.', style: TextStyle(color: Colors.white54))),
        // --- Continue Watching ---
        if (watchingKeys.isNotEmpty) ...[
          sectionHeader(d.tr('continueWatching')),
          ...watchingKeys.map((k) {
            final parts = k.split(':');
            final it = _find(d, parts.first);
            final ep = int.tryParse(parts.last) ?? 0;
            if (it == null) return const SizedBox.shrink();
            final frac = d.progressFraction(it.id, ep);
            return ListTile(
              leading: const Icon(Icons.play_circle, color: Color(0xFFE50914)),
              title: Text('${it.title} — Ep $ep'),
              subtitle: LinearProgressIndicator(value: frac, backgroundColor: Colors.white24, color: const Color(0xFFE50914)),
              trailing: Text('${(frac * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(item: it, data: d, episodeNumber: ep))),
            );
          }),
        ],
        // --- Watch Later ---
        if (watchLater.isNotEmpty) ...[
          sectionHeader(d.tr('watchLater')),
          SizedBox(height: 190, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: watchLater.length, itemBuilder: (c, i) => _itemCard(context, d, watchLater[i], width: 130))),
        ],
        // --- My Favourites ---
        sectionHeader('${d.tr('myFavourites')} (${favs.length})'),
        if (favs.isEmpty) const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 8), child: Text('No favourites yet. Tap the heart on any item.', style: TextStyle(color: Colors.white54))),
        ...favs.map((it) => ListTile(leading: const Icon(Icons.favorite, color: Colors.pink), title: Text(it.title), subtitle: Text(d.catName(it.categoryId)), trailing: IconButton(icon: const Icon(Icons.delete), onPressed: () => d.toggleFav(it)), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemPage(data: d, item: it))))),
        // --- Watch History ---
        if (d.recent.isNotEmpty) ...[
          sectionHeader('${d.tr('watchHistory')} (${d.recent.length})'),
          ...d.recent.map((it) => ListTile(leading: const Icon(Icons.history), title: Text(it.title), subtitle: Text(d.catName(it.categoryId)), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemPage(data: d, item: it))))),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _dashStat(IconData icon, String value, String label) => Container(
        padding: const EdgeInsets.all(12),
        decoration: glassDeco(),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: const Color(0xFFE50914)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ]),
      );
}

// ---------- Friends (by Hanimo ID, with online / last-seen) ----------
class FriendsPage extends StatefulWidget {
  final AppData data;
  const FriendsPage({super.key, required this.data});
  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final idCtrl = TextEditingController();
  final _partyCtrl = TextEditingController();
  String status = '';
  @override
  void dispose() {
    idCtrl.dispose();
    _partyCtrl.dispose();
    super.dispose();
  }

  String _lastSeenText(dynamic ts) {
    if (ts == null) return 'Last seen unknown';
    DateTime dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else {
      return 'Last seen unknown';
    }
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (day == today) return 'Last seen today $hh:$mm';
    if (day == today.subtract(const Duration(days: 1))) return 'Last seen yesterday $hh:$mm';
    return 'Last seen ${dt.day}/${dt.month}/${dt.year} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Row(children: [
          Expanded(child: TextField(controller: idCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Add friend by Hanimo ID (HNM-XXXXXX)', border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () async {
              final r = await d.addFriendById(idCtrl.text);
              if (mounted) setState(() { status = r; if (r.startsWith('Added')) idCtrl.clear(); });
            },
            child: const Text('Add'),
          ),
        ]),
        if (status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(status)),
        const SizedBox(height: 16),
        const Text('Join a watch party', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: _partyCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Party code (6 letters)', border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () async {
              final code = _partyCtrl.text.trim().toUpperCase();
              if (code.isEmpty) return;
              try {
                final doc = await FirebaseFirestore.instance.collection('parties').doc(code).get();
                if (!doc.exists) { if (mounted) setState(() => status = 'No party with code $code.'); return; }
                final pd = doc.data() ?? {};
                final itemId = pd['itemId'] as String?;
                Item? it;
                for (final e in [...d.items, ...d.imported]) { if (e.id == itemId) it = e; }
                if (it == null) { if (mounted) setState(() => status = 'Party found, but that title is not in your catalog.'); return; }
                if (mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(item: it!, data: d, episodeNumber: (pd['episodeNumber'] as num?)?.toInt() ?? 0, partyId: code)));
              } catch (e) {
                if (mounted) setState(() => status = 'Could not join party: $e');
              }
            },
            child: const Text('Join'),
          ),
        ]),
        const SizedBox(height: 16),
        Text('Your friends (${d.friends.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (d.friends.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('No friends yet. Ask a friend for their Hanimo ID — it is on their dashboard — and add them here.', style: TextStyle(color: Colors.white54))),
        ...d.friends.map((f) {
          final fUid = f['uid'] as String;
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('presence').doc(fUid).snapshots(),
            builder: (c, snap) {
              final pres = snap.data?.data() as Map<String, dynamic>?;
              final online = pres?['online'] == true;
              return ListTile(
                leading: Stack(children: [
                  CircleAvatar(backgroundImage: (f['photoURL'] as String?)?.isNotEmpty == true ? NetworkImage(f['photoURL']) : null, child: (f['photoURL'] as String?)?.isNotEmpty == true ? null : Text(((f['displayName'] as String?) ?? 'H').substring(0, 1).toUpperCase())),
                  Positioned(right: 0, bottom: 0, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: online ? Colors.green : Colors.grey, shape: BoxShape.circle, border: Border.all(color: Colors.black, width: 2)))),
                ]),
                title: Text(f['displayName'] ?? f['hanimoId'] ?? ''),
                subtitle: Text(online ? 'Online now' : _lastSeenText(pres?['lastSeen'])),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.chat), tooltip: 'Chat', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MessagesPage(data: d, initialFriend: f)))),
                  IconButton(icon: const Icon(Icons.person_remove), tooltip: 'Remove', onPressed: () => d.removeFriend(fUid)),
                ]),
              );
            },
          );
        }),
      ]),
    );
  }
}

class MessagesPage extends StatefulWidget {
  final AppData data;
  final Map<String, dynamic>? initialFriend;
  const MessagesPage({super.key, required this.data, this.initialFriend});
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

  Map<String, dynamic>? _toFriend; // resolved recipient {uid, hanimoId, displayName}
  String _resolveStatus = '';

  @override
  void initState() {
    super.initState();
    _toFriend = widget.initialFriend;
  }

  Future<void> _resolveId() async {
    final id = toCtrl.text.trim().toUpperCase();
    if (id.isEmpty) return;
    try {
      final q = await FirebaseFirestore.instance.collection('presence').where('hanimoId', isEqualTo: id).limit(1).get();
      if (q.docs.isEmpty) {
        setState(() => _resolveStatus = 'No user with ID $id.');
        return;
      }
      final doc = q.docs.first;
      setState(() {
        _toFriend = {'uid': doc.id, 'hanimoId': id, 'displayName': doc.data()['displayName'] ?? ''};
        _resolveStatus = 'Chatting with ${_toFriend!['displayName']} ($id).';
      });
    } catch (e) {
      setState(() => _resolveStatus = 'Lookup failed: $e');
    }
  }

  Future<void> _send({Map<String, dynamic>? toFriend, String? text}) async {
    final d = widget.data;
    final u = d.user;
    if (u == null) return;
    final to = toFriend ?? _toFriend;
    final body = (text ?? msgCtrl.text.trim());
    if (to == null) { setState(() => status = 'Enter a friend\'s Hanimo ID and tap Find first.'); return; }
    if (body.isEmpty) { setState(() => status = 'Write a message first.'); return; }
    try {
      await FirebaseFirestore.instance.collection('messages').add({
        'fromUid': u.uid,
        'fromName': u.displayName ?? '',
        'fromHanimoId': d.hanimoId ?? '',
        'toUid': to['uid'],
        'toHanimoId': to['hanimoId'] ?? '',
        'text': body,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      setState(() { status = 'Message sent to ${to['displayName'] ?? to['hanimoId']}.'; if (toFriend == null) msgCtrl.clear(); });
    } catch (e) {
      setState(() => status = 'Send failed: $e');
    }
  }

  Future<void> _reply(Map<String, dynamic> m) async {
    final replyCtrl = TextEditingController(text: '');
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Reply to ${m['fromName'] ?? m['fromHanimoId'] ?? ''}'), content: TextField(controller: replyCtrl, maxLines: 4, decoration: const InputDecoration(labelText: 'Your reply', border: OutlineInputBorder())), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send'))]));
    if (ok == true && replyCtrl.text.trim().isNotEmpty) {
      await _send(toFriend: {'uid': m['fromUid'], 'hanimoId': m['fromHanimoId'], 'displayName': m['fromName']}, text: replyCtrl.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final u = d.user;
    if (u == null) {
      return Scaffold(appBar: AppBar(title: const Text('Messages')), body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Sign in to see your messages.'), const SizedBox(height: 12), ElevatedButton.icon(icon: const Icon(Icons.login), label: const Text('Sign in with Google'), onPressed: () async { try { await d.signInGoogle(); setState(() {}); } catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign-in failed: $e'))); } })])));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Send a message', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: toCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Friend\'s Hanimo ID (HNM-XXXXXX)', border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            ElevatedButton(onPressed: _resolveId, child: const Text('Find')),
          ]),
          if (_resolveStatus.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_resolveStatus)),
          if (_toFriend != null) Padding(padding: const EdgeInsets.only(top: 8), child: Chip(label: Text('To: ${_toFriend!['displayName']} (${_toFriend!['hanimoId']})'))),
          const SizedBox(height: 8),
          TextField(controller: msgCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Message', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          ElevatedButton.icon(icon: const Icon(Icons.send), label: const Text('Send'), onPressed: () => _send()),
          if (status.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(status)),
          const SizedBox(height: 20),
          const Text('Inbox — messages sent to you', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('messages').where('toUid', isEqualTo: u.uid).orderBy('createdAt', descending: true).snapshots(),
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
                  title: Text('${m['fromName'] ?? ''} (${m['fromHanimoId'] ?? ''})'),
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
                return ListTile(leading: const Icon(Icons.send), title: Text('To: ${m['toHanimoId'] ?? ''}'), subtitle: Text(m['text']?.toString() ?? ''));
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
  // IPTV bulk delete: keys are 'fs:<docId>' for Firestore live items
  // and 'local:<id>' for channels imported on this device only.
  final Set<String> _selectedIptv = {};
  Widget _stat(String label, String value) => Container(width: 100, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF1F1F1F), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFFE50914))), Text(label, style: const TextStyle(color: Colors.white54))]));
  Future<void> _editBanner(BuildContext context, BannerSlide? existing) async {
    final img = TextEditingController(text: existing?.imageUrl ?? '');
    final title = TextEditingController(text: existing?.title ?? '');
    final sub = TextEditingController(text: existing?.subtitle ?? '');
    final cat = TextEditingController(text: existing?.targetCategoryId ?? '');
    final order = TextEditingController(text: '${existing?.order ?? 0}');
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(existing == null ? 'Add banner' : 'Edit banner'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: img, decoration: const InputDecoration(labelText: 'Image URL, or asset:hero.webp')), TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')), TextField(controller: sub, decoration: const InputDecoration(labelText: 'Subtitle')), TextField(controller: cat, decoration: const InputDecoration(labelText: 'Opens category ID (optional)')), TextField(controller: order, decoration: const InputDecoration(labelText: 'Order'), keyboardType: TextInputType.number)])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))]));
    if (ok != true) return;
    try {
      final data = {'imageUrl': img.text.trim(), 'title': title.text.trim(), 'subtitle': sub.text.trim(), 'targetCategoryId': cat.text.trim(), 'order': int.tryParse(order.text) ?? 0};
      if (existing == null) { await FirebaseFirestore.instance.collection('banners').add(data); } else { await FirebaseFirestore.instance.collection('banners').doc(existing.id).set(data, SetOptions(merge: true)); }
      await widget.data.refreshFromFirestore();
      setState(() => msg = 'Banner saved. Home now shows it.');
    } catch (e) { setState(() => msg = 'Save failed: $e'); }
  }

  Future<void> _editAddon(BuildContext context, Addon? existing) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final url = TextEditingController(text: existing?.manifestUrl ?? '');
    final desc = TextEditingController(text: existing?.description ?? '');
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(existing == null ? 'Add add-on' : 'Edit add-on'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')), TextField(controller: url, decoration: const InputDecoration(labelText: 'Manifest URL (…/manifest.json)')), TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description (optional)'))])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))]));
    if (ok != true) return;
    try {
      final data = {'name': name.text.trim(), 'manifestUrl': url.text.trim(), 'description': desc.text.trim(), 'enabled': true};
      if (existing == null) { await FirebaseFirestore.instance.collection('addons').add(data); } else { await FirebaseFirestore.instance.collection('addons').doc(existing.id).set(data, SetOptions(merge: true)); }
      await widget.data.refreshFromFirestore();
      setState(() => msg = 'Add-on saved.');
    } catch (e) { setState(() => msg = 'Save failed: $e'); }
  }

  Future<void> _testAddon(Addon a) async {
    setState(() => msg = 'Testing ${a.name}…');
    try {
      final res = await http.get(Uri.parse(a.manifestUrl));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      final cats = (m['catalogs'] as List?) ?? [];
      setState(() => msg = '${m['name'] ?? a.name} v${m['version'] ?? '?'} — ${cats.length} catalog(s): ${cats.map((c) => c['name']).join(', ')}');
    } catch (e) { setState(() => msg = 'Add-on test failed: $e'); }
  }

  // Import real catalog content from Jikan (MyAnimeList, public, no key):
  // top series + top movies with real posters, synopsis, score and year.
  // No stream links are bundled — Admin adds links per item/episode.
  Future<void> _importJikan() async {
    setState(() => msg = 'Importing top anime from Jikan…');
    try {
      var added = 0;
      for (final spec in [
        ('https://api.jikan.moe/v4/top/anime?limit=20&filter=bypopularity', 'anime-series', 'series'),
        ('https://api.jikan.moe/v4/top/anime?limit=10&type=movie&filter=bypopularity', 'anime-movies', 'movie'),
      ]) {
        final res = await http.get(Uri.parse(spec.$1));
        if (res.statusCode != 200) throw Exception('Jikan HTTP ${res.statusCode}');
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        for (final a in (body['data'] as List?) ?? []) {
          final malId = (a['mal_id'] as num?)?.toInt() ?? 0;
          final images = a['images'] as Map<String, dynamic>?;
          final jpg = images?['jpg'] as Map<String, dynamic>?;
          final genres = ((a['genres'] as List?) ?? []).map((g) => (g['name'] ?? '') as String).where((g) => g.isNotEmpty).toList();
          await FirebaseFirestore.instance.collection('items').doc('mal-$malId').set({
            'categoryId': spec.$2,
            'title': (a['title'] ?? '') as String,
            'description': (a['synopsis'] ?? '') as String,
            'imageUrl': (jpg?['large_image_url'] ?? jpg?['image_url'] ?? '') as String,
            'url': '',
            'type': spec.$3,
            'malId': malId,
            'score': (a['score'] as num?)?.toDouble() ?? 0,
            'year': (a['year'] as num?)?.toInt() ?? 0,
            'genres': genres,
            'episodeCount': (a['episodes'] as num?)?.toInt() ?? 0,
            'isVisible': true,
            'isLive': false,
            'order': added,
          }, SetOptions(merge: true));
          added++;
        }
        await Future.delayed(const Duration(milliseconds: 400));
      }
      await widget.data.refreshFromFirestore();
      setState(() => msg = 'Imported $added titles from Jikan. Add links per item or episode in Admin.');
    } catch (e) {
      setState(() => msg = 'Import failed: $e');
    }
  }

  Future<void> _editEpisode(BuildContext context, Item item) async {
    final num = TextEditingController(text: '1');
    final title = TextEditingController();
    final url = TextEditingController();
    final sub = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Add episode link — ${item.title}'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: num, decoration: const InputDecoration(labelText: 'Episode number'), keyboardType: TextInputType.number), TextField(controller: title, decoration: const InputDecoration(labelText: 'Episode title (optional)')), TextField(controller: url, decoration: const InputDecoration(labelText: 'Episode link / stream URL')), TextField(controller: sub, decoration: const InputDecoration(labelText: 'Subtitle URL (.vtt / .srt, optional)'))])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))]));
    if (ok != true) return;
    try {
      final n = int.tryParse(num.text.trim()) ?? 0;
      if (n <= 0) throw Exception('Episode number must be 1 or higher');
      await FirebaseFirestore.instance.collection('items').doc(item.id).collection('episodes').doc('$n').set({'title': title.text.trim(), 'url': url.text.trim(), 'subtitleUrl': sub.text.trim()}, SetOptions(merge: true));
      setState(() => msg = 'Episode $n link saved for ${item.title}.');
    } catch (e) {
      setState(() => msg = 'Save failed: $e');
    }
  }

  List<String> _iptvKeys(AppData d) {
    final keys = <String>[];
    for (final it in d.items.where((e) => e.isLive || e.type == 'live')) { keys.add('fs:${it.id}'); }
    for (final it in d.imported) { keys.add('local:${it.id}'); }
    return keys;
  }

  Future<void> _deleteIptv(AppData d, List<String> keys, String what) async {
    if (keys.isEmpty) return;
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text('Delete $what?'), content: Text('This deletes ${keys.length} IPTV channel(s) permanently. This cannot be undone.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)), onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))]));
    if (ok != true) return;
    try {
      var n = 0;
      for (final key in keys) {
        if (key.startsWith('fs:')) {
          await FirebaseFirestore.instance.collection('items').doc(key.substring(3)).delete();
        } else {
          d.imported.removeWhere((e) => 'local:${e.id}' == key);
        }
        n++;
      }
      await d._saveLocal();
      await d.refreshFromFirestore();
      setState(() { _selectedIptv.removeAll(keys); msg = 'Deleted $n IPTV channel(s).'; });
    } catch (e) {
      setState(() => msg = 'Delete failed: $e');
    }
  }

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
    final sub = TextEditingController(text: existing?.subtitleUrl ?? '');
    final type = TextEditingController(text: existing?.type ?? 'series');
    final mal = TextEditingController(text: existing != null && existing.malId > 0 ? '${existing.malId}' : '');
    final score = TextEditingController(text: existing != null && existing.score > 0 ? '${existing.score}' : '');
    final year = TextEditingController(text: existing != null && existing.year > 0 ? '${existing.year}' : '');
    final genres = TextEditingController(text: existing?.genres.join(', ') ?? '');
    final cat = TextEditingController(text: existing?.categoryId ?? (widget.data.cats.isNotEmpty ? widget.data.cats.first.id : ''));
    final order = TextEditingController(text: '${existing?.order ?? 0}');
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: Text(existing == null ? 'Add item' : 'Edit item'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')), TextField(controller: cat, decoration: const InputDecoration(labelText: 'Category ID (e.g. anime-series)')), TextField(controller: img, decoration: const InputDecoration(labelText: 'Poster image URL (optional)')), TextField(controller: desc, decoration: const InputDecoration(labelText: 'Description')), TextField(controller: url, decoration: const InputDecoration(labelText: 'Link / stream URL — or a magnet: / .torrent link')), TextField(controller: sub, decoration: const InputDecoration(labelText: 'Subtitle URL (.vtt / .srt, optional)')), TextField(controller: type, decoration: const InputDecoration(labelText: 'Type: series / movie / live')), TextField(controller: mal, decoration: const InputDecoration(labelText: 'MyAnimeList ID (loads episodes, optional)')), TextField(controller: score, decoration: const InputDecoration(labelText: 'Score (e.g. 8.7)')), TextField(controller: year, decoration: const InputDecoration(labelText: 'Year')), TextField(controller: genres, decoration: const InputDecoration(labelText: 'Genres, comma separated')), TextField(controller: order, decoration: const InputDecoration(labelText: 'Order'), keyboardType: TextInputType.number)])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save'))]));
    if (ok != true) return;
    try {
      final data = {'categoryId': cat.text.trim(), 'title': title.text.trim(), 'imageUrl': img.text.trim(), 'description': desc.text.trim(), 'url': url.text.trim(), 'subtitleUrl': sub.text.trim(), 'type': type.text.trim(), 'order': int.tryParse(order.text) ?? 0, 'isVisible': true, 'isLive': type.text.trim() == 'live', 'malId': int.tryParse(mal.text.trim()) ?? 0, 'score': double.tryParse(score.text.trim()) ?? 0, 'year': int.tryParse(year.text.trim()) ?? 0, 'genres': genres.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()};
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
        const SizedBox(height: 16),
        if (d.isAdmin) ...[
          Wrap(spacing: 10, runSpacing: 10, children: [ElevatedButton.icon(icon: const Icon(Icons.add), label: const Text('Add category'), onPressed: () => _editCat(context, null)), ElevatedButton.icon(icon: const Icon(Icons.add), label: const Text('Add item'), onPressed: () => _editItem(context, null)), ElevatedButton.icon(icon: const Icon(Icons.download), label: const Text('Import top anime (Jikan)'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)), onPressed: _importJikan)]),
          const SizedBox(height: 12),
          const Text('Categories', style: TextStyle(fontWeight: FontWeight.bold)),
          ...d.cats.map((c) => ListTile(title: Text(c.name), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.edit), onPressed: () => _editCat(context, c)), IconButton(icon: const Icon(Icons.delete), onPressed: () async { await FirebaseFirestore.instance.collection('categories').doc(c.id).delete(); await d.refreshFromFirestore(); })]))),
          const Text('Items', style: TextStyle(fontWeight: FontWeight.bold)),
          ...d.items.map((it) => ListTile(title: Text(it.title), subtitle: Text(it.categoryId), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.playlist_play), tooltip: 'Add episode link', onPressed: () => _editEpisode(context, it)), IconButton(icon: const Icon(Icons.edit), onPressed: () => _editItem(context, it)), IconButton(icon: const Icon(Icons.delete), onPressed: () async { await FirebaseFirestore.instance.collection('items').doc(it.id).delete(); await d.refreshFromFirestore(); })]))),
          const SizedBox(height: 16),
          const Text('Dashboard', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _stat('Categories', '${d.cats.length}'),
            _stat('Items', '${d.items.length}'),
            _stat('Banners', '${d.banners.length}'),
            _stat('Add-ons', '${d.addons.length}'),
            _stat('Latest build', d.latestBuild > 0 ? '${d.latestBuild}' : '—'),
          ]),
          const SizedBox(height: 16),
          const Text('Carousel — Home banners', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('This is what the Home carousel shows. Add, edit, delete or change the order number — it updates for everyone with no new APK. Image can be a web URL, or asset:hero.webp, asset:series.webp, asset:movie.webp, asset:cyberpunk.webp or asset:fantasy.webp for the built-in banners. If you delete all banners, Home falls back to the built-in ones.', style: TextStyle(color: Colors.white54)),
          Row(children: [ElevatedButton.icon(icon: const Icon(Icons.add), label: const Text('Add banner'), onPressed: () => _editBanner(context, null))]),
          ...d.banners.map((b) => ListTile(leading: const Icon(Icons.image), title: Text(b.title.isEmpty ? b.imageUrl : b.title), subtitle: Text('Order ${b.order}'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.edit), onPressed: () => _editBanner(context, b)), IconButton(icon: const Icon(Icons.delete), onPressed: () async { await FirebaseFirestore.instance.collection('banners').doc(b.id).delete(); await d.refreshFromFirestore(); })]))),
          const SizedBox(height: 16),
          const Text('Add-ons (Stremio-style)', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('Add a manifest URL (…/manifest.json). Its catalogs become browseable lists, and its streams can be played — torrent streams open in a torrent app. Only add-ons you trust.', style: TextStyle(color: Colors.white54)),
          Row(children: [ElevatedButton.icon(icon: const Icon(Icons.add), label: const Text('Add add-on'), onPressed: () => _editAddon(context, null)), const SizedBox(width: 10), ElevatedButton.icon(icon: const Icon(Icons.explore), label: const Text('Browse add-ons'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddonsPage(data: d))))]),
          ...d.addons.map((a) => ListTile(leading: const Icon(Icons.extension), title: Text(a.name), subtitle: Text(a.manifestUrl), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(icon: const Icon(Icons.check_circle), tooltip: 'Test', onPressed: () => _testAddon(a)), Switch(value: a.enabled, onChanged: (v) async { await FirebaseFirestore.instance.collection('addons').doc(a.id).set({'enabled': v}, SetOptions(merge: true)); await d.refreshFromFirestore(); }), IconButton(icon: const Icon(Icons.edit), onPressed: () => _editAddon(context, a)), IconButton(icon: const Icon(Icons.delete), onPressed: () async { await FirebaseFirestore.instance.collection('addons').doc(a.id).delete(); await d.refreshFromFirestore(); })]))),
          const SizedBox(height: 16),
          const Text('IPTV / Live channels', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('All live channels: those saved in Firestore and those imported on this device only. Tick channels to delete them, or use Select all.', style: TextStyle(color: Colors.white54)),
          Builder(builder: (c) {
            final keys = _iptvKeys(d);
            final live = d.items.where((e) => e.isLive || e.type == 'live').toList();
            final allSelected = keys.isNotEmpty && _selectedIptv.length == keys.length;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Checkbox(value: allSelected, onChanged: (v) => setState(() { if (v == true) { _selectedIptv.addAll(keys); } else { _selectedIptv.clear(); } })),
                const Text('Select all'),
                Text('  ${keys.length} channel(s)'),
                const Spacer(),
                ElevatedButton(onPressed: _selectedIptv.isEmpty ? null : () => _deleteIptv(d, _selectedIptv.toList(), 'selected channels'), child: Text('Delete selected (${_selectedIptv.length})')),
              ]),
              Row(children: [
                ElevatedButton.icon(icon: const Icon(Icons.delete_forever), label: const Text('Delete all IPTV'), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE50914)), onPressed: keys.isEmpty ? null : () => _deleteIptv(d, keys, 'all IPTV channels')),
              ]),
              if (keys.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('No IPTV channels right now.')),
              ...live.map((it) => CheckboxListTile(value: _selectedIptv.contains('fs:${it.id}'), onChanged: (v) => setState(() { if (v == true) { _selectedIptv.add('fs:${it.id}'); } else { _selectedIptv.remove('fs:${it.id}'); } }), title: Text(it.title), subtitle: const Text('Saved in Firestore'))),
              ...d.imported.map((it) => CheckboxListTile(value: _selectedIptv.contains('local:${it.id}'), onChanged: (v) => setState(() { if (v == true) { _selectedIptv.add('local:${it.id}'); } else { _selectedIptv.remove('local:${it.id}'); } }), title: Text(it.title), subtitle: const Text('Imported on this device only'))),
            ]);
          }),
          const SizedBox(height: 16),
          const Text('App update', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('Set a newer build number than the installed app to show the update message to all users. The banner appears with an Update button that opens the download link.', style: TextStyle(color: Colors.white54)),
          _UpdateForm(data: d),
        ] else
          const Padding(padding: EdgeInsets.only(top: 12), child: Text('Sign in with an admin account to edit.')),
      ]),
    );
  }
}

// ---------- Add-ons (Stremio-style manifests) ----------
String _addonBase(String manifestUrl) {
  final u = manifestUrl.trim();
  return u.endsWith('/manifest.json') ? u.substring(0, u.length - '/manifest.json'.length) : u;
}

class AddonsPage extends StatefulWidget {
  final AppData data;
  const AddonsPage({super.key, required this.data});
  @override
  State<AddonsPage> createState() => _AddonsPageState();
}

class _AddonsPageState extends State<AddonsPage> {
  String msg = '';
  List<Map<String, dynamic>> catalogs = [];
  String addonName = '';
  String base = '';

  Future<void> _load(Addon a) async {
    setState(() { msg = 'Loading ${a.name}…'; catalogs = []; });
    try {
      final res = await http.get(Uri.parse(a.manifestUrl));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        addonName = (m['name'] ?? a.name) as String;
        base = _addonBase(a.manifestUrl);
        catalogs = List<Map<String, dynamic>>.from((m['catalogs'] as List?) ?? []);
        msg = catalogs.isEmpty ? 'This add-on has no catalogs.' : '';
      });
    } catch (e) { setState(() => msg = 'Failed: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.data.addons.where((a) => a.enabled).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Add-ons')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        if (enabled.isEmpty) const Text('No add-ons enabled. Add one in Admin first.'),
        ...enabled.map((a) => ListTile(leading: const Icon(Icons.extension), title: Text(a.name), subtitle: Text(a.description.isEmpty ? a.manifestUrl : a.description), onTap: () => _load(a))),
        if (msg.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(msg)),
        if (addonName.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(addonName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
        ...catalogs.map((c) => ListTile(leading: const Icon(Icons.list), title: Text((c['name'] ?? c['id'] ?? '') as String), subtitle: Text((c['type'] ?? '') as String), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddonCatalogPage(base: base, type: (c['type'] ?? 'movie') as String, catalogId: (c['id'] ?? '') as String, title: (c['name'] ?? '') as String))))),
      ]),
    );
  }
}

class AddonCatalogPage extends StatefulWidget {
  final String base, type, catalogId, title;
  const AddonCatalogPage({super.key, required this.base, required this.type, required this.catalogId, required this.title});
  @override
  State<AddonCatalogPage> createState() => _AddonCatalogPageState();
}

class _AddonCatalogPageState extends State<AddonCatalogPage> {
  List<Map<String, dynamic>> metas = [];
  String msg = 'Loading…';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(Uri.parse('${widget.base}/catalog/${widget.type}/${widget.catalogId}.json'));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() { metas = List<Map<String, dynamic>>.from((m['metas'] as List?) ?? []); msg = metas.isEmpty ? 'No items in this catalog.' : ''; });
    } catch (e) { setState(() => msg = 'Failed: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: msg.isNotEmpty && metas.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(msg, textAlign: TextAlign.center)))
          : ListView.builder(itemCount: metas.length, itemBuilder: (c, i) {
              final m = metas[i];
              return ListTile(
                leading: (m['poster'] as String?)?.isNotEmpty == true ? Image.network(m['poster'] as String, width: 40, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.movie)) : const Icon(Icons.movie),
                title: Text((m['name'] ?? '') as String),
                subtitle: Text(((m['description'] ?? '') as String).length > 80 ? '${((m['description'] ?? '') as String).substring(0, 80)}…' : (m['description'] ?? '') as String),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddonStreamsPage(base: widget.base, type: widget.type, id: (m['id'] ?? '') as String, title: (m['name'] ?? '') as String, poster: (m['poster'] ?? '') as String))),
              );
            }),
    );
  }
}

class AddonStreamsPage extends StatefulWidget {
  final String base, type, id, title, poster;
  const AddonStreamsPage({super.key, required this.base, required this.type, required this.id, required this.title, required this.poster});
  @override
  State<AddonStreamsPage> createState() => _AddonStreamsPageState();
}

class _AddonStreamsPageState extends State<AddonStreamsPage> {
  List<Map<String, dynamic>> streams = [];
  String msg = 'Loading streams…';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await http.get(Uri.parse('${widget.base}/stream/${widget.type}/${widget.id}.json'));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final m = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() { streams = List<Map<String, dynamic>>.from((m['streams'] as List?) ?? []); msg = streams.isEmpty ? 'No streams for this title.' : ''; });
    } catch (e) { setState(() => msg = 'Failed: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: msg.isNotEmpty && streams.isEmpty
          ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(msg, textAlign: TextAlign.center)))
          : ListView.builder(itemCount: streams.length, itemBuilder: (c, i) {
              final st = streams[i];
              final url = (st['url'] as String?) ?? '';
              final infoHash = (st['infoHash'] as String?) ?? '';
              final title = (st['title'] as String?) ?? (st['name'] as String?) ?? 'Stream ${i + 1}';
              final isTorrent = infoHash.isNotEmpty || url.startsWith('magnet:');
              final magnet = url.startsWith('magnet:') ? url : (infoHash.isNotEmpty ? 'magnet:?xt=urn:btih:$infoHash' : '');
              return ListTile(
                leading: Icon(isTorrent ? Icons.download : Icons.play_arrow),
                title: Text(title),
                subtitle: Text(isTorrent ? 'Torrent — opens in a torrent app' : url),
                trailing: isTorrent
                    ? TextButton(child: const Text('Open torrent'), onPressed: () async { final uri = Uri.tryParse(magnet); if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication); })
                    : IconButton(icon: const Icon(Icons.play_arrow), onPressed: () { final item = Item(id: 'addon-${widget.id}-$i', categoryId: widget.type, title: widget.title, url: url); Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerPage(item: item))); }),
              );
            }),
    );
  }
}

// ---------- App update form (Admin only) ----------
class _UpdateForm extends StatefulWidget {
  final AppData data;
  const _UpdateForm({required this.data});
  @override
  State<_UpdateForm> createState() => _UpdateFormState();
}

class _UpdateFormState extends State<_UpdateForm> {
  late final TextEditingController _build;
  late final TextEditingController _version;
  late final TextEditingController _url;
  late final TextEditingController _notes;
  String _msg = '';
  @override
  void initState() {
    super.initState();
    _build = TextEditingController(text: '${widget.data.latestBuild}');
    _version = TextEditingController(text: widget.data.latestVersionName);
    _url = TextEditingController(text: widget.data.updateUrl);
    _notes = TextEditingController(text: widget.data.updateNotes);
  }

  @override
  void dispose() {
    _build.dispose();
    _version.dispose();
    _url.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(controller: _build, decoration: const InputDecoration(labelText: 'Latest build number (e.g. 6)'), keyboardType: TextInputType.number),
      TextField(controller: _version, decoration: const InputDecoration(labelText: 'Version name (e.g. 1.0.5)')),
      TextField(controller: _url, decoration: const InputDecoration(labelText: 'Download URL (APK link)')),
      TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notes (optional)')),
      const SizedBox(height: 8),
      ElevatedButton.icon(
        icon: const Icon(Icons.publish),
        label: const Text('Publish update'),
        onPressed: () async {
          try {
            final buildNo = int.tryParse(_build.text.trim()) ?? 0;
            await FirebaseFirestore.instance.collection('config').doc('app_update').set({
              'latestBuild': buildNo,
              'latestVersionName': _version.text.trim(),
              'downloadUrl': _url.text.trim(),
              'notes': _notes.text.trim(),
            }, SetOptions(merge: true));
            await FirebaseFirestore.instance.collection('updates').add({'versionName': _version.text.trim(), 'build': buildNo, 'notes': _notes.text.trim(), 'downloadUrl': _url.text.trim(), 'createdAt': FieldValue.serverTimestamp()});
            await widget.data.checkUpdate();
            await widget.data.refreshFromFirestore();
            setState(() => _msg = 'Update published — it is now in the Updates inbox (bell) and the banner. To push it to phones that are closed, send one message from Firebase Console > Cloud Messaging to topic app_updates with the download link in the data.');
          } catch (e) {
            setState(() => _msg = 'Publish failed: $e');
          }
        },
      ),
      if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg)),
      const SizedBox(height: 8),
      OutlinedButton.icon(icon: const Icon(Icons.notifications_active), label: const Text('Open Firebase Cloud Messaging'), onPressed: () async { final uri = Uri.parse('https://console.firebase.google.com/project/anime-app-556c8/notification'); if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication); }),
    ]);
  }
}
