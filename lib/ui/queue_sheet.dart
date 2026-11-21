import 'package:material_ui/material_ui.dart';

import '../core/automix_engine.dart';
import '../core/player_api.dart';
import '../core/player_controller.dart';
import '../core/playlist_store.dart';
import '../theme.dart';

/// Cola de reproducción: reordenar arrastrando, quitar deslizando, saltar
/// tocando y el interruptor de «cola protegida».
///
/// Escucha al controlador por su cuenta (`AnimatedBuilder`), así que se puede
/// dejar abierta mientras suena la música: cada cambio del motor repinta la
/// lista sin que la hoja tenga que reconstruirse desde fuera.
class QueueSheet extends StatefulWidget {
  const QueueSheet({
    super.key,
    required this.controller,
    this.queues,
    this.automix,
  });

  final PlayerController controller;

  /// Cinco colas guardadas. Si falta, la hoja crea la suya (en producción la
  /// comparte con el resto de la app; en pruebas se inyecta).
  final MultiQueueStore? queues;

  /// Motor de mezcla automática. Igual: inyectable.
  final AutomixEngine? automix;

  /// Abre la hoja desde abajo, ocupando como mucho el 78 % de la pantalla.
  static Future<void> show(
    BuildContext context,
    PlayerController controller, {
    MultiQueueStore? queues,
    AutomixEngine? automix,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: chSurface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.78,
        child: QueueSheet(controller: controller, queues: queues, automix: automix),
      ),
    );
  }

  @override
  State<QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<QueueSheet> {
  late final MultiQueueStore _queues = widget.queues ?? MultiQueueStore.memory();

  late final AutomixEngine _automix = widget.automix ??
      AutomixEngine(controller: widget.controller, enabled: false);

  bool _ownsAutomix = false;

  PlayerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _ownsAutomix = widget.automix == null;
    _controller.addListener(_captureCurrent);
    if (widget.queues == null) _queues.load();
    _automix.start();
  }

  @override
  void dispose() {
    _controller.removeListener(_captureCurrent);
    if (_ownsAutomix) _automix.dispose();
    if (widget.queues == null) _queues.dispose();
    super.dispose();
  }

  /// Guarda lo que hay en el motor en la cola activa (sin avisar a la UI: los
  /// cambios de cola no deben repintar la hoja en mitad de un gesto).
  void _captureCurrent() {
    final snapshot = _controller.snapshot;
    _queues.capture(
      _queues.active,
      <String>[for (final item in snapshot.queue) item.path],
      snapshot.queueIndex,
    );
  }

  /// Cambia de cola: guarda la actual y carga la elegida en el motor.
  Future<void> _switchTo(int slot) async {
    if (slot == _queues.active) return;
    _captureCurrent();
    _queues.setActive(slot);
    final target = _queues.activeSlot;
    _controller.queueProtected = true;
    _controller.clearQueue();
    for (final path in target.paths) {
      _controller.enqueue(path);
    }
    if (target.paths.isNotEmpty) {
      final index = target.index.clamp(0, target.paths.length - 1);
      if (!_controller.playAt(index)) {
        await _controller.openFile(target.paths[index]);
      }
    }
    if (mounted) {
      setState(() {
        _message = target.isEmpty
            ? 'Cola ${slot + 1} vacía y lista para llenar.'
            : 'Cola «${target.label}» cargada (${target.length} pistas).';
      });
    }
  }

  String? _message;

  Future<void> _confirmClear() async {
    final count = _controller.snapshot.queue.length;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: chSurface,
        title: const Text('¿Vaciar la cola?'),
        content: Text(
          count == 1
              ? 'Se quitará la única pista de la cola.'
              : 'Se quitarán las $count pistas de la cola.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Vaciar'),
          ),
        ],
      ),
    );
    if (confirmed == true) _controller.clearQueue();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final snapshot = _controller.snapshot;
        final queue = snapshot.queue;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(snapshot),
              const SizedBox(height: 6),
              _slotBar(),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _message!,
                    style: const TextStyle(fontSize: 11, color: chAccent),
                  ),
                ),
              const SizedBox(height: 6),
              Expanded(
                child: queue.isEmpty ? _empty() : _list(queue, snapshot),
              ),
              ..._automixRows(snapshot),
            ],
          ),
        );
      },
    );
  }

  Widget _header(PlayerSnapshot snapshot) {
    final count = snapshot.queue.length;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Cola',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              Text(
                count == 0
                    ? 'Sin pistas'
                    : '$count ${count == 1 ? 'pista' : 'pistas'} · '
                        'arrastra para ordenar, desliza para quitar',
                style: const TextStyle(fontSize: 12, color: chMuted),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: count == 0 ? null : _confirmClear,
          tooltip: 'Vaciar la cola',
          icon: const Icon(Icons.delete_sweep_rounded),
        ),
      ],
    );
  }

  Widget _empty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.queue_music_rounded, size: 42, color: chMuted),
          const SizedBox(height: 10),
          const Text('La cola está vacía', style: TextStyle(color: chMuted)),
          const SizedBox(height: 4),
          Text(
            _controller.queueProtected
                ? 'Abre un archivo y se añadirá al final.'
                : 'Abre un archivo para empezar a llenarla.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: chMuted),
          ),
        ],
      ),
    );
  }

  Widget _list(List<QueueItem> queue, PlayerSnapshot snapshot) {
    return Column(
      children: [
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: true,
            itemCount: queue.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) newIndex -= 1;
              _controller.moveQueueItem(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final item = queue[index];
              final active = index == snapshot.queueIndex;
              return Dismissible(
                key: ValueKey<String>('queue-$index-${item.path}'),
                direction: DismissDirection.endToStart,
                background: const _RemoveBackground(),
                onDismissed: (_) => _controller.removeQueueItem(index),
                child: _QueueTile(
                  item: item,
                  index: index,
                  active: active,
                  onTap: active ? null : () => _controller.playAt(index),
                ),
              );
            },
          ),
        ),
        const Divider(height: 20),
        _protectedSwitch(),
      ],
    );
  }

  /// Cinco colas: la activa se marca; tocar otra la trae al motor.
  Widget _slotBar() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: MultiQueueStore.slotCount,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final slot = _queues.slots[index];
          final active = index == _queues.active;
          return ChoiceChip(
            label: Text(
              '${index + 1} · ${slot.length}',
              style: TextStyle(
                fontSize: 11,
                color: active ? chOnAccent : chMuted,
              ),
            ),
            tooltip: slot.label,
            selected: active,
            selectedColor: chAccent,
            backgroundColor: chSurfaceHigh,
            side: BorderSide(color: active ? chAccent : chBorder),
            onSelected: (_) => _switchTo(index),
          );
        },
      ),
    );
  }

  /// Automix y aviso de cómo se comporta.
  List<Widget> _automixRows(PlayerSnapshot snapshot) {
    return <Widget>[
      const Divider(height: 16),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        dense: true,
        value: _automix.enabled,
        onChanged: (value) {
          _automix.setEnabled(value);
          setState(() {});
        },
        title: const Text('Automix DJ', style: TextStyle(fontSize: 14)),
        subtitle: Text(
          _automix.enabled
              ? '${_automix.status} · ${automixLabel(_automix.phase)}'
              : automixHint(snapshot),
          style: const TextStyle(fontSize: 11, color: chMuted),
        ),
      ),
    ];
  }

  Widget _protectedSwitch() {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: _controller.queueProtected,
      onChanged: (value) => _controller.queueProtected = value,
      title: const Text('Cola protegida', style: TextStyle(fontSize: 14)),
      subtitle: const Text(
        'Abrir un archivo lo añade al final en vez de vaciar la cola.',
        style: TextStyle(fontSize: 12, color: chMuted),
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.item,
    required this.index,
    required this.active,
    required this.onTap,
  });

  final QueueItem item;
  final int index;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Del núcleo solo se conoce el artista de la pista que suena; para el
    // resto, la carpeta dice más que una línea vacía.
    final subtitle =
        item.artist.isNotEmpty ? item.artist : _parentOf(item.path);
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: SizedBox(
        width: 34,
        child: Center(
          child: active
              ? const Icon(Icons.graphic_eq_rounded, size: 20, color: chAccent)
              : Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 12, color: chMuted),
                ),
        ),
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 14,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active ? chAccent : chForeground,
        ),
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: chMuted),
            ),
    );
  }

  static String _parentOf(String path) {
    final cut = path.lastIndexOf(RegExp(r'[/\\]'));
    return cut <= 0 ? '' : path.substring(0, cut);
  }
}

class _RemoveBackground extends StatelessWidget {
  const _RemoveBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0x33FF5370),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF5370)),
    );
  }
}
