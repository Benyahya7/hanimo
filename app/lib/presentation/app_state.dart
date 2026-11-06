// AppState — the single source of truth the screens render.
// Screens never fetch. They read fields here and call methods here.
// Every load stores its error (if any) in a field the UI shows with Retry.
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:animeapp/app_constants.dart';
import 'package:animeapp/core/result.dart';
import 'package:animeapp/data/animeify/animeify_repository.dart';
import 'package:animeapp/data/firebase/auth_service.dart';
import 'package:animeapp/data/firebase/catalog_store.dart';
import 'package:animeapp/domain/anime.dart';

class AppState extends ChangeNotifier {
  final AuthService authService;
  final AnimeifyRepository repo;
  final CatalogStore store;
  AppState({AuthService? auth, AnimeifyRepository? repository, CatalogStore? catalog})
      : authService = auth ?? AuthService(),
        repo = repository ?? AnimeifyRepository(),
        store = catalog ?? CatalogStore();

  // ----- session -----
  User? user;
  bool isAdmin = false;
  bool langIsArabic = false;
  String? authError;

  // ----- home -----
  bool homeLoading = false;
  String? homeError;
  HomeFeed homeFeed = const HomeFeed();
  List<Anime> trendingAnime = [];
  List<Anime> newAnime = [];

  // ----- catalog (owner's Firestore library) -----
  List<Category> categories = [];
  List<CatalogItem> items = [];
  String? catalogError;

  // ----- local lists -----
  final Map<String, double> progress = {}; // animeify id -> 0..1
  final Map<String, String> progressTitles = {};
  final Set<String> favourites = {};
  final Map<String, String> favouriteTitles = {};

  // ----- update -----
  int latestBuild = 0;
  String latestVersionName = '';
  String updateDownloadUrl = '';
  String updateNotes = '';
  bool get hasUpdate => latestBuild > kCurrentBuild;

  static const _kLang = 'lang';
  static const _kFavs = 'favourites';
  static const _kFavTitles = 'favouriteTitles';
  static const _kProgress = 'progress';
  static const _kProgressTitles = 'progressTitles';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    langIsArabic = prefs.getString(_kLang) == 'ar';
    favourites.addAll((prefs.getStringList(_kFavs) ?? []).toSet());
    final favTitles = jsonDecode(prefs.getString(_kFavTitles) ?? '{}') as Map<String, dynamic>;
    favouriteTitles.addAll(favTitles.map((k, v) => MapEntry(k, '$v')));
    final prog = jsonDecode(prefs.getString(_kProgress) ?? '{}') as Map<String, dynamic>;
    progress.addAll(prog.map((k, v) => MapEntry(k, (v as num).toDouble())));
    final progTitles = jsonDecode(prefs.getString(_kProgressTitles) ?? '{}') as Map<String, dynamic>;
    progressTitles.addAll(progTitles.map((k, v) => MapEntry(k, '$v')));
    user = null;
    try {
      user = authService.currentUser;
      if (user != null) isAdmin = await authService.isAdmin();
    } catch (_) {
      // Firebase unavailable (e.g. web init failed) — run local-only.
      user = null;
    }
    notifyListeners();
    await refreshAll();
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kFavs, favourites.toList());
    await prefs.setString(_kFavTitles, jsonEncode(favouriteTitles));
    await prefs.setString(_kProgress, jsonEncode(progress));
    await prefs.setString(_kProgressTitles, jsonEncode(progressTitles));
  }

  Future<void> setLanguage(bool arabic) async {
    langIsArabic = arabic;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLang, arabic ? 'ar' : 'en');
    notifyListeners();
  }

  // ----- sign-in -----

  Future<Result<bool>> signIn() async {
    final res = await authService.signIn();
    if (res.isOk) {
      user = authService.currentUser;
      isAdmin = res.valueOrNull == true;
      authError = null;
    } else {
      authError = res.errorOrNull;
    }
    notifyListeners();
    return res;
  }

  Future<void> signOut() async {
    await authService.signOut();
    user = null;
    isAdmin = false;
    notifyListeners();
  }

  // ----- loads -----

  Future<void> refreshAll() async {
    await Future.wait([refreshHome(), refreshCatalog(), checkUpdate()]);
  }

  Future<void> refreshHome() async {
    homeLoading = true;
    homeError = null;
    notifyListeners();
    final res = await repo.getHome();
    if (res.isOk) {
      final feed = res.valueOrNull!;
      homeFeed = feed;
      newAnime = feed.latestAnime;
      final tr = await repo.getTrending();
      trendingAnime = tr.valueOrNull ?? feed.latestAnime;
      homeError = null;
    } else {
      homeError = res.errorOrNull;
    }
    homeLoading = false;
    notifyListeners();
  }

  Future<void> refreshCatalog() async {
    final cats = await store.listCategories();
    if (cats.isOk) {
      categories = cats.valueOrNull!;
    } else {
      catalogError = cats.errorOrNull;
    }
    final its = await store.listItems();
    if (its.isOk) {
      items = its.valueOrNull!;
      catalogError = null;
    } else {
      catalogError = its.errorOrNull;
    }
    notifyListeners();
  }

  Future<void> checkUpdate() async {
    final up = await store.latestUpdate();
    if (up != null) {
      latestBuild = up.build;
      latestVersionName = up.versionName;
      updateDownloadUrl = up.downloadUrl;
      updateNotes = up.notes;
      notifyListeners();
    }
  }

  // ----- local lists -----

  bool isFavourite(String id) => favourites.contains(id);

  Future<void> toggleFavourite(Anime anime) async {
    if (favourites.contains(anime.id)) {
      favourites.remove(anime.id);
      favouriteTitles.remove(anime.id);
    } else {
      favourites.add(anime.id);
      favouriteTitles[anime.id] = anime.title;
    }
    await _savePrefs();
    notifyListeners();
  }

  Future<void> setProgress(Anime anime, double fraction) async {
    progress[anime.id] = fraction.clamp(0, 1);
    progressTitles[anime.id] = anime.title;
    await _savePrefs();
    notifyListeners();
  }

  // ----- admin: optimistic local drops + message on failure -----
  // (The 1.0.14 lesson: delete must say what happened, on screen.)

  void dropLocalItem(String id) {
    items.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  void dropLocalCategory(String id) {
    categories.removeWhere((c) => c.id == id);
    notifyListeners();
  }
}
