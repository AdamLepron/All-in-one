import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/util.dart';
import '../music/mini_player.dart';
import '../music/music_controller.dart';
import 'online.dart';
import 'online_library.dart';

const _countries = <(String, String?)>[
  ('Monde', null),
  ('France', 'FR'),
  ('Belgique', 'BE'),
  ('Suisse', 'CH'),
  ('Canada', 'CA'),
  ('Maroc', 'MA'),
  ('Royaume-Uni', 'GB'),
  ('États-Unis', 'US'),
];

/// Radios and podcasts from the Internet, played by the music player.
class RadioPage extends StatelessWidget {
  const RadioPage({super.key, this.directory, this.podcasts});

  /// Replaced in tests.
  final RadioDirectory? directory;
  final PodcastService? podcasts;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Radios et podcasts'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.radio_rounded), text: 'Radios'),
              Tab(icon: Icon(Icons.podcasts_rounded), text: 'Podcasts'),
            ],
          ),
        ),
        bottomNavigationBar: const SafeArea(child: MiniPlayer()),
        body: TabBarView(
          children: [
            _RadioTab(directory: directory ?? RadioDirectory()),
            _PodcastTab(service: podcasts ?? PodcastService()),
          ],
        ),
      ),
    );
  }
}

String _error(Object e) => e is FormatException
    ? e.message
    : 'Impossible de joindre le service : vérifiez votre connexion Internet';

class _RadioTab extends StatefulWidget {
  const _RadioTab({required this.directory});
  final RadioDirectory directory;

  @override
  State<_RadioTab> createState() => _RadioTabState();
}

class _RadioTabState extends State<_RadioTab> {
  final _query = TextEditingController();
  String? _country = 'FR';
  List<RadioStation>? _results;
  bool _loading = false;
  String? _error_;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error_ = null;
    });
    try {
      final r = await widget.directory.search(
        name: _query.text,
        countryCode: _country,
      );
      if (mounted) setState(() => _results = r);
    } on Object catch (e) {
      if (mounted) setState(() => _error_ = _error(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = OnlineLibrary(context.watch<AppSettings>());
    final music = context.read<MusicController>();
    final favorites = library.favoriteStations;
    final current = context.select<MusicController, String?>(
      (m) => m.current?.uri,
    );

    Widget tile(RadioStation s) => ListTile(
      leading: _Logo(s.logo, Icons.radio_rounded),
      title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (s.country.isNotEmpty) s.country,
          if (s.codec.isNotEmpty) s.codec,
          if (s.bitrate > 0) '${s.bitrate} kb/s',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      selected: current == s.url,
      trailing: IconButton(
        tooltip: library.isFavorite(s)
            ? 'Retirer des favoris'
            : 'Ajouter aux favoris',
        icon: Icon(
          library.isFavorite(s)
              ? Icons.star_rounded
              : Icons.star_border_rounded,
        ),
        onPressed: () => library.toggleFavorite(s),
      ),
      onTap: () => playStation(music, s),
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Rechercher une radio',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Rechercher',
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: _search,
              ),
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final (label, code) in _countries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    showCheckmark: false,
                    label: Text(label),
                    selected: _country == code,
                    onSelected: (_) {
                      setState(() => _country = code);
                      _search();
                    },
                  ),
                ),
            ],
          ),
        ),
        if (favorites.isNotEmpty) ...[
          const _Heading('Mes radios'),
          for (final s in favorites) tile(s),
        ],
        _Heading(
          _query.text.trim().isEmpty ? 'Les plus écoutées' : 'Résultats',
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error_ != null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(_error_!, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _search,
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          )
        else if (_results != null && _results!.isEmpty && !_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Aucune radio trouvée')),
          ),
        for (final s in _results ?? const <RadioStation>[]) tile(s),
      ],
    );
  }
}

class _PodcastTab extends StatefulWidget {
  const _PodcastTab({required this.service});
  final PodcastService service;

  @override
  State<_PodcastTab> createState() => _PodcastTabState();
}

class _PodcastTabState extends State<_PodcastTab> {
  final _query = TextEditingController();
  List<Podcast>? _results;
  bool _loading = false;
  String? _error_;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.length < 2) return;
    setState(() {
      _loading = true;
      _error_ = null;
    });
    try {
      final r = await widget.service.search(q);
      if (mounted) setState(() => _results = r);
    } on Object catch (e) {
      if (mounted) setState(() => _error_ = _error(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(Podcast pod) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PodcastPage(podcast: pod, service: widget.service),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final library = OnlineLibrary(context.watch<AppSettings>());
    final subs = library.subscriptions;
    Widget tile(Podcast pod) => ListTile(
      leading: _Logo(pod.art, Icons.podcasts_rounded),
      title: Text(pod.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: pod.author.isEmpty
          ? null
          : Text(pod.author, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: library.isSubscribed(pod)
          ? const Icon(Icons.check_circle, size: 20)
          : null,
      onTap: () => _open(pod),
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _query,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Rechercher un podcast',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: 'Rechercher',
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: _search,
              ),
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error_ != null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error_!, textAlign: TextAlign.center),
          ),
        if (_results != null) ...[
          const _Heading('Résultats'),
          if (_results!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Aucun podcast trouvé')),
            ),
          for (final pod in _results!) tile(pod),
        ],
        const _Heading('Mes podcasts'),
        if (subs.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Recherchez un podcast puis touchez « S\'abonner » pour le retrouver ici, même sans connexion pour les épisodes téléchargés.',
              textAlign: TextAlign.center,
            ),
          ),
        for (final pod in subs) tile(pod),
      ],
    );
  }
}

