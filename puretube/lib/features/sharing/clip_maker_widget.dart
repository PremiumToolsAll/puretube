import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/file_utils.dart';
import '../../core/utils/format.dart';

/// Video clip maker: trim max 60s and share.
class ClipMakerWidget extends StatefulWidget {
  final Player player;
  final String videoId;
  final String title;
  final String sourcePath; // local file OR stream url

  const ClipMakerWidget({
    super.key,
    required this.player,
    required this.videoId,
    required this.title,
    required this.sourcePath,
  });

  static Future<void> show(
    BuildContext context, {
    required Player player,
    required String videoId,
    required String title,
    required String sourcePath,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, __) => ClipMakerWidget(
          player: player,
          videoId: videoId,
          title: title,
          sourcePath: sourcePath,
        ),
      ),
    );
  }

  @override
  State<ClipMakerWidget> createState() =>
      _ClipMakerWidgetState();
}

class _ClipMakerWidgetState
    extends State<ClipMakerWidget> {
  double _start = 0;
  double _end = 30;
  double _max = 60;
  bool _working = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    final dur =
        widget.player.state.duration;
    if (dur > Duration.zero) {
      _max =
          dur.inSeconds.toDouble();
      _end = _max > 60 ? 60 : _max;
    }
  }

  Future<void> _create() async {
    final length = _end - _start;
    if (length <= 0 || length > 60) {
      setState(() => _status =
          'Clip must be 1–60 seconds.');
      return;
    }
    setState(() {
      _working = true;
      _status = 'Trimming…';
    });
    try {
      final dir =
          await FileUtils.customDir(
              'Clips');
      final out =
          '${dir.path}/${FileUtils.safeName(widget.title)}_clip_${_start.toInt()}-${_end.toInt()}.mp4';
      // -ss before -i = fast seek; -t = duration.
      final cmd =
          '-y -ss $_start -i "${widget.sourcePath}" -t $length -c copy "$out"';
      final session =
          await FFmpegKit.execute(cmd);
      final code =
          await session.getReturnCode();
      if (code?.isValueSuccess() == true) {
        if (mounted) {
          setState(() =>
              _status = 'Clip created!');
          Navigator.pop(context);
          await Share.shareXFiles(
              [XFile(out)],
              text:
                  'Clip from ${widget.title}');
        }
      } else {
        if (mounted) {
          setState(() => _status =
              'Trim failed. Try a downloaded file.');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(
            () => _status = 'Error: $e');
      }
    } finally {
      if (mounted) {
        setState(
            () => _working = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text('Create clip (max 60s)',
                style: AppTheme.subtitle),
            const SizedBox(height: 16),
            Text(
                'Start: ${formatDuration(Duration(seconds: _start.toInt()))}',
                style: AppTheme.body),
            Slider(
              value: _start,
              min: 0,
              max: _max,
              activeColor:
                  AppTheme.primary,
              onChanged: (v) => setState(() {
                _start = v;
                if (_end <= _start) {
                  _end = (_start + 10)
                      .clamp(0, _max);
                }
              }),
            ),
            Text(
                'End: ${formatDuration(Duration(seconds: _end.toInt()))}',
                style: AppTheme.body),
            Slider(
              value: _end,
              min: 0,
              max: _max,
              activeColor:
                  AppTheme.primary,
              onChanged: (v) => setState(
                  () => _end = v),
            ),
            const SizedBox(height: 8),
            Text(
                'Length: ${(_end - _start).toStringAsFixed(0)}s',
                style:
                    AppTheme.caption.copyWith(
                        color: AppTheme
                            .textSecondary)),
            if (_status != null) ...[
              const SizedBox(height: 8),
              Text(_status!,
                  style: AppTheme.caption
                      .copyWith(
                          color: AppTheme
                              .primary)),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _working
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child:
                            CircularProgressIndicator(
                                strokeWidth:
                                    2,
                                color: Colors
                                    .white))
                    : const Icon(
                        Icons.content_cut),
                label:
                    const Text('Create & Share'),
                style: ElevatedButton
                    .styleFrom(
                        backgroundColor:
                            AppTheme.primary,
                        padding:
                            const EdgeInsets
                                .symmetric(
                                vertical:
                                    14)),
                onPressed:
                    _working ? null : _create,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
