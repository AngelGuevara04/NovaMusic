class WebMediaHelper {
  static bool get isHidden => false;

  static void initVisibilityListener(void Function(bool isHidden) onChanged) {}

  static void setActionHandlers({
    required Future<void> Function() onPlay,
    required Future<void> Function() onPause,
    required Future<void> Function() onNext,
    required Future<void> Function() onPrevious,
    Future<void> Function(Duration position)? onSeekTo,
  }) {}

  static void updateMediaSession({
    required String title,
    required String artist,
    required String album,
    required bool isPlaying,
  }) {}
}
