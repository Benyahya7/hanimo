import 'dart:convert';

import 'package:animeapp/data/animeify/animeify_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('pure extractors', () {
    test('MediaFire direct link is pulled from the page', () {
      const html = '<a href="https://download2390.mediafire.com/abc/file.mp4">x</a>';
      expect(extractMediaFireDirect(html), 'https://download2390.mediafire.com/abc/file.mp4');
    });

    test('MediaFire scrambled URL is base64-decoded', () {
      final direct = 'https://download1.mediafire.com/xyz/file.mp4';
      final encoded = base64.encode(utf8.encode(direct));
      final html = 'data-scrambled-url="$encoded"';
      expect(extractMediaFireScrambled(html), direct);
    });

    test('SolidFiles streamUrl is pulled from the page', () {
      const html = '{"streamUrl":"http://solidfiles.com/dl.mp4"}';
      expect(extractSolidFilesDirect(html), 'http://solidfiles.com/dl.mp4');
    });
  });

  group('serversForEpisode priority', () {
    test('MediaFire FHD first, SVLink "1" skipped, OK.ru + Mega last', () {
      const ep = AnimeifyEpisode(
        number: 8,
        frFhdQ: 'fhd1',
        frLink: 'hd1',
        frLowQ: 'low1',
        sfLink: 'sf1',
        gdLink: 'gd1',
        svLink: '1',
        lbLink: '',
        okLink: '16765440821781',
        maLink: 'fileId!key',
      );
      final servers = serversForEpisode(ep);
      expect(servers.map((s) => s.host), ['MediaFire', 'MediaFire', 'MediaFire', 'SolidFiles', 'Google Drive', 'OK.ru', 'Mega']);
      expect(servers.map((s) => s.quality), ['FHD', 'HD', 'Low', '', '', '', '']);
      expect(servers.where((s) => s.host == 'SendVid'), isEmpty);
      expect(servers.where((s) => s.host == 'FileLions'), isEmpty);
      expect(servers.last.kind, 'external');
      expect(servers.last.megaUrl, 'https://mega.nz/file/fileId#key');
      expect(servers[5].okEmbedUrl, 'https://ok.ru/videoembed/16765440821781');
    });

    test('URL-like FileLions/SendVid are kept', () {
      const ep = AnimeifyEpisode(number: 1, lbLink: 'https://filelions.to/v/abc', svLink: 'https://sendvid.com/xyz');
      final servers = serversForEpisode(ep);
      expect(servers.map((s) => s.host), containsAll(['FileLions', 'SendVid']));
    });
  });

  group('parsers', () {
    test('"tempres" MalId parses to 0, string numbers parse', () {
      final a = AnimeifyAnime.fromJson({
        'AnimeId': 'xOnePiece',
        'EN_Title': 'One Piece',
        'Genres': 'Action, Adventure',
        'Score': '8.7',
        'Episodes': '1120',
        'Premiered': 'Fall 1999',
        'Type': 'SERIES',
        'MalId': 'tempres',
      });
      expect(a.malId, 0);
      expect(a.score, 8.7);
      expect(a.episodeCount, 1120);
      expect(a.year, 1999);
      expect(a.genres, ['Action', 'Adventure']);
    });

    test('MOVIE type maps to movie', () {
      final a = AnimeifyAnime.fromJson({'AnimeId': 'x1', 'EN_Title': 'A', 'Type': 'MOVIE'});
      expect(a.type, 'movie');
      expect(a.thumbnailUrl, '');
    });

    test('thumbnail + trailer URLs are built', () {
      final a = AnimeifyAnime.fromJson({'AnimeId': 'x1', 'EN_Title': 'A', 'Thumbnail': 'one.jpg', 'YTTrailer': 'dQw4w9WgXcQ'});
      expect(a.thumbnailUrl, 'https://animeify.net/animeify/files/thumbnails/one.jpg');
      expect(a.trailerUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    });
  });

  group('season + broadcast helpers', () {
    test('current season by month', () {
      expect(animeifyCurrentSeason(DateTime(2026, 1, 5)), 'Winter 2026');
      expect(animeifyCurrentSeason(DateTime(2026, 5, 5)), 'Spring 2026');
      expect(animeifyCurrentSeason(DateTime(2026, 8, 5)), 'Summer 2026');
      expect(animeifyCurrentSeason(DateTime(2026, 11, 6)), 'Fall 2026');
    });

    test('broadcast day is the weekday name', () {
      expect(animeifyTodayBroadcast(DateTime(2026, 11, 6)), 'FRIDAY'); // 2026-11-06 is a Friday
    });
  });

  group('client with fake transport', () {
    http.Response okJson(Object body) => http.Response(jsonEncode(body), 200);

    test('fetchCatalog sends the token and parses titles', () async {
      var sawFields = <String, String>{};
      final api = AnimeifyApi(
        poster: (url, fields) async {
          sawFields = fields;
          expect(url.path, contains('load_anime_list_v2.php'));
          return okJson([
            {'AnimeId': 'xNaruto', 'EN_Title': 'Naruto', 'Score': '8.0', 'Type': 'SERIES'},
          ]);
        },
      );
      final list = await api.fetchCatalog();
      expect(list, hasLength(1));
      expect(list.first.title, 'Naruto');
      expect(sawFields['Token'], animeifyToken);
      expect(sawFields['UserId'], '0');
    });

    test('fetchHome parses latest episodes pairs', () async {
      final api = AnimeifyApi(
        poster: (url, fields) async => okJson({
          'LatestAnime': [
            {'AnimeId': 'xA', 'EN_Title': 'A', 'Type': 'SERIES'},
          ],
          'LatestEpisodes': [
            {
              'Anime': {'AnimeId': 'xB', 'EN_Title': 'B', 'Type': 'SERIES'},
              'Episode': {'Episode': '10'},
            },
          ],
          'Broadcast': [],
          'Premiere': [],
        }),
      );
      final home = await api.fetchHome();
      expect(home.latestAnime, hasLength(1));
      expect(home.latestEpisodes, hasLength(1));
      expect(home.latestEpisodes.first.$1.title, 'B');
      expect(home.latestEpisodes.first.$2.number, 10);
    });

    test('fetchDetails drops a defaced plot', () async {
      final api = AnimeifyApi(
        poster: (url, fields) async => okJson({
          'Plot': 'HACKED_BY_CTF — pwned',
          'RelatedAnime': [],
        }),
      );
      final details = await api.fetchDetails('xOnePiece');
      expect(details.plot, '');
    });

    test('fetchEpisodes sorts ascending and skips empty', () async {
      final api = AnimeifyApi(
        poster: (url, fields) async => okJson([
          {'Episode': '12'},
          {'Episode': '3'},
          {'Episode': '0'},
        ]),
      );
      final eps = await api.fetchEpisodes('xA');
      expect(eps.map((e) => e.number), [3, 12]);
    });

    test('a failed request returns an empty list, never throws', () async {
      final api = AnimeifyApi(poster: (url, fields) async => null);
      expect(await api.fetchCatalog(), isEmpty);
      expect(await api.fetchTrending(), isEmpty);
      expect((await api.fetchHome()).latestAnime, isEmpty);
    });
  });
}
