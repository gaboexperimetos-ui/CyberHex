import 'package:material_ui/material_ui.dart';

import '../core/stats_store.dart';
import '../theme.dart';
import 'kit/ch_kit.dart';

/// Estadísticas de escucha: totales, top de pistas y artistas, franja horaria e
/// historial.
///
/// Todo sale de [StatsStore]; esta pantalla no mide nada por su cuenta.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.stats});

  final StatsStore stats;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  @override
  void initState() {
    super.initState();
    widget.stats.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.stats.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: paletteOf(context).surface,
        title: const Text('¿Borrar las estadísticas?'),
        content: const Text(
          'Se pierden el historial, los totales y la franja horaria. '
          'No se toca ningún archivo de música.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.stats.clear();
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final stats = widget.stats;
    final top = stats.topTracks(8);
    final artists = stats.topArtists(6);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Estadísticas'),
        actions: [
          IconButton(
            tooltip: 'Borrar estadísticas',
            onPressed: stats.totalPlays == 0 ? null : _confirmClear,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
      body: ChContent(
        maxWidth: 980,
        child: stats.totalPlays == 0
            ? ChEmptyState(
                icon: Icons.insights_rounded,
                title: 'Aún no hay datos',
                message:
                    'Todavía no hay nada que contar.\nDale al play y vuelve por '
                    'aquí.',
                palette: palette,
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _Figure(
                          value: '${stats.totalPlays}',
                          label: 'reproducciones',
                          icon: Icons.play_circle_outline_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Figure(
                          value: _minutes(stats.totalMinutes),
                          label: 'escuchados',
                          icon: Icons.timer_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _Figure(
                          value: '${stats.tracks.length}',
                          label: stats.tracks.length == 1
                              ? 'pista distinta'
                              : 'pistas distintas',
                          icon: Icons.library_music_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Figure(
                          value: stats.favoriteHour < 0
                              ? '—'
                              : '${stats.favoriteHour.toString().padLeft(2, '0')}:00',
                          label: stats.favoriteSlot,
                          icon: Icons.schedule_rounded,
                        ),
                      ),
                    ],
                  ),
                  const _Title('Por hora del día'),
                  _HourChart(hours: stats.byHour, peak: stats.favoriteHour),
                  const _Title('Más escuchadas'),
                  if (top.isEmpty)
                    Text('—', style: chMono(palette, size: 12))
                  else
                    for (var i = 0; i < top.length; i++)
                      _RankRow(
                        position: i + 1,
                        title: top[i].label,
                        subtitle: top[i].artist.isEmpty
                            ? '${top[i].plays}× · ${top[i].minutes} min'
                            : '${top[i].artist} · ${top[i].plays}× · ${top[i].minutes} min',
                      ),
                  const _Title('Artistas'),
                  if (artists.isEmpty)
                    Text('—', style: chMono(palette, size: 12))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final artist in artists)
                          Chip(
                            backgroundColor: palette.surfaceHigh,
                            side: BorderSide(color: palette.border),
                            label: Text(
                              '${artist.key} · ${artist.value}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  const _Title('Historial reciente'),
                  if (stats.history.isEmpty)
                    Text('—', style: chMono(palette, size: 12))
                  else
                    for (final entry in stats.history.take(12))
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            ChCoverThumb(
                              seed: entry.label,
                              palette: palette,
                              size: 36,
                              hex: true,
                            ),
                            const SizedBox(width: ChSpace.sm + 2),
                            Text(
                              entry.clock,
                              style: chMono(palette, size: 10.5),
                            ),
                          ],
                        ),
                        title: Text(
                          entry.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: chTitle(palette, size: 13.5),
                        ),
                        subtitle: entry.artist.isEmpty
                            ? null
                            : Text(
                                entry.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: palette.muted,
                                ),
                              ),
                      ),
                ],
              ),
      ),
    );
  }

  static String _minutes(double minutes) {
    if (minutes < 60) return '${minutes.round()} min';
    final hours = minutes / 60;
    return '${hours.toStringAsFixed(hours < 10 ? 1 : 0)} h';
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
      child: ChSectionHeader(text, palette: paletteOf(context)),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, required this.icon});

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return ChSurface(
      padding: const EdgeInsets.symmetric(
        horizontal: ChSpace.md,
        vertical: ChSpace.md,
      ),
      radius: ChRadius.md,
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: palette.accent),
          const SizedBox(width: ChSpace.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: chTitle(palette, size: 19, weight: FontWeight.w700),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: chEyebrow(palette, size: 9.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 24 barras, una por hora; la favorita en acento.
class _HourChart extends StatelessWidget {
  const _HourChart({required this.hours, required this.peak});

  final Map<int, int> hours;
  final int peak;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    final max = hours.values.fold<int>(
      0,
      (best, value) => value > best ? value : best,
    );
    return SizedBox(
      height: 74,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var hour = 0; hour < 24; hour++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: max == 0
                          ? 2
                          : 2 + 50 * ((hours[hour] ?? 0) / max),
                      decoration: BoxDecoration(
                        color: hour == peak
                            ? palette.accent
                            : palette.accent.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    if (hour % 6 == 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '$hour',
                          style: TextStyle(fontSize: 8, color: palette.muted),
                        ),
                      )
                    else
                      const SizedBox(height: 11),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.position,
    required this.title,
    required this.subtitle,
  });

  final int position;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$position',
              style: chMono(palette, size: 11, color: palette.accent),
            ),
          ),
          ChCoverThumb(seed: title, palette: palette, size: 40, hex: true),
          const SizedBox(width: ChSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: chTitle(palette, size: 13.5),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: palette.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
