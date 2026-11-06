// Servers bottom sheet — one episode, every server Animeify lists.
// Direct servers resolve to a playable mp4 and open the in-app player;
// external ones (OK.ru, Mega) open outside the app. A server that cannot
// be resolved says so on its own row instead of doing nothing.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:animeapp/data/animeify/animeify_repository.dart';
import 'package:animeapp/domain/anime.dart';
import 'package:animeapp/l10n/gen/app_localizations.dart';
import 'package:animeapp/presentation/screens/player_page.dart';
import 'package:animeapp/presentation/theme.dart';

Future<void> showServersSheet(BuildContext context, {required Anime anime, required int episodeNumber}) async {
  final l10n = AppLocalizations.of(context)!;
  final repo = AnimeifyRepository();
  final res = await repo.getServers(animeId: anime.id, episode: episodeNumber, animeType: anime.type);
  if (!context.mounted) return;
  if (res.isErr) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.errorOrNull!)));
    return;
  }
  final servers = res.valueOrNull!;
  final fileName = '${anime.title.replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '').trim()}_E$episodeNumber';

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: HanimoColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (_, controller) => _ServersList(
        anime: anime,
        episodeNumber: episodeNumber,
        servers: servers,
        fileName: fileName,
        l10n: l10n,
      ),
    ),
  );
}

class _ServersList extends StatefulWidget {
  final Anime anime;
  final int episodeNumber;
  final List<Server> servers;
  final String fileName;
  final AppLocalizations l10n;
  const _ServersList({required this.anime, required this.episodeNumber, required this.servers, required this.fileName, required this.l10n});

  @override
  State<_ServersList> createState() => _ServersListState();
}

class _ServersListState extends State<_ServersList> {
  String? _resolvingId;
  String? _rowError;

  Future<void> _open(Server server) async {
    setState(() {
      _resolvingId = '${server.host}-${server.id}';
      _rowError = null;
    });
    final repo = AnimeifyRepository();
    final res = await repo.resolveServer(server, fileName: widget.fileName);
    if (!mounted) return;
    setState(() => _resolvingId = null);
    if (res.isErr) {
      setState(() => _rowError = res.errorOrNull);
      return;
    }
    final url = res.valueOrNull!;
    if (server.playsInApp) {
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerPage(anime: widget.anime, episodeNumber: widget.episodeNumber, videoUrl: url),
        ),
      );
    } else {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        setState(() => _rowError = widget.l10n.linkResolveFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 12),
        Text(
          '${widget.anime.title} — Ep ${widget.episodeNumber}',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(widget.l10n.servers, style: const TextStyle(color: Colors.white70)),
        if (_rowError != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFF2A1A1A), borderRadius: BorderRadius.circular(8)),
            child: Text(_rowError!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
          ),
        ],
        const SizedBox(height: 10),
        for (final server in widget.servers)
          Card(
            color: HanimoColors.card,
            child: ListTile(
              leading: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(gradient: HanimoGradients.brand, shape: BoxShape.circle),
                child: Icon(server.playsInApp ? Icons.play_arrow : Icons.open_in_new, color: Colors.white),
              ),
              title: Text(server.label, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(server.playsInApp ? widget.l10n.playInApp : widget.l10n.openExternally),
              trailing: _resolvingId == '${server.host}-${server.id}'
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_right),
              onTap: () => _open(server),
            ),
          ),
      ],
    );
  }
}
