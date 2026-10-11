import 'dart:convert';

import 'package:http/http.dart' as http;

/// Like/dislike counts via ReturnYouTubeDislike public API.
/// (YouTube no longer exposes dislikes via InnerTube.)
class DislikeService {
  static const _base =
      'https://returnyoutubedislikeapi.com';

  final http.Client _client;

  DislikeService([http.Client? client])
      : _client = client ?? http.Client();

  Future<DislikeVotes> getVotes(String videoId) async {
    try {
      final uri = Uri.parse('$_base/votes?videoId=$videoId');
      final res = await _client
          .get(uri)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        return const DislikeVotes();
      }
      final d =
          jsonDecode(res.body) as Map<String, dynamic>;
      return DislikeVotes(
        likes: (d['likes'] as num?)?.toInt(),
        dislikes: (d['dislikes'] as num?)?.toInt(),
      );
    } catch (_) {
      return const DislikeVotes();
    }
  }

  void dispose() => _client.close();
}

class DislikeVotes {
  final int? likes;
  final int? dislikes;

  const DislikeVotes({this.likes, this.dislikes});
}
