import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/settings/app_settings.dart';
import '../../../player/presentation/providers/player_provider.dart';
import '../../../player/presentation/services/audio_output_service.dart';
import 'hidden_songs_screen.dart';

class _ProfileAvatar extends StatefulWidget {
  const _ProfileAvatar({
    required this.imagePath,
    required this.color,
    required this.onTap,
  });

  final String? imagePath;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<_ProfileAvatar> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final file = widget.imagePath == null ? null : File(widget.imagePath!);
    final hasImage = file != null && file.existsSync();
    return Semantics(
      button: true,
      label: 'Cambiar foto de perfil',
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: ClipOval(
            child: SizedBox(
              width: 56,
              height: 56,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircleAvatar(
                    backgroundColor: widget.color,
                    backgroundImage: hasImage ? FileImage(file) : null,
                    child: hasImage
                        ? null
                        : const Icon(Icons.person_rounded,
                            color: Colors.white, size: 28),
                  ),
                  AnimatedOpacity(
                    opacity: _isHovered ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: const ColoredBox(
                      color: Colors.black54,
                      child: Center(
                        child: Icon(Icons.edit_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _openAudioOutput(BuildContext context) async {
    final opened = await AudioOutputService.openSystemOutputSettings();
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo abrir el selector de audio.')),
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final currentName = ref.read(appSettingsProvider).displayName ?? '';
    final controller = TextEditingController(text: currentName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar nombre'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Tu nombre'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(appSettingsProvider.notifier).setDisplayName(name);
    }
    // El diálogo todavía se está animando al cerrarse; desechar el
    // controlador en el siguiente ciclo evita dependientes activos de Flutter.
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
  }

  Future<void> _pickProfileImage(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      dialogTitle: 'Selecciona tu foto de perfil',
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    final directory = Directory(
        p.join((await getApplicationDocumentsDirectory()).path, 'profile'));
    await directory.create(recursive: true);
    final extension =
        p.extension(picked.name).isEmpty ? '.jpg' : p.extension(picked.name);
    final target = File(p.join(directory.path,
        'profile-${DateTime.now().microsecondsSinceEpoch}$extension'));
    if (picked.path != null) {
      await File(picked.path!).copy(target.path);
    } else if (picked.bytes != null) {
      await target.writeAsBytes(picked.bytes!);
    } else {
      return;
    }
    final previousPath = ref.read(appSettingsProvider).profileImagePath;
    await ref
        .read(appSettingsProvider.notifier)
        .setProfileImagePath(target.path);
    if (previousPath != null && previousPath != target.path) {
      final previousFile = File(previousPath);
      if (await previousFile.exists()) await previousFile.delete();
    }
  }

  Future<void> _pickBackgroundImage(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      dialogTitle: 'Selecciona una imagen de fondo',
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final directory = Directory(
        p.join((await getApplicationDocumentsDirectory()).path, 'backgrounds'));
    await directory.create(recursive: true);
    final extension =
        p.extension(picked.name).isEmpty ? '.jpg' : p.extension(picked.name);
    final target = File(p.join(directory.path,
        'background-${DateTime.now().microsecondsSinceEpoch}$extension'));
    if (picked.path != null) {
      await File(picked.path!).copy(target.path);
    } else if (picked.bytes != null) {
      await target.writeAsBytes(picked.bytes!);
    } else {
      return;
    }
    final previousPath = ref.read(appSettingsProvider).backgroundImagePath;
    await ref
        .read(appSettingsProvider.notifier)
        .setBackgroundImagePath(target.path);
    if (previousPath != null && previousPath != target.path) {
      final previousFile = File(previousPath);
      if (await previousFile.exists()) await previousFile.delete();
    }
  }

  Future<void> _clearBackgroundImage(WidgetRef ref) async {
    final previousPath = ref.read(appSettingsProvider).backgroundImagePath;
    await ref.read(appSettingsProvider.notifier).clearBackgroundImage();
    if (previousPath != null) {
      final previousFile = File(previousPath);
      if (await previousFile.exists()) await previousFile.delete();
    }
  }

  Future<void> _pickCustomColor(BuildContext context, WidgetRef ref) async {
    final initialColor = ref.read(appSettingsProvider).activeColor;
    final color = await showDialog<Color>(
      context: context,
      builder: (_) => _CustomColorDialog(initialColor: initialColor),
    );
    if (color != null) {
      await ref.read(appSettingsProvider.notifier).setCustomAccent(color);
    }
  }

  Future<void> _setSleepTimer(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final minutes = await showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Temporizador para dormir'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('La música se pausará cuando termine el tiempo.'),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Minutos',
              hintText: 'Ej. 30',
              suffixText: 'min',
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 0),
            child: const Text('Desactivar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Iniciar'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
    if (minutes == null) return;
    ref.read(playerProvider.notifier).setSleepTimer(
          minutes <= 0 ? null : Duration(minutes: minutes),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final timer =
        ref.watch(playerProvider.select((state) => state.sleepTimerRemaining));
    final name = settings.displayName ?? 'Aún no definido';

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Perfil', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: _ProfileAvatar(
                imagePath: settings.profileImagePath,
                color: colorScheme.primary,
                onTap: () => _pickProfileImage(context, ref),
              ),
              title: const Text('Nombre'),
              subtitle: Text(name),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editName(context, ref),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Músicas ocultas'),
              subtitle: const Text('Mostrar o borrar canciones ocultas'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HiddenSongsScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Reproducción', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.bedtime_rounded, color: colorScheme.primary),
              title: const Text('Temporizador para dormir'),
              subtitle: Text(timer == null
                  ? 'Pausa la música después de un tiempo'
                  : 'Se pausará en ${timer.inMinutes}:${(timer.inSeconds % 60).toString().padLeft(2, '0')}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _setSleepTimer(context, ref),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(Icons.speaker_rounded, color: colorScheme.primary),
              title: const Text('Dispositivo de salida'),
              subtitle:
                  const Text('Elegir parlante, auriculares o salida Bluetooth'),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () => _openAudioOutput(context),
            ),
          ),
          const SizedBox(height: 32),
          Text('Tema', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('Elige el color principal de MuShare.'),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              secondary: Icon(
                settings.isDarkMode
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                color: colorScheme.primary,
              ),
              title: const Text('Modo oscuro'),
              subtitle: Text(
                  settings.isDarkMode ? 'Interfaz oscura' : 'Interfaz clara'),
              value: settings.isDarkMode,
              onChanged: (value) =>
                  ref.read(appSettingsProvider.notifier).setDarkMode(value),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.wallpaper_rounded),
              title: const Text('Imagen de fondo'),
              subtitle: Text(settings.backgroundImagePath == null
                  ? 'Fondo oscuro predeterminado'
                  : 'Imagen aplicada con una capa oscura'),
              trailing: settings.backgroundImagePath == null
                  ? const Icon(Icons.add_photo_alternate_outlined)
                  : IconButton(
                      tooltip: 'Quitar imagen de fondo',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => _clearBackgroundImage(ref),
                    ),
              onTap: () => _pickBackgroundImage(context, ref),
            ),
          ),
          const SizedBox(height: 8),
          if (settings.backgroundImagePath != null)
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.palette_outlined),
                title: const Text('Colores según la imagen'),
                subtitle:
                    const Text('Ajusta el color principal usando el fondo'),
                value: settings.adaptAccentToBackground,
                onChanged: (value) => ref
                    .read(appSettingsProvider.notifier)
                    .setAdaptAccentToBackground(value),
              ),
            ),
          if (settings.backgroundImagePath != null) const SizedBox(height: 8),
          ...AppAccent.values.where((accent) => accent != AppAccent.custom).map(
                (accent) => Card(
                  child: RadioListTile<AppAccent>(
                    value: accent,
                    groupValue: settings.accent,
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(appSettingsProvider.notifier).setAccent(value);
                      }
                    },
                    activeColor: accent.color,
                    title: Text(accent.label),
                    secondary: CircleAvatar(backgroundColor: accent.color),
                  ),
                ),
              ),
          Card(
            child: ListTile(
              leading: CircleAvatar(backgroundColor: settings.activeColor),
              title: const Text('Color personalizado'),
              subtitle:
                  const Text('Elige cualquier color en la rueda cromática'),
              trailing: const Icon(Icons.colorize_rounded),
              onTap: () => _pickCustomColor(context, ref),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomColorDialog extends StatefulWidget {
  const _CustomColorDialog({required this.initialColor});
  final Color initialColor;

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late HSVColor _color = HSVColor.fromColor(widget.initialColor);

  void _select(Offset position, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final angle = math.atan2(position.dy - center.dy, position.dx - center.dx);
    final hue = (angle * 180 / math.pi + 360) % 360;
    setState(() => _color = _color.withHue(hue));
  }

  @override
  Widget build(BuildContext context) {
    const wheelSize = 220.0;
    final selectedColor = _color.toColor();
    return AlertDialog(
      title: const Text('Color personalizado'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onPanDown: (details) =>
                _select(details.localPosition, const Size.square(wheelSize)),
            onPanUpdate: (details) =>
                _select(details.localPosition, const Size.square(wheelSize)),
            child: CustomPaint(
              size: const Size.square(wheelSize),
              painter: _HueWheelPainter(
                hue: _color.hue,
                centerColor: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: selectedColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                  '#${selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}'),
            ],
          ),
          const SizedBox(height: 12),
          _ColorSlider(
            label: 'Saturación',
            value: _color.saturation,
            valueLabel: '${(_color.saturation * 100).round()}%',
            onChanged: (value) =>
                setState(() => _color = _color.withSaturation(value)),
          ),
          _ColorSlider(
            label: 'Luminosidad',
            value: _color.value,
            valueLabel: '${(_color.value * 100).round()}%',
            onChanged: (value) =>
                setState(() => _color = _color.withValue(value)),
          ),
          const SizedBox(height: 2),
          Text(
            'La rueda cambia el tono. Ajusta los controles para hacerlo más suave, intenso, claro u oscuro.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(context, selectedColor),
            child: const Text('Usar color')),
      ],
    );
  }
}

class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.valueLabel,
    required this.onChanged,
  });

  final String label;
  final double value;
  final String valueLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [Text(label), const Spacer(), Text(valueLabel)],
        ),
        Slider(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _HueWheelPainter extends CustomPainter {
  const _HueWheelPainter({required this.hue, required this.centerColor});
  final double hue;
  final Color centerColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..shader = SweepGradient(
        colors: List.generate(13,
            (index) => HSVColor.fromAHSV(1, index * 30, .82, .95).toColor()),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius * .53, Paint()..color = centerColor);
    final radians = hue * math.pi / 180;
    final marker =
        center + Offset(math.cos(radians), math.sin(radians)) * radius * .76;
    canvas.drawCircle(marker, 9, Paint()..color = Colors.white);
    canvas.drawCircle(marker, 5,
        Paint()..color = HSVColor.fromAHSV(1, hue, .82, .95).toColor());
  }

  @override
  bool shouldRepaint(covariant _HueWheelPainter oldDelegate) =>
      oldDelegate.hue != hue || oldDelegate.centerColor != centerColor;
}
