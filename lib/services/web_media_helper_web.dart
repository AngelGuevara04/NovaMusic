import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

class WebMediaHelper {
  static bool _visInitialized = false;

  static bool get isHidden {
    try {
      final doc = globalContext['document'];
      if (doc is JSObject) {
        final hidden = doc['hidden'];
        if (hidden is JSBoolean) return hidden.toDart;
      }
    } catch (_) {}
    return false;
  }

  static void initVisibilityListener(void Function(bool isHidden) onChanged) {
    if (_visInitialized) return;
    _visInitialized = true;
    try {
      final doc = globalContext['document'];
      if (doc is JSObject) {
        doc.callMethod(
          'addEventListener'.toJS,
          'visibilitychange'.toJS,
          ((JSAny? _) {
            onChanged(isHidden);
          }).toJS,
        );
      }
    } catch (_) {}
  }

  static void setActionHandlers({
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
    Future<void> Function(Duration position)? onSeekTo,
  }) {
    try {
      final nav = globalContext['navigator'];
      if (nav is! JSObject) return;
      final mediaSession = nav['mediaSession'];
      if (mediaSession is! JSObject) return;

      void register(String action, JSFunction handler) {
        try {
          mediaSession.callMethod('setActionHandler'.toJS, action.toJS, handler);
        } catch (_) {}
      }

      register('play', ((JSAny? _) { unawaited(onPlay()); }).toJS);
      register('pause', ((JSAny? _) { unawaited(onPause()); }).toJS);
      register('nexttrack', ((JSAny? _) { unawaited(onNext()); }).toJS);
      register('previoustrack', ((JSAny? _) { unawaited(onPrevious()); }).toJS);
      if (onSeekTo != null) {
        register('seekto', ((JSAny? details) {
          try {
            if (details is JSObject) {
              final seekTime = details['seekTime'];
              if (seekTime is JSNumber) {
                unawaited(onSeekTo(Duration(milliseconds: (seekTime.toDartDouble * 1000).round())));
              }
            }
          } catch (_) {}
        }).toJS);
      }
    } catch (_) {}
  }

  static void updateMediaSession({
    required String title,
    required String artist,
    required String album,
    required bool isPlaying,
  }) {
    try {
      final nav = globalContext['navigator'];
      if (nav is! JSObject) return;
      final mediaSession = nav['mediaSession'];
      if (mediaSession is! JSObject) return;

      final ctor = globalContext['MediaMetadata'];
      if (ctor is JSFunction) {
        final metadataInit = <String, Object>{
          'title': title,
          'artist': artist,
          'album': album,
        }.jsify();
        final metadata = ctor.callAsConstructor<JSObject>(metadataInit);
        mediaSession['metadata'] = metadata;
      }

      mediaSession['playbackState'] = (isPlaying ? 'playing' : 'paused').toJS;
    } catch (_) {}
  }
}
