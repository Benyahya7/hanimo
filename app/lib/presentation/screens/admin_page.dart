// Admin — the owner's control room. Every action shows what happened:
// success in green, the real error in red, on the page itself.
// Deletes are optimistic (the row leaves at once) and restore themselves
// with the error shown when the server says no. (The 1.0.14 lesson.)
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:animeapp/app_constants.dart';
import 'package:animeapp/domain/anime.dart';
import 'package:animeapp/l10n/gen/app_localizations.dart';
import 'package:animeapp/presentation/app_state.dart';
import 'package:animeapp/presentation/theme.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  String? _msg;
  bool _msgIsError = false;

  void _say(String message, {bool error = false}) {
    setState(() {
      _msg = message;
      _msgIsError = error;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: error ? Colors.red.shade800 : Colors.green.shade800),
    );
  }

  Future<void> _deleteItem(AppState d, CatalogItem item) async {
    d.dropLocalItem(item.id);
    final res = await d.store.deleteItem(item.id);
    if (res.isOk) {
      _say('Deleted.');
    } else {
      await d.refreshCatalog();
      _say(res.errorOrNull ?? 'Delete failed.', error: true);
    }
  }

  Future<void> _deleteCategory(AppState d, Category c) async {
    d.dropLocalCategory(c.id);
    final res = await d.store.deleteCategory(c.id);
    if (res.isOk) {
      _say('Deleted.');
    } else {
      await d.refreshCatalog();
      _say(res.errorOrNull ?? 'Delete failed.', error: true);
    }
  }

  Future<void> _import(AppState d) async {
    _say('Importing from Animeify…');
    final res = await d.store.importTopAnime();
    if (res.isOk) {
      await d.refreshCatalog();
      _say('Imported ${res.valueOrNull} titles.');
    } else {
      _say(res.errorOrNull ?? 'Import failed.', error: true);
    }
  }

  Future<void> _editCategory(AppState d, Category? existing) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final desc = TextEditingController(text: existing?.description ?? '');
    final image = TextEditingController(text: existing?.imageUrl ?? '');
    final order = TextEditingController(text: '${existing?.order ?? 0}');
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? l10n.add : l10n.edit),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: InputDecoration(labelText: l10n.title)),
              TextField(controller: desc, decoration: InputDecoration(labelText: l10n.description)),
              TextField(controller: image, decoration: InputDecoration(labelText: l10n.imageUrl)),
              TextField(controller: order, decoration: const InputDecoration(labelText: 'Order'), keyboardType: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.save)),
        ],
      ),
    );
    if (ok != true) return;
    final res = await d.store.saveCategory(
      Category(id: existing?.id ?? '', name: name.text.trim(), description: desc.text.trim(), imageUrl: image.text.trim(), order: int.tryParse(order.text) ?? 0),
    );
    if (res.isOk) {
      await d.refreshCatalog();
      _say('Saved.');
    } else {
      _say(res.errorOrNull ?? 'Save failed.', error: true);
    }
  }

  Future<void> _editItem(AppState d, CatalogItem? existing) async {
    final title = TextEditingController(text: existing?.title ?? '');
    final desc = TextEditingController(text: existing?.description ?? '');
    final image = TextEditingController(text: existing?.imageUrl ?? '');
    final url = TextEditingController(text: existing?.url ?? '');
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? l10n.add : l10n.edit),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: title, decoration: InputDecoration(labelText: l10n.title)),
              TextField(controller: desc, decoration: InputDecoration(labelText: l10n.description)),
              TextField(controller: image, decoration: InputDecoration(labelText: l10n.imageUrl)),
              TextField(controller: url, decoration: const InputDecoration(labelText: 'Video URL')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.save)),
        ],
      ),
    );
    if (ok != true) return;
    final res = await d.store.saveItem(
      CatalogItem(
        id: existing?.id ?? 'manual-${DateTime.now().millisecondsSinceEpoch}',
        categoryId: existing?.categoryId ?? 'anime-series',
        title: title.text.trim(),
        description: desc.text.trim(),
        imageUrl: image.text.trim(),
        url: url.text.trim(),
        type: existing?.type ?? 'series',
      ),
    );
    if (res.isOk) {
      await d.refreshCatalog();
      _say('Saved.');
    } else {
      _say(res.errorOrNull ?? 'Save failed.', error: true);
    }
  }

  Future<void> _publishUpdate(AppState d) async {
    final version = TextEditingController(text: kCurrentVersionName);
    final url = TextEditingController();
    final notes = TextEditingController();
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.publishUpdate),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: version, decoration: InputDecoration(labelText: l10n.versionName)),
              TextField(controller: url, decoration: InputDecoration(labelText: l10n.downloadUrl)),
              TextField(controller: notes, decoration: InputDecoration(labelText: l10n.notes), maxLines: 3),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.publishUpdate)),
        ],
      ),
    );
    if (ok != true) return;
    final res = await d.store.publishUpdate(
      build: kCurrentBuild + 1,
      versionName: version.text.trim(),
      downloadUrl: url.text.trim(),
      notes: notes.text.trim(),
    );
    if (res.isOk) {
      _say('Update published.');
    } else {
      _say(res.errorOrNull ?? 'Publish failed.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<AppState>();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.admin),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => d.refreshCatalog(), tooltip: l10n.retry),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_msg != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _msgIsError ? const Color(0xFF2A1A1A) : const Color(0xFF1A2A1A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _msgIsError ? Colors.red.shade900 : Colors.green.shade900),
              ),
              child: Text(_msg!, style: TextStyle(color: _msgIsError ? Colors.redAccent : Colors.greenAccent)),
            ),
          Row(
            children: [
              _StatCard(label: l10n.categories, value: '${d.categories.length}'),
              const SizedBox(width: 12),
              _StatCard(label: l10n.items, value: '${d.items.length}'),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _import(d),
            icon: const Icon(Icons.download),
            label: Text(l10n.importTopAnime),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _publishUpdate(d),
            icon: const Icon(Icons.system_update),
            label: Text(l10n.publishUpdate),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text(l10n.categories, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.add), onPressed: () => _editCategory(d, null)),
            ],
          ),
          if (d.catalogError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(d.catalogError!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
          if (d.categories.isEmpty) const Text('No categories yet — add one, or import.', style: TextStyle(color: Colors.white54)),
          for (final c in d.categories)
            ListTile(
              title: Text(c.name.isEmpty ? c.id : c.name),
              subtitle: Text('${c.order}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.edit), onPressed: () => _editCategory(d, c)),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => _deleteCategory(d, c)),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text(l10n.items, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.add), onPressed: () => _editItem(d, null)),
            ],
          ),
          if (d.items.isEmpty) const Text('No items yet — import from Animeify, or add one.', style: TextStyle(color: Colors.white54)),
          for (final item in d.items)
            ListTile(
              leading: item.imageUrl.isEmpty
                  ? null
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(width: 40, height: 60, child: Image.network(item.imageUrl, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox())),
                    ),
              title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(item.animeifyId.isEmpty ? item.type : 'Animeify · ${item.animeifyId}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.edit), onPressed: () => _editItem(d, item)),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () => _deleteItem(d, item)),
                ],
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: HanimoColors.card, borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}
