import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../player/domain/entities/models.dart';
import '../data/download_service.dart';

/// Enhanced download dialog:
/// rename, folder select, quality, queue/now, size estimate, storage warning.
class DownloadDialog extends StatefulWidget {
  final VideoItem video;
  final PlaybackStreams streams;

  const DownloadDialog({
    super.key,
    required this.video,
    required this.streams,
  });

  static Future<void> show(
      BuildContext context,
      VideoItem video,
      PlaybackStreams streams) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, __) => DownloadDialog(
            video: video, streams: streams),
      ),
    );
  }

  @override
  State<DownloadDialog> createState() =>
      _DownloadDialogState();
}

class _DownloadDialogState
    extends State<DownloadDialog> {
  late final TextEditingController _nameCtrl;
  String _folder = 'Videos';
  QualityOption? _selectedQuality;
  bool _isAudio = false;
  bool _downloadNow = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
        text: _safeName(widget.video.title));
    if (widget.streams.qualities.isNotEmpty) {
      _selectedQuality =
          widget.streams.qualities.first;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String _safeName(String title) {
    return title
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  String get _extension =>
      _isAudio ? 'm4a' : 'mp4';

  Future<void> _start() async {
    final quality = _selectedQuality;
    if (quality == null && !_isAudio) return;

    final url = _isAudio
        ? widget.streams.audioOnlyUrl
        : (quality!.audioUrl ?? quality.url);
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(
                content:
                    Text('No stream URL available')));
      }
      return;
    }

    Navigator.pop(context);
    final record =
        await DownloadService.instance.enqueue(
      videoId: widget.video.id,
      title: _nameCtrl.text.trim().isEmpty
          ? widget.video.title
          : _nameCtrl.text.trim(),
      url: url,
      isAudio: _folder == 'Music' || _isAudio,
      extension: _extension,
      qualityLabel:
          _isAudio ? 'audio' : quality?.label,
      folder: _folder,
      startNow: _downloadNow,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(record != null
              ? (_downloadNow
                  ? 'Download started'
                  : 'Added to queue')
              : 'Download failed — check storage permission.'),
          backgroundColor: record != null
              ? AppTheme.success
              : AppTheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                16, 16, 16, 8),
            child: Text('Download',
                style: AppTheme.title),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  16, 0, 16, 16),
              children: [
                Text('File name',
                    style: AppTheme.body.copyWith(
                        fontWeight:
                            FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  decoration: InputDecoration(
                    suffixText: '.$_extension',
                    suffixStyle: AppTheme.caption
                        .copyWith(
                            color: AppTheme
                                .textSecondary),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Save to',
                    style: AppTheme.body.copyWith(
                        fontWeight:
                            FontWeight.w600)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _folderChip('Videos',
                        Icons.videocam_outlined),
                    const SizedBox(width: 8),
                    _folderChip('Music',
                        Icons.music_note_outlined),
                    const SizedBox(width: 8),
                    _folderChip('Custom',
                        Icons.folder_outlined),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _typeTab(
                          'Video', !_isAudio,
                          () {
                        setState(() {
                          _isAudio = false;
                          if (_selectedQuality ==
                                  null &&
                              widget.streams
                                  .qualities
                                  .isNotEmpty) {
                            _selectedQuality = widget
                                .streams
                                .qualities
                                .first;
                          }
                        });
                      }),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _typeTab(
                          'Audio', _isAudio, () {
                        setState(
                            () => _isAudio = true);
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_isAudio)
                  ...widget.streams.qualities.map(
                    (q) => RadioListTile<
                        QualityOption>(
                      value: q,
                      groupValue:
                          _selectedQuality,
                      onChanged: (v) => setState(
                          () =>
                              _selectedQuality =
                                  v),
                      title: Text(q.label,
                          style: AppTheme.body),
                      subtitle: q.isVideoOnly
                          ? Text(
                              'Video + audio',
                              style: AppTheme
                                  .caption
                                  .copyWith(
                                      color: AppTheme
                                          .textSecondary))
                          : null,
                      activeColor:
                          AppTheme.primary,
                      contentPadding:
                          EdgeInsets.zero,
                      dense: true,
                    ),
                  )
                else
                  RadioListTile<bool>(
                    value: true,
                    groupValue: true,
                    onChanged: (_) {},
                    title: Text(
                        'Best audio quality',
                        style: AppTheme.body),
                    activeColor:
                        AppTheme.primary,
                    contentPadding:
                        EdgeInsets.zero,
                    dense: true,
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                        Icons
                            .storage_outlined,
                        size: 16,
                        color:
                            AppTheme.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      'Estimated size: Unknown (shown during download)',
                      style:
                          AppTheme.caption.copyWith(
                              color: AppTheme
                                  .textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _modeTab(
                          'Download now',
                          _downloadNow, () {
                        setState(() =>
                            _downloadNow = true);
                      }),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _modeTab(
                          'Add to queue',
                          !_downloadNow, () {
                        setState(() =>
                            _downloadNow = false);
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _start,
                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        AppTheme.primary,
                    padding:
                        const EdgeInsets.symmetric(
                            vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                                12)),
                  ),
                  child: Text(
                      _downloadNow
                          ? 'Download'
                          : 'Add to Queue',
                      style: AppTheme.subtitle
                          .copyWith(
                              color: Colors.white)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _folderChip(String label, IconData icon) {
    final active = _folder == label;
    return InkWell(
      onTap: () {
        setState(() => _folder = label);
        if (label == 'Custom' && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(
                  content: Text(
                      'Custom folder: /PureTube/Downloads/')));
        }
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(20),
          color: active
              ? AppTheme.primary
              : AppTheme.card,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(label,
                style: AppTheme.body.copyWith(
                    color: Colors.white,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _typeTab(
      String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
            vertical: 12),
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(12),
          color: active
              ? AppTheme.primary.withOpacity(0.2)
              : AppTheme.card,
          border: Border.all(
            color: active
                ? AppTheme.primary
                : Colors.transparent,
          ),
        ),
        child: Center(
          child: Text(label,
              style: AppTheme.body.copyWith(
                  color: active
                      ? AppTheme.primary
                      : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _modeTab(
      String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(
            vertical: 10),
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(12),
          color: active
              ? AppTheme.primary
              : AppTheme.card,
        ),
        child: Center(
          child: Text(label,
              style: AppTheme.body.copyWith(
                  color: Colors.white,
                  fontSize: 13)),
        ),
      ),
    );
  }
}
