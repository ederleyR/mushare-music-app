// lib/features/library/presentation/widgets/song_tile.dart
//
// Widget reutilizable que representa una fila de canción en cualquier
// lista (biblioteca completa, favoritos, resultados de una playlist, etc).
//
// La interfaz pública (song, onTap, onFavoriteTap, isFavorite, isPlaying)
// se mantiene intacta a propósito: este archivo solo cambia el diseño
// visual, no el contrato que usan library_screen.dart y otras pantallas.

import 'dart:io';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/song.dart';

class SongTile extends StatelessWidget {
  final SongEntity song;
  final VoidCallback onTap;
  final VoidCallback? onFavoriteTap;
  final VoidCallback? onAddToPlaylistTap;
  final VoidCallback? onDeleteTap;
  final VoidCallback? onArtworkTap;
  final bool isFavorite;
  final bool isPlaying;
  final bool isSelected;
  final VoidCallback? onLongPress;

  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.onFavoriteTap,
    this.onAddToPlaylistTap,
    this.onDeleteTap,
    this.onArtworkTap,
    this.isFavorite = false,
    this.isPlaying = false,
    this.isSelected = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return InkWell(
      onTap: onTap,
      onLongPress: isMobile
          ? (onLongPress ??
              ((onAddToPlaylistTap != null ||
                      onDeleteTap != null ||
                      onArtworkTap != null)
                  ? () => _showMobileActions(context)
                  : null))
          : onLongPress,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withValues(alpha: 0.18) : null,
          border:
              isSelected ? Border.all(color: primaryColor, width: 1.5) : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _buildArtwork(context),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isPlaying
                            ? primaryColor
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${song.artist} • ${song.formattedDuration}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              if (song.artworkPath == null && onArtworkTap != null)
                IconButton(
                  tooltip: 'Agregar portada',
                  icon: const Icon(Icons.add_photo_alternate_outlined,
                      size: 22, color: AppColors.textSecondary),
                  onPressed: onArtworkTap,
                ),
              if (onFavoriteTap != null)
                IconButton(
                  tooltip:
                      isFavorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
                  icon: Icon(
                    isFavorite
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 22,
                    color: isFavorite ? primaryColor : AppColors.textSecondary,
                  ),
                  onPressed: onFavoriteTap,
                ),
              if (!isMobile && onAddToPlaylistTap != null)
                IconButton(
                  tooltip: 'Agregar a playlist',
                  icon: const Icon(Icons.add_rounded,
                      size: 20, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shadowColor: Colors.transparent,
                  ),
                  onPressed: onAddToPlaylistTap,
                ),
              if (!isMobile && onDeleteTap != null)
                IconButton(
                  tooltip: 'Quitar de MuShare',
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 22, color: AppColors.textSecondary),
                  onPressed: onDeleteTap,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMobileActions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Text(
                song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (onAddToPlaylistTap != null)
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('Agregar a playlist'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onAddToPlaylistTap!();
                },
              ),
            if (onDeleteTap != null)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: const Text('Quitar de MuShare'),
                textColor: Theme.of(context).colorScheme.error,
                iconColor: Theme.of(context).colorScheme.error,
                onTap: () {
                  Navigator.pop(sheetContext);
                  onDeleteTap!();
                },
              ),
            if (song.artworkPath == null && onArtworkTap != null)
              ListTile(
                leading: const Icon(Icons.add_photo_alternate_outlined),
                title: const Text('Agregar portada'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onArtworkTap!();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildArtwork(BuildContext context) {
    final hasArtwork = song.artworkPath != null;

    return Stack(
      alignment: Alignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: hasArtwork
              ? Image.file(
                  File(song.artworkPath!),
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  cacheWidth:
                      (52 * MediaQuery.devicePixelRatioOf(context)).round(),
                  cacheHeight:
                      (52 * MediaQuery.devicePixelRatioOf(context)).round(),
                  filterQuality: FilterQuality.low,
                )
              : Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient(context),
                  ),
                  child: const Icon(Icons.music_note_rounded,
                      color: Colors.white, size: 22),
                ),
        ),
        // Overlay sutil + ícono de ecualizador cuando esta es la canción
        // actual, en vez de reemplazar por completo la portada (así el
        // usuario nunca pierde la referencia visual del álbum).
        if (isPlaying)
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.black.withValues(alpha: 0.45),
            ),
            child: Icon(Icons.equalizer_rounded,
                color: Theme.of(context).colorScheme.primary, size: 22),
          ),
      ],
    );
  }
}
