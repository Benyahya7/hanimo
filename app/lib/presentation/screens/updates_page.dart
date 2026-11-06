// Updates inbox: notices the owner publishes from Admin.
// Tapping one with a download link opens it outside the app.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:animeapp/data/firebase/catalog_store.dart';
import 'package:animeapp/domain/anime.dart';
import 'package:animeapp/l10n/gen/app_localizations.dart';
import 'package:animeapp/presentation/theme.dart';

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key});

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  final _store = CatalogStore();
  List<UpdateNotice> _updates = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _store.listUpdates();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.isOk) {
        _updates = res.valueOrNull!;
      } else {
        _error = res.errorOrNull;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.updates)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: Text(l10n.retry)),
                      ],
                    ),
                  ),
                )
              : _updates.isEmpty
                  ? Center(child: Text(l10n.noUpdatesYet))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        itemCount: _updates.length,
                        itemBuilder: (_, i) {
                          final u = _updates[i];
                          return ListTile(
                            leading: const Icon(Icons.system_update, color: HanimoColors.pink),
                            title: Text(u.versionName.isEmpty ? 'Hanimo update' : 'Hanimo ${u.versionName}'),
                            subtitle: Text(u.notes, maxLines: 3, overflow: TextOverflow.ellipsis),
                            trailing: u.downloadUrl.isEmpty ? null : const Icon(Icons.download),
                            onTap: u.downloadUrl.isEmpty
                                ? null
                                : () => launchUrl(Uri.parse(u.downloadUrl), mode: LaunchMode.externalApplication),
                          );
                        },
                      ),
                    ),
    );
  }
}
