import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../domain/models/chat.dart';

/// All bubbles in a screen share one player: only one note can play at a time.
class VoiceNotePlayer extends StatefulWidget {
  const VoiceNotePlayer({
    required this.message,
    required this.player,
    required this.selected,
    required this.loadUrl,
    required this.color,
    super.key,
  });
  final ChatMessage message;
  final AudioPlayer player;
  final ValueNotifier<String?> selected;
  final Future<String> Function() loadUrl;
  final Color color;
  @override
  State<VoiceNotePlayer> createState() => _VoiceNotePlayerState();
}

class _VoiceNotePlayerState extends State<VoiceNotePlayer>
    with WidgetsBindingObserver {
  bool _busy = false;
  String? _error;
  Duration _position = Duration.zero;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool get _selected => widget.selected.value == widget.message.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.selected.addListener(_changed);
    _subscriptions.add(
      widget.player.onPlayerStateChanged.listen((_) => _changed()),
    );
    _subscriptions.add(
      widget.player.onPositionChanged.listen((position) {
        if (mounted && _selected) setState(() => _position = position);
      }),
    );
    _subscriptions.add(
      widget.player.onPlayerComplete.listen((_) {
        if (mounted && _selected) setState(() => _position = Duration.zero);
      }),
    );
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _selected) {
      unawaited(widget.player.pause().catchError((_) {}));
    }
  }

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_selected && widget.player.state == PlayerState.playing) {
        await widget.player.pause();
      } else {
        final position = _selected ? _position : Duration.zero;
        widget.selected.value = widget.message.id;
        await widget.player.stop();
        final url = await widget.loadUrl();
        if (!mounted ||
            !_selected ||
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed) {
          return;
        }
        // Fresh signed URL on every play/resume; never persist the URL.
        await widget.player.play(UrlSource(url), position: position);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Cannot play. Tap to retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.selected.removeListener(_changed);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    if (_selected) unawaited(widget.player.stop().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playing = _selected && widget.player.state == PlayerState.playing;
    final seconds = ((widget.message.voiceDurationMs ?? 0) / 1000).ceil();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: playing ? 'Pause voice message' : 'Play voice message',
              onPressed: _busy ? null : _toggle,
              color: widget.color,
              icon: Icon(
                _busy
                    ? Icons.hourglass_empty
                    : playing
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
            ),
            Flexible(
              child: Text(
                '${_selected ? _position.inSeconds : 0}s / ${seconds}s',
                style: TextStyle(color: widget.color),
              ),
            ),
          ],
        ),
        if (_error != null)
          Text(_error!, style: TextStyle(color: widget.color)),
      ],
    );
  }
}
