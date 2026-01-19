import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';
import '../models/post_model.dart';

class DatabaseService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  Future<void> createPost(PostModel post) async {
    await _db.child('posts').child(post.id).set(post.toJson());
  }

  // We will listen to the stream in the provider, but here's a helper to get the query
  Query get postsQuery => _db.child('posts').orderByChild('timestamp');

  Future<void> likePost(String postId, String userId) async {//runTransaction to toggle likes
    final postRef = _db.child('posts').child(postId);
    await postRef.runTransaction((Object? post) {
      if (post == null) {
        return Transaction.success(post);
      }
      final Map<String, dynamic> postData = Map<String, dynamic>.from(
        post as Map,
      );
      final likes =
          postData['likes'] != null
              ? Map<String, dynamic>.from(postData['likes'])
              : {};

      if (likes.containsKey(userId)) {
        likes.remove(userId);
      } else {
        likes[userId] = true;
      }

      postData['likes'] = likes;
      return Transaction.success(postData);
    });
  }

  Future<void> deletePost(String postId) async {
    await _db.child('posts').child(postId).remove();
  }

  // --- Comments (Nested in Posts) ---
  Future<void> addComment(
    String postId,
    String userId,
    String username,
    String? userImage,
    String text,
  ) async {
    final commentId = const Uuid().v4();
    final comment = {
      'id': commentId,
      'userId': userId,
      'username': username,
      'userImage': userImage ?? '',
      'text': text,
      'timestamp': ServerValue.timestamp,
    };
    // Path: posts/{postId}/comments/{commentId}
    await _db
        .child('posts')
        .child(postId)
        .child('comments')
        .child(commentId)
        .set(comment);

    // Update comment count
    final postRef = _db.child('posts').child(postId);
    final snapshot = await postRef.child('commentCount').get();
    int count = (snapshot.value as int? ?? 0) + 1;
    await postRef.update({'commentCount': count});
  }

  Stream<DatabaseEvent> getComments(String postId) {
    // Path: posts/{postId}/comments
    return _db.child('posts').child(postId).child('comments').onValue;
  }

  // --- Social Graph (Nested in Users) ---
  Future<void> followUser(String currentUserId, String targetUserId) async {
    // Add target to current user's following: users/{current}/following/{target}
    await _db
        .child('users')
        .child(currentUserId)
        .child('following')
        .child(targetUserId)
        .set(true);
    // Add current to target's followers: users/{target}/followers/{current}
    await _db
        .child('users')
        .child(targetUserId)
        .child('followers')
        .child(currentUserId)
        .set(true);
  }

  Future<void> unfollowUser(String currentUserId, String targetUserId) async {
    await _db
        .child('users')
        .child(currentUserId)
        .child('following')
        .child(targetUserId)
        .remove();
    await _db
        .child('users')
        .child(targetUserId)
        .child('followers')
        .child(currentUserId)
        .remove();
  }

  Future<bool> isFollowing(String currentUserId, String targetUserId) async {
    final snapshot =
        await _db
            .child('users')
            .child(currentUserId)
            .child('following')
            .child(targetUserId)
            .get();
    return snapshot.exists;
  }

  Future<List<String>> getFollowingIds(String userId) async {
    final snapshot =
        await _db.child('users').child(userId).child('following').get();
    if (snapshot.exists && snapshot.value != null) {
      Map<dynamic, dynamic> map = snapshot.value as Map<dynamic, dynamic>;
      return map.keys.cast<String>().toList();
    }
    return [];
  }

  Future<List<String>> getFollowerIds(String userId) async {
    final snapshot =
        await _db.child('users').child(userId).child('followers').get();
    if (snapshot.exists && snapshot.value != null) {
      Map<dynamic, dynamic> map = snapshot.value as Map<dynamic, dynamic>;
      return map.keys.cast<String>().toList();
    }
    return [];
  }

  // --- Stories (Nested in Users) ---
  Future<void> createStory(
    String userId,
    String username,
    String? userImage,
    String mediaUrl,
    String mediaType,
  ) async {
    final storyId = const Uuid().v4();
    final story = {
      'id': storyId,
      'userId': userId,
      'username': username,
      'userImage': userImage ?? '',
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'timestamp': ServerValue.timestamp,
    };
    // Path: users/{userId}/stories/{storyId}
    await _db
        .child('users')
        .child(userId)
        .child('stories')
        .child(storyId)
        .set(story);
  }

  Future<void> deleteStory(String userId, String storyId) async {
    await _db
        .child('users')
        .child(userId)
        .child('stories')
        .child(storyId)
        .remove();
  }

  // Helper to fetch all stories from followed users + self (for Feed)
  // Since stories are now nested, we can't just query 'stories' root.
  // We need to fetch stories for each followed user.
  // For simplicity in this session, we will fetch ALL users and filter, OR fetch individually.
  // Fetching all users is heavy.
  // Better approach: Maintain a 'feed_stories' or just iterate followed users.
  // Given user wants "one circle per user", iterating users is fine.
  // We won't have a single stream for ALL stories easily. We need to fetch/listen.
  // I will expose a method to get stories for a specific user ID.
  Stream<DatabaseEvent> getUserStories(String userId) {
    return _db
        .child('users')
        .child(userId)
        .child('stories')
        .orderByChild('timestamp')
        .onValue;
  }

  // Backwards compatibility/Search for "All Stories" (e.g. Discovery) is harder.
  // I'll leave 'storiesQuery' but it won't work with new structure.
  // I'll remove it.

  // --- Notifications ---

  Future<void> sendNotification(
    String receiverId,
    String senderId,
    String senderName,
    String type, {
    String? postId,
  }) async {
    if (receiverId == senderId) return; // Don't notify self
    final notifId = const Uuid().v4();
    final notif = {
      'id': notifId,
      'senderId': senderId,
      'senderName': senderName,
      'type': type, // 'like', 'comment', 'follow'
      'postId': postId,
      'timestamp': ServerValue.timestamp,
      'read': false,
    };
    await _db
        .child('notifications')
        .child(receiverId)
        .child(notifId)
        .set(notif);
  }

  // --- Repost ---

  Future<void> repost(
    PostModel originalPost,
    String currentUserId,
    String currentUsername,
    String? currentUserImage,
  ) async {
    // Create a new post referencing the original
    final newId = const Uuid().v4();
    final repost = PostModel(
      id: newId,
      userId: currentUserId,
      username: currentUsername,
      userProfileImage: currentUserImage ?? '',
      mediaUrl: originalPost.mediaUrl, // Repost same media
      mediaType: originalPost.mediaType,
      caption:
          "Reposted from @${originalPost.username}: ${originalPost.caption ?? ''}",
      timestamp:
          DateTime.now().millisecondsSinceEpoch, // Fix: Use int timestamp
      likes: {},
      commentCount: 0,
    );

    await createPost(repost);
  }

  // No second getComments here

  // For Discovery
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    final result = await _db.child('users').limitToFirst(50).get();
    if (result.exists && result.value != null) {
      final Map<dynamic, dynamic> usersMap =
          result.value as Map<dynamic, dynamic>;
      final List<Map<String, dynamic>> users = [];
      usersMap.forEach((key, value) {
        users.add(Map<String, dynamic>.from(value));
      });
      return users;
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    if (query.isEmpty) return [];

    final lowerQuery = query.toLowerCase();

    // 1. Try optimized search (requires index)
    try {
      final result =
          await _db
              .child('users')
              .orderByChild('username_key')
              .startAt(lowerQuery)
              .endAt('$lowerQuery\uf8ff')
              .limitToFirst(20)
              .get();

      if (result.exists && result.value != null) {
        final Map<dynamic, dynamic> usersMap =
            result.value as Map<dynamic, dynamic>;
        final List<Map<String, dynamic>> users = [];
        usersMap.forEach((key, value) {
          users.add(Map<String, dynamic>.from(value));
        });
        if (users.isNotEmpty) return users;
      }
    } catch (e) {
      // Ignore index errors, proceed to fallback
      print("Search index error (using fallback): $e");
    }

    // 2. Fallback: Client-side filter (handles missing keys/indices)
    // Fetch recent 50 users (or all if small DB)
    final fallbackResult = await _db.child('users').limitToFirst(50).get();
    if (fallbackResult.exists && fallbackResult.value != null) {
      final Map<dynamic, dynamic> usersMap =
          fallbackResult.value as Map<dynamic, dynamic>;
      final List<Map<String, dynamic>> users = [];
      usersMap.forEach((key, value) {
        final userMap = Map<String, dynamic>.from(value);
        final username = userMap['username']?.toString().toLowerCase() ?? '';
        if (username.contains(lowerQuery)) {
          users.add(userMap);
        }
      });
      return users;
    }

    return [];
  }

  Future<Map<String, dynamic>?> getUser(String userId) async {
    final snapshot = await _db.child('users').child(userId).get();
    if (snapshot.exists && snapshot.value != null) {
      return Map<String, dynamic>.from(snapshot.value as Map);
    }
    return null;
  }
}
