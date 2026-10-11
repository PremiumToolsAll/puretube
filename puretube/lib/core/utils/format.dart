/// Format a [Duration] as H:MM:SS or M:SS.
String formatDuration(Duration? d) {
  if (d == null) return '--:--';
  final total = d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// 1234567 -> "1.2M", 1234 -> "1.2K".
String formatCount(int? count) {
  if (count == null) return '';
  if (count >= 1000000000) {
    return '${(count / 1000000000).toStringAsFixed(1)}B';
  }
  if (count >= 1000000) {
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }
  if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(1)}K';
  }
  return '$count';
}

/// "2024-01-15" style -> "2 weeks ago".
String timeAgo(DateTime? date) {
  if (date == null) return '';
  final diff = DateTime.now().difference(date);
  if (diff.inDays >= 365) {
    final y = diff.inDays ~/ 365;
    return '$y year${y > 1 ? 's' : ''} ago';
  }
  if (diff.inDays >= 30) {
    final m = diff.inDays ~/ 30;
    return '$m month${m > 1 ? 's' : ''} ago';
  }
  if (diff.inDays >= 7) {
    final w = diff.inDays ~/ 7;
    return '$w week${w > 1 ? 's' : ''} ago';
  }
  if (diff.inDays >= 1) {
    return '${diff.inDays} day${diff.inDays > 1 ? 's' : ''} ago';
  }
  if (diff.inHours >= 1) {
    return '${diff.inHours} hour${diff.inHours > 1 ? 's' : ''} ago';
  }
  if (diff.inMinutes >= 1) {
    return '${diff.inMinutes} min ago';
  }
  return 'just now';
}
