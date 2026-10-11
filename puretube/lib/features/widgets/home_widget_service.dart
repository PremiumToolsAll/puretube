import 'package:home_widget/home_widget.dart';

/// Home screen widgets: Continue Watching + Quick Search.
class HomeWidgetService {
  HomeWidgetService._();
  static final HomeWidgetService instance =
      HomeWidgetService._();

  static const _continueWatchingId =
      'ContinueWatchingWidget';
  static const _quickSearchId =
      'QuickSearchWidget';

  Future<void> init() async {
    try {
      await HomeWidget.setAppGroupId(
          'group.com.puretube.app');
    } catch (_) {}
  }

  /// Update "Continue Watching" widget when a video plays.
  Future<void> updateContinueWatching({
    required String videoId,
    required String title,
    required String author,
    required String thumbnailUrl,
  }) async {
    try {
      await HomeWidget.saveWidgetData<String>(
          'last_video_id', videoId);
      await HomeWidget.saveWidgetData<String>(
          'last_video_title', title);
      await HomeWidget.saveWidgetData<String>(
          'last_video_author', author);
      await HomeWidget.saveWidgetData<String>(
          'last_video_thumb', thumbnailUrl);
      await HomeWidget.updateWidget(
        name: _continueWatchingId,
        androidName: _continueWatchingId,
        iOSName: _continueWatchingId,
      );
    } catch (_) {}
  }

  Future<void> clearContinueWatching() async {
    try {
      await HomeWidget.saveWidgetData<String>(
          'last_video_id', '');
      await HomeWidget.updateWidget(
        name: _continueWatchingId,
        androidName: _continueWatchingId,
      );
    } catch (_) {}
  }

  /// Handle widget tap -> returns video id to open.
  Future<String?> getLaunchVideoId(
      Uri? uri) async {
    try {
      final data =
          await HomeWidget.getWidgetData<String>(
              'launch_video_id',
              defaultValue: '');
      if (data != null && data.isNotEmpty) {
        await HomeWidget.saveWidgetData<String>(
            'launch_video_id', '');
        return data;
      }
    } catch (_) {}
    // Deep link URI fallback.
    if (uri != null) {
      final id = uri.queryParameters['videoId'];
      if (id != null && id.isNotEmpty) {
        return id;
      }
    }
    return null;
  }
}
