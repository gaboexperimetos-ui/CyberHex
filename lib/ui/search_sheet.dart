import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/library_search.dart';
import '../core/player_controller.dart';
import '../core/stats_store.dart';
import '../theme.dart';
import 'kit/ch_kit.dart';

/// Búsqueda global: biblioteca escaneada e historial en una sola lista, con
/// reproducción directa al tocar un resultado.
///
/// Escucha al controlador y a las estadísticas por su cuenta, así que si la
/// biblioteca termina de escanearse con la hoja abierta los resultados se
/// actualizan solos. No guarda estado propio más allá del texto escrito.
class SearchSheet extends StatefulWidget {
  const SearchSheet({super.key, required this.controller, required this.stats});

  final PlayerController controller;
  final StatsStore stats;

  /// Abre la hoja desde abajo, ocupando como mucho el 86 % de la pantalla.
  static Future<void> show(
    BuildContext context, {
    required PlayerController controller,
    required StatsStore stats,
  }) {
    final palette = paletteOf(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(ChRadius.lg)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.86,
          child: SearchSheet(controller: controller, stats: stats),
        ),
      ),
    );
  }

  @override
  State<SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<SearchSheet> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = paletteOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        widget.controller,
        widget.stats,
      ]),
      builder: (context, _) {
        final hits = searchHits(
          query: _query.text,
          library: widget.controller.libraryTracks,
          history: widget.stats.history,
        );
        final emptyLibrary =
            widget.controller.libraryTracks.isEmpty &&
            widget.stats.history.isEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                ChSpace.lg,
                0,
                ChSpace.lg,
                ChSpace.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ChHexBadge(
                        icon: Icons.manage_search_rounded,
                        palette: palette,
                        size: 38,
                      ),
                      const SizedBox(width: ChSpace.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Buscar', style: chTitle(palette, size: 16.5)),
                            const SizedBox(height: 1),
                            Text(
                              emptyLibrary
                                  ? 'Tu biblioteca e historial'
                                  : '${hits.length} '
                                        '${hits.length == 1 ? 'resultado' : 'resultados'}',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: hits.isEmpty && !emptyLibrary
                                    ? palette.muted
                                    : palette.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ChSpace.md),
                  TextField(
                    controller: _query,
                    focusNode: _focus,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (hits.isNotEmpty) unawaited(_play(hits.first.path));
                    },
                    decoration: InputDecoration(
                      hintText: 'Busca en tu biblioteca e historial',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _query.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar',
                              icon: const Icon(Icons.close_rounded, size: 18),
                              onPressed: () {
                                _query.clear();
                                setState(() {});
                                _focus.requestFocus();
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: emptyLibrary
                  ? ChEmptyState(
                      palette: palette,
                      icon: Icons.manage_search_rounded,
                      title: 'Nada que buscar todavía',
                      message:
                          'Escanea una carpeta en la Biblioteca y aquí podrás '
                          'encontrar cualquier pista al instante.',
                    )
                  : hits.isEmpty
                  ? ChEmptyState(
                      palette: palette,
                      icon: Icons.search_off_rounded,
                      title: 'Sin resultados',
                      message: 'Ninguna pista coincide con «${_query.text}».',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        ChSpace.md,
                        0,
                        ChSpace.md,
                        ChSpace.lg,
                      ),
                      itemCount: hits.length,
                      separatorBuilder: (_, _) =>
                          ChHairline(palette: palette, indent: 58),
                      itemBuilder: (context, index) => _HitTile(
                        hit: hits[index],
                        palette: palette,
                        onTap: () => unawaited(_play(hits[index].path)),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _play(String path) async {
    chHaptic();
    final error = await widget.controller.openFile(path);
    if (!mounted) return;
    if (error == null) {
      Navigator.of(context).pop();
      return;
    }
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('No se pudo reproducir: $error')));
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({
    required this.hit,
    required this.palette,
    required this.onTap,
  });

  final SearchHit hit;
  final CyberHexPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChPressable(
      onTap: onTap,
      radius: ChRadius.md,
      semanticLabel: 'Reproducir ${hit.title}',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ChSpace.xs,
          vertical: ChSpace.sm + 1,
        ),
        child: Row(
          children: [
            ChCoverThumb(seed: hit.seed, palette: palette, size: 42, hex: true),
            const SizedBox(width: ChSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: chTitle(palette, size: 13.5),
                  ),
                  if (hit.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      hit.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: palette.muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: ChSpace.sm),
            Icon(
              hit.recent ? Icons.history_rounded : Icons.play_arrow_rounded,
              size: 20,
              color: hit.recent ? palette.muted : palette.accent,
            ),
          ],
        ),
      ),
    );
  }
}
