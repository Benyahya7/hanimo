// Firestore catalog store — the Admin's data. Every method returns a
// Result so the Admin screen can always show what happened. Reads are
// lenient: one malformed document is skipped, never allowed to break a
// whole list (the 1.0.14 lesson).
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:animeapp/core/result.dart';
import 'package:animeapp/data/animeify/animeify_repository.dart';
import 'package:animeapp/domain/anime.dart';

class CatalogStore {
  final FirebaseFirestore db;
  final AnimeifyRepository repo;
  CatalogStore({FirebaseFirestore? db, AnimeifyRepository? repo})
      : db = db ?? FirebaseFirestore.instance,
        repo = repo ?? AnimeifyRepository();

  // ---------------- reads (lenient: bad docs skipped) ----------------

  Future<Result<List<Category>>> listCategories() async {
    try {
      final snap = await db.collection('categories').orderBy('order').get();
      final out = <Category>[];
      for (final d in snap.docs) {
        try {
          out.add(Category.fromMap(d.id, Map<String, dynamic>.from(d.data())));
        } catch (_) {
          // Skip the malformed document, keep the rest.
        }
      }
      return Result.ok(out);
    } catch (e) {
      return Err('Could not load categories: $e');
    }
  }

  Future<Result<List<CatalogItem>>> listItems() async {
    try {
      final snap = await db.collection('items').orderBy('title').get();
      final out = <CatalogItem>[];
      for (final d in snap.docs) {
        try {
          out.add(CatalogItem.fromMap(d.id, Map<String, dynamic>.from(d.data())));
        } catch (_) {}
      }
      return Result.ok(out);
    } catch (e) {
      return Err('Could not load items: $e');
    }
  }

  Future<Result<List<UpdateNotice>>> listUpdates() async {
    try {
      final snap = await db.collection('updates').orderBy('build', descending: true).get();
      final out = <UpdateNotice>[];
      for (final d in snap.docs) {
        try {
          out.add(UpdateNotice.fromMap(d.id, Map<String, dynamic>.from(d.data())));
        } catch (_) {}
      }
      return Result.ok(out);
    } catch (e) {
      return Err('Could not load updates: $e');
    }
  }

  // ---------------- writes (admin only per Firestore rules) ----------------

  Future<Result<void>> saveCategory(Category c) async {
    try {
      final ref = c.id.isEmpty ? db.collection('categories').doc() : db.collection('categories').doc(c.id);
      await ref.set(c.toMap(), SetOptions(merge: true));
      return const Ok(null);
    } catch (e) {
      return Err('Could not save category: $e');
    }
  }

  Future<Result<void>> deleteCategory(String id) async {
    try {
      await db.collection('categories').doc(id).delete();
      return const Ok(null);
    } catch (e) {
      return Err('Could not delete category: $e');
    }
  }

  Future<Result<void>> saveItem(CatalogItem item) async {
    try {
      await db.collection('items').doc(item.id).set(item.toMap(), SetOptions(merge: true));
      return const Ok(null);
    } catch (e) {
      return Err('Could not save item: $e');
    }
  }

  Future<Result<void>> deleteItem(String id) async {
    try {
      await db.collection('items').doc(id).delete();
      return const Ok(null);
    } catch (e) {
      return Err('Could not delete item: $e');
    }
  }

  /// Import the Animeify catalog into Firestore as items. Reports how
  /// many titles were saved — or the exact error when it fails.
  Future<Result<int>> importTopAnime({String categoryId = 'anime-series', int limit = 50}) async {
    try {
      final res = await repo.getCatalog();
      final list = res.valueOrNull;
      if (list == null) return Err(res.errorOrNull ?? 'Import failed: Animeify did not answer.');
      var saved = 0;
      for (final anime in list.take(limit)) {
        final item = CatalogItem.fromAnime(anime, categoryId: categoryId, order: saved);
        final w = await saveItem(item);
        if (w.isOk) saved++;
      }
      if (saved == 0) return const Err('Import failed: nothing could be saved to Firestore.');
      return Result.ok(saved);
    } catch (e) {
      return Err('Import failed: $e');
    }
  }

  // ---------------- app update ----------------

  Future<Result<void>> publishUpdate({required int build, required String versionName, required String downloadUrl, required String notes}) async {
    try {
      await db.collection('config').doc('app_update').set({
        'latestBuild': build,
        'latestVersionName': versionName,
        'downloadUrl': downloadUrl,
        'notes': notes,
      });
      await db.collection('updates').add({
        'build': build,
        'versionName': versionName,
        'downloadUrl': downloadUrl,
        'notes': notes,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return const Ok(null);
    } catch (e) {
      return Err('Could not publish update: $e');
    }
  }

  /// The latest published build, if any. No doc yet = no update.
  Future<({int build, String versionName, String downloadUrl, String notes})?> latestUpdate() async {
    try {
      final doc = await db.collection('config').doc('app_update').get();
      final m = doc.data();
      if (m == null) return null;
      return (
        build: (m['latestBuild'] as num?)?.toInt() ?? 0,
        versionName: (m['latestVersionName'] as String?) ?? '',
        downloadUrl: (m['downloadUrl'] as String?) ?? '',
        notes: (m['notes'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}
