// Profile: sign-in, Hanimo ID, My List, Continue Watching, language.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:animeapp/data/firebase/auth_service.dart';
import 'package:animeapp/domain/anime.dart';
import 'package:animeapp/l10n/gen/app_localizations.dart';
import 'package:animeapp/presentation/app_state.dart';
import 'package:animeapp/presentation/theme.dart';
import 'package:animeapp/presentation/screens/item_page.dart';
import 'package:animeapp/presentation/widgets/anime_card.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final d = context.watch<AppState>();
    final l10n = AppLocalizations.of(context)!;
    final user = d.user;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.profile)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (user == null) ...[
            const Icon(Icons.account_circle, size: 80, color: Colors.white38),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                final res = await d.signIn();
                if (!context.mounted) return;
                if (res.isErr) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(res.errorOrNull!), backgroundColor: Colors.red.shade800),
                  );
                }
              },
              icon: const Icon(Icons.login),
              label: Text(l10n.signInWithGoogle),
            ),
            if (d.authError != null) ...[
              const SizedBox(height: 10),
              Text(d.authError!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ],
          ] else ...[
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                  child: user.photoURL == null ? const Icon(Icons.person, size: 30) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.displayName ?? user.email ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                      Text(user.email ?? '', style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(AuthService.hanimoIdFor(user.uid))),
                        ),
                        child: Chip(label: Text(AuthService.hanimoIdFor(user.uid)), avatar: const Icon(Icons.badge, size: 16)),
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.logout), onPressed: () => d.signOut(), tooltip: l10n.signOut),
              ],
            ),
            if (d.isAdmin)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Chip(label: Text(l10n.admin), backgroundColor: HanimoColors.violet),
              ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text(l10n.settings, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('العربية'),
            subtitle: const Text('Arabic interface'),
            value: d.langIsArabic,
            onChanged: (v) => d.setLanguage(v),
          ),
          const SizedBox(height: 24),
          Text(l10n.myList, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (d.favourites.isEmpty)
            const Text('Nothing saved yet — tap the heart on any title.', style: TextStyle(color: Colors.white54))
          else
            SizedBox(
              height: 210,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: d.favourites.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final id = d.favourites.elementAt(i);
                  final anime = Anime(id: id, title: d.favouriteTitles[id] ?? id, imageUrl: '');
                  return AnimeCard(
                    anime: anime,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ItemPage(anime: anime))),
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
          Text(l10n.continueWatching, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (d.progress.isEmpty)
            const Text('Nothing started yet.', style: TextStyle(color: Colors.white54))
          else
            Column(
              children: [
                for (final id in d.progress.keys)
                  ListTile(
                    title: Text(d.progressTitles[id] ?? id),
                    subtitle: LinearProgressIndicator(value: d.progress[id]),
                    trailing: Text('${((d.progress[id] ?? 0) * 100).round()}%'),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ItemPage(anime: Anime(id: id, title: d.progressTitles[id] ?? id)),
                      ),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
