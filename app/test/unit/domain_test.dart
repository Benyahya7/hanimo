import 'package:animeapp/domain/anime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CatalogItem.fromMap is lenient', () {
    test('string-typed numbers do not throw', () {
      final item = CatalogItem.fromMap('x1', {
        'title': 'One Piece',
        'score': '8.7',
        'year': '1999',
        'genres': 'Action, Adventure',
        'malId': 'tempres',
      });
      expect(item.score, 8.7);
      expect(item.year, 1999);
      expect(item.genres, ['Action, Adventure']);
      expect(item.malId, 0); // 'tempres' is not a number
    });

    test('missing fields fall back to defaults', () {
      final item = CatalogItem.fromMap('x2', {});
      expect(item.title, '');
      expect(item.type, 'series');
      expect(item.score, 0);
    });

    test('toMap round-trips through fromMap', () {
      const item = CatalogItem(id: 'a', categoryId: 'c', title: 'Naruto', score: 8.0, year: 2002, genres: ['Action'], episodeCount: 220);
      final again = CatalogItem.fromMap('a', item.toMap());
      expect(again.title, 'Naruto');
      expect(again.episodeCount, 220);
      expect(again.genres, ['Action']);
    });
  });

  group('Anime', () {
    test('isMovie reflects type', () {
      const s = Anime(id: 'x', title: 'A', type: 'series');
      const m = Anime(id: 'y', title: 'B', type: 'movie');
      expect(s.isMovie, isFalse);
      expect(m.isMovie, isTrue);
    });
  });

  group('Category', () {
    test('round-trips', () {
      const c = Category(id: 'c1', name: 'Anime Series', order: 1);
      final again = Category.fromMap('c1', c.toMap());
      expect(again.name, 'Anime Series');
      expect(again.order, 1);
    });
  });
}
