// Root: bottom tabs + update banner + back-button behaviour.
// Admin tab appears only for the owner.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:animeapp/l10n/gen/app_localizations.dart';
import 'package:animeapp/presentation/app_state.dart';
import 'package:animeapp/presentation/theme.dart';
import 'package:animeapp/presentation/screens/admin_page.dart';
import 'package:animeapp/presentation/screens/browse_page.dart';
import 'package:animeapp/presentation/screens/home_page.dart';
import 'package:animeapp/presentation/screens/profile_page.dart';
import 'package:animeapp/presentation/screens/search_page.dart';

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _index = 0;
  DateTime? _lastBack;

  @override
  Widget build(BuildContext context) {
    final d = context.watch<AppState>();
    final l10n = AppLocalizations.of(context)!;
    final tabs = <Widget>[
      const HomePage(),
      const BrowsePage(),
      const SearchPage(),
      const ProfilePage(),
      if (d.isAdmin) const AdminPage(),
    ];
    final labels = <String>[l10n.home, l10n.browse, l10n.search, l10n.profile, if (d.isAdmin) l10n.admin];
    final icons = <IconData>[Icons.home, Icons.grid_view, Icons.search, Icons.person, Icons.admin_panel_settings];
    final safeIndex = _index.clamp(0, tabs.length - 1);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_index != 0) {
          setState(() => _index = 0);
          return;
        }
        final now = DateTime.now();
        if (_lastBack == null || now.difference(_lastBack!) > const Duration(seconds: 2)) {
          _lastBack = now;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.pressBackAgain), duration: const Duration(seconds: 2)));
        } else {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(index: safeIndex, children: tabs),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: safeIndex,
          onTap: (i) => setState(() => _index = i),
          type: BottomNavigationBarType.fixed,
          backgroundColor: HanimoColors.surface,
          selectedItemColor: HanimoColors.pink,
          unselectedItemColor: Colors.white60,
          items: [
            for (var i = 0; i < labels.length; i++)
              BottomNavigationBarItem(icon: Icon(icons[i]), label: labels[i]),
          ],
        ),
      ),
    );
  }
}
