import 'package:material_ui/material_ui.dart';

import '../core/player_controller.dart';
import '../theme.dart';

/// Hoja con la cola de reproducción: qué suena y en qué orden.
///
/// El motor expone cada ruta con `ch_engine_queue_item`; tocar una pista salta
/// a ella sin vaciar la cola.
class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key, required this.controller});

  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.6;
    return SizedBox(
      height: height,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final count = controller.queueCount;
          final current = controller.queueIndex;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
                child: Row(
                  children: [
                    Text('Cola', style: chDisplay.copyWith(fontSize: 20)),
                    const SizedBox(width: 10),
                    if (count > 0)
                      Text(
                        '$count pistas',
                        style: const TextStyle(color: chMuted, fontSize: 12),
                      ),
                    const Spacer(),
                    IconButton(
                      onPressed: count == 0 ? null : controller.queueClear,
                      tooltip: 'Vaciar la cola',
                      icon: const Icon(Icons.delete_sweep_rounded),
                    ),
                  ],
                ),
              ),
              if (count == 0)
                const Expanded(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'La cola está vacía.\nAbre un audio para empezar.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: chMuted, height: 1.6),
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    itemCount: count,
                    itemBuilder: (context, index) {
                      final path = controller.queueItem(index);
                      final playing = index == current;
                      return ListTile(
                        selected: playing,
                        selectedTileColor: chAccent.withValues(alpha: 0.08),
                        leading: playing
                            ? const Icon(Icons.graphic_eq_rounded,
                                color: chAccent)
                            : Text(
                                '${index + 1}',
                                style: const TextStyle(color: chMuted),
                              ),
                        title: Text(
                          _fileName(path),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: playing ? chAccent : chForeground,
                            fontWeight:
                                playing ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                        subtitle: Text(
                          path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              const TextStyle(color: chMuted, fontSize: 11),
                        ),
                        onTap: () {
                          controller.playIndex(index);
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String _fileName(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}