/// Episodes of one podcast.
class PodcastPage extends StatefulWidget {
  const PodcastPage({super.key, required this.podcast, required this.service});
  final Podcast podcast;
  final PodcastService service;

  @override
  State<PodcastPage> createState() => _PodcastPageState();
}

class _PodcastPageState extends State<PodcastPage> {
  Feed? _feed;
  String? _error_;
  final _progress = <String, double>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error_ = null);
    try {
      final feed = await widget.service.feed(widget.podcast.feed);
      if (mounted) setState(() => _feed = feed);
    } on Object catch (e) {
      if (mounted) setState(() => _error_ = _error(e));
    }
  }

  Future<void> _download(OnlineLibrary library, Episode e) async {
    setState(() => _progress[e.guid] = 0);
    try {
      await library.download(
        e,
        onProgress: (f) {
          if (mounted) setState(() => _progress[e.guid] = f);
        },
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Téléchargement impossible')),
        );
      }
    } finally {
      if (mounted) setState(() => _progress.remove(e.guid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = OnlineLibrary(context.watch<AppSettings>());
    final music = context.read<MusicController>();
    final scheme = Theme.of(context).colorScheme;
    final pod = widget.podcast;
    final feed = _feed;
    return Scaffold(
      appBar: AppBar(
        title: Text(pod.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: () => library.toggleSubscription(pod),
            child: Text(library.isSubscribed(pod) ? 'Abonné' : "S'abonner"),
          ),
        ],
      ),
      bottomNavigationBar: const SafeArea(child: MiniPlayer()),
      body: _error_ != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error_!, textAlign: TextAlign.center),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            )
          : feed == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 16),
              children: [
                for (final e in feed.episodes.take(150))
                  () {
                    final local = library.downloadedPath(e);
                    final played = library.isPlayed(e);
                    final busy = _progress[e.guid];
                    return ListTile(
                      title: Text(
                        e.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: played
                              ? FontWeight.w400
                              : FontWeight.w700,
                          color: played ? scheme.onSurfaceVariant : null,
                        ),
                      ),
                      subtitle: Text(
                        [
                          if (e.published != null)
                            dayLabel(e.published!.toLocal()),
                          if (e.duration > Duration.zero)
                            formatDuration(e.duration),
                          if (local != null) 'Téléchargé',
                        ].join(' · '),
                      ),
                      leading: busy != null
                          ? SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(
                                value: busy > 0 ? busy : null,
                              ),
                            )
                          : Icon(
                              played
                                  ? Icons.check_circle_outline
                                  : Icons.play_circle_outline,
                            ),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Options',
                        onSelected: (v) async {
                          switch (v) {
                            case 'download':
                              await _download(library, e);
                            case 'remove':
                              await library.deleteDownload(e);
                              if (mounted) setState(() {});
                            case 'played':
                              library.setPlayed(e, !played);
                          }
                        },
                        itemBuilder: (_) => [
                          if (local == null && busy == null)
                            const PopupMenuItem(
                              value: 'download',
                              child: Text('Télécharger'),
                            ),
                          if (local != null)
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('Supprimer le téléchargement'),
                            ),
                          PopupMenuItem(
                            value: 'played',
                            child: Text(
                              played
                                  ? 'Marquer comme non écouté'
                                  : 'Marquer comme écouté',
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        library.setPlayed(e, true);
                        playEpisode(music, pod, e, localPath: local);
                      },
                    );
                  }(),
              ],
            ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    ),
  );
}

/// A logo from the Internet, or an icon when there is none or it fails.
class _Logo extends StatelessWidget {
  const _Logo(this.url, this.fallback);
  final String url;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = CircleAvatar(
      backgroundColor: scheme.secondaryContainer,
      child: Icon(fallback, color: scheme.onSecondaryContainer),
    );
    if (!url.startsWith('http')) return icon;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        cacheWidth: 120,
        errorBuilder: (_, _, _) => icon,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : SizedBox(width: 44, height: 44, child: icon),
      ),
    );
  }
}
