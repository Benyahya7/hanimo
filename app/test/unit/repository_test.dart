import 'dart:convert';

import 'package:animeapp/data/animeify/animeify_api.dart';
import 'package:animeapp/data/animeify/animeify_repository.dart';
import 'package:animeapp/domain/anime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('AnimeifyRepository returns readable Results', () {
    AnimeifyRepository repoFor(String path, Object body) => AnimeifyRepository(
          api: AnimeifyApi(
            poster: (url, fields) async => url.path.contains(path) ? http.Response(jsonEncode(body), 200) : http.Response('[]', 200),
          ),
        );

    test('getHome: empty feed is an Err with a message, not silent', () async {
      final repo = repoFor('load_home.php', {});
      final res = await repo.getHome();
      expect(res.isErr, isTrue);
      expect(res.errorOrNull, contains('Animeify'));
    });

    test('getHome: a real feed is Ok', () async {
      final repo = AnimeifyRepository(
        api: AnimeifyApi(
          poster: (url, fields) async {
            if (url.path.contains('load_home.php')) {
              return http.Response(
                jsonEncode({
                  'LatestAnime': [
                    {'AnimeId': 'xA', 'EN_Title': 'A', 'Type': 'SERIES'},
                  ],
                  'LatestEpisodes': [],
                  'Broadcast': [],
                  'Premiere': [],
                }),
                200,
              );
            }
            return http.Response('[]', 200);
          },
        ),
      );
      final res = await repo.getHome();
      expect(res.isOk, isTrue);
      expect(res.valueOrNull!.latestAnime, hasLength(1));
    });

    test('getCatalog: empty first page is an Err, later pages are Ok-empty', () async {
      final repo = repoFor('load_anime_list_v2.php', []);
      final first = await repo.getCatalog(from: 0);
      expect(first.isErr, isTrue);
      final next = await repo.getCatalog(from: 20);
      expect(next.isOk, isTrue);
      expect(next.valueOrNull, isEmpty);
    });

    test('search: empty result is an Err', () async {
      final repo = repoFor('load_anime_list_v2.php', []);
      final res = await repo.search('Naruto');
      expect(res.isErr, isTrue);
    });

    test('getEpisodes: no episodes is an Err with a message', () async {
      final repo = repoFor('load_episodes.php', []);
      final res = await repo.getEpisodes('xA');
      expect(res.isErr, isTrue);
      expect(res.errorOrNull, contains('episode'));
    });

    test('getServers: no servers is an Err', () async {
      final repo = repoFor('load_servers.php', {});
      final res = await repo.getServers(animeId: 'xA', episode: 1, animeType: 'series');
      expect(res.isErr, isTrue);
    });

    test('getServers: servers list through, best first', () async {
      final repo = repoFor('load_servers.php', {
        'CurrentEpisode': {'Episode': '1', 'FRFhdQ': 'f1', 'FRLink': 'h1'},
        'PreviousEpisode': {},
        'NextEpisode': {},
      });
      final res = await repo.getServers(animeId: 'xA', episode: 1, animeType: 'series');
      expect(res.isOk, isTrue);
      expect(res.valueOrNull!.first.host, 'MediaFire');
      expect(res.valueOrNull!.first.quality, 'FHD');
    });

    test('resolveServer: Drive resolves to the public uc link', () async {
      final repo = AnimeifyRepository(api: AnimeifyApi(poster: (url, fields) async => http.Response('[]', 200)));
      final res = await repo.resolveServer(const Server(host: 'Google Drive', id: 'abc123', kind: 'direct'));
      expect(res.isOk, isTrue);
      expect(res.valueOrNull, 'https://drive.google.com/uc?id=abc123&export=download');
    });
  });
}
