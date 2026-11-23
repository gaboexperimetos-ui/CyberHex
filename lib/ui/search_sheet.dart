import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/library_search.dart';
import '../core/player_controller.dart';
import '../core/stats_store.dart';
import '../theme.dart';
import 'hex_cover.dart';

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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
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
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _query.clear();
                            setState(() {});
                            _focus.requestFocus();
                          },
                        ),
                  filled: true,
                  fillColor: palette.surfaceHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                ),
              ),
            ),
            Expanded(
              child: emptyLibrary
                  ? _Empty(
                      palette: palette,
                      title: 'Nada que buscar todavía',
                      message:
                          'Escanea una carpeta en la Biblioteca y aquí podrás '
                          'encontrar cualquier pista al instante.',
                    )
                  : hits.isEmpty
                  ? _Empty(
                      palette: palette,
                      title: 'Sin resultados',
                      message: 'Ninguna pista coincide con «${_query.text}».',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: hits.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: palette.border.withValues(alpha: 0.45),
                      ),
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
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      leading: HexCover(seed: hit.seed, palette: palette, size: 42),
      title: Text(
        hit.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: palette.foreground),
      ),
      subtitle: hit.subtitle.isEmpty
          ? null
          : Text(
              hit.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.muted),
            ),
      trailing: Icon(
        hit.recent ? Icons.history_rounded : Icons.play_arrow_rounded,
        color: palette.muted,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.palette,
    required this.title,
    required this.message,
  });

  final CyberHexPalette palette;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.manage_search_rounded, size: 44, color: palette.muted),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: palette.foreground,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted),
            ),
          ],
        ),
      ),
    );
  }
}
