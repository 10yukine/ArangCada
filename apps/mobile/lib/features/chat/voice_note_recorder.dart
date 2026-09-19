import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

/// Temporary microphone capture only; no recording survives closing the sheet.
class VoiceRecorder {
  late final _recorder = AudioRecorder();
  Directory? _directory;
  Future<void>? _starting;

  Future<void> start() => _starting = _start();
  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      throw StateError(
        'Microphone permission is required. You can enable it in Android app settings.',
      );
    }
    final previous = _directory;
    if (previous != null && await previous.exists()) {
      await previous.delete(recursive: true);
    }
    _directory = await (await getTemporaryDirectory()).createTemp(
      'trip-voice-',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 24000,
        numChannels: 1,
      ),
      path: '${_directory!.path}/note.m4a',
    );
  }

  Future<Uint8List> stop() async {
    final path = await _recorder.stop();
    if (path == null) throw StateError('No audio was recorded.');
    final file = File(path);
    if (await file.length() > 1048576) {
      throw StateError('Voice note exceeds 1 MB.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) throw StateError('No audio was recorded.');
    return bytes;
  }

  Future<void> dispose() async {
    if (_starting == null) return;
    try {
      await _starting;
    } catch (_) {
      /* Still release the microphone. */
    }
    await _recorder.dispose();
    final directory = _directory;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

class VoiceNoteRecorder extends StatefulWidget {
  const VoiceNoteRecorder({required this.onSend, this.recorder, super.key});
  final Future<void> Function(String id, Uint8List bytes, int durationMs)
  onSend;
  final VoiceRecorder? recorder;
  @override
  State<VoiceNoteRecorder> createState() => _VoiceNoteRecorderState();
}

class _VoiceNoteRecorderState extends State<VoiceNoteRecorder>
    with WidgetsBindingObserver {
  late final VoiceRecorder _recorder = widget.recorder ?? VoiceRecorder();
  final _id = const Uuid().v4();
  final _clock = Stopwatch();
  Timer? _timer;
  Uint8List? _bytes;
  int _durationMs = 0;
  bool _recording = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _recording) unawaited(_stop());
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _recorder.start();
      if (!mounted) return;
      _clock
        ..reset()
        ..start();
      setState(() => _recording = true);
      _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (_clock.elapsedMilliseconds >= 60000) {
          unawaited(_stop());
        } else if (mounted) {
          setState(() {});
        }
      });
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        await _stop();
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message
              : 'Could not start the microphone. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (!_recording) return;
    _timer?.cancel();
    _clock.stop();
    setState(() {
      _recording = false;
      _busy = true;
    });
    try {
      final bytes = await _recorder.stop();
      if (!mounted) return;
      if (_clock.elapsedMilliseconds < 500) {
        throw StateError('Record at least half a second.');
      }
      setState(() {
        _bytes = bytes;
        _durationMs = _clock.elapsedMilliseconds.clamp(1, 60000);
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError
              ? error.message
              : 'Could not finish recording. Close and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    if (_busy || _bytes == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSend(_id, _bytes!, _durationMs);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not send. Check your connection and that this ride is still active, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(_recorder.dispose().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Voice message',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              _recording
                  ? 'Recording · ${(_clock.elapsedMilliseconds / 1000).floor()} / 60 seconds'
                  : _bytes != null
                  ? 'Ready · ${(_durationMs / 1000).ceil()} seconds'
                  : 'Record up to 60 seconds. Nothing is sent until you tap Send.',
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, semanticsLabel: _error),
              ),
            const SizedBox(height: 12),
            if (_recording)
              FilledButton.icon(
                onPressed: _stop,
                icon: const Icon(Icons.stop),
                label: const Text('Stop recording'),
              )
            else if (_bytes != null)
              FilledButton(
                onPressed: _busy ? null : _send,
                child: Text(
                  _busy
                      ? 'Sending…'
                      : _error != null
                      ? 'Retry send'
                      : 'Send voice message',
                ),
              )
            else
              FilledButton.icon(
                onPressed: _busy ? null : _start,
                icon: const Icon(Icons.mic),
                label: Text(_busy ? 'Starting…' : 'Record'),
              ),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('Discard and close'),
            ),
          ],
        ),
      ),
    ),
  );
}
