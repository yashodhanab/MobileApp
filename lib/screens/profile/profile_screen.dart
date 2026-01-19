import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../providers/feed_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/database_service.dart';
import '../../widgets/post_card.dart'; // Reusing PostCard for detail view
import 'edit_profile_screen.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final bool isCurrentUser;

  const ProfileScreen({
    super.key,
    required this.userId,
    this.isCurrentUser = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  UserModel? _user;
  bool _isLoading = true;
  bool _isFollowing = false;

  // Stats
  int _followersCount = 0;
  int _followingCount = 0;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAllData();
  }

  void _loadAllData() async {
    if (widget.isCurrentUser) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      _user = userProvider.currentUser;
    } else {
      final data = await DatabaseService().getUser(widget.userId);
      if (data != null) {
        _user = UserModel.fromJson(data);
      }
    }

    if (_user != null) {
      await _loadStats();
      await _checkIfFollowing();
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadStats() async {
    final followers = await DatabaseService().getFollowerIds(widget.userId);
    final following = await DatabaseService().getFollowingIds(widget.userId);
    if (mounted) {
      setState(() {
        _followersCount = followers.length;
        _followingCount = following.length;
      });
    }
  }

  Future<void> _checkIfFollowing() async {
    if (widget.isCurrentUser) return;
    final currentUser =
        Provider.of<UserProvider>(context, listen: false).currentUser;
    if (currentUser != null) {
      final following = await DatabaseService().isFollowing(
        currentUser.id,
        widget.userId,
      );
      if (mounted) setState(() => _isFollowing = following);
    }
  }

  Future<void> _toggleFollow() async {
    final currentUser =
        Provider.of<UserProvider>(context, listen: false).currentUser;
    if (currentUser == null) return;

    setState(() => _isFollowing = !_isFollowing); // Optimistic UI

    if (_isFollowing) {
      await DatabaseService().followUser(currentUser.id, widget.userId);
      _followersCount++;
    } else {
      await DatabaseService().unfollowUser(currentUser.id, widget.userId);
      _followersCount--;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_user == null) {
      return const Scaffold(body: Center(child: Text("User not found")));
    }

    final allPosts = Provider.of<FeedProvider>(context).posts;
    final userPosts = allPosts.where((p) => p.userId == widget.userId).toList();
    userPosts.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _user!.username,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (widget.isCurrentUser)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(user: _user!.toJson()),
                  ),
                );
                _loadAllData(); // Reload after return
              },
            ),
          if (widget.isCurrentUser)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await Provider.of<UserProvider>(
                  context,
                  listen: false,
                ).logout();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (r) => false,
                  );
                }
              },
            ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, _) {
          return [
            SliverList(
              delegate: SliverChildListDelegate([
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Avatar + Stats
                      Row(
                        children: [
                          Hero(
                            tag: 'profile_${_user!.id}',
                            child: CircleAvatar(
                              radius: 40,
                              backgroundColor: Colors.grey[200],
                              backgroundImage:
                                  _user!.profileImageUrl != null &&
                                          _user!.profileImageUrl!.isNotEmpty
                                      ? CachedNetworkImageProvider(
                                        _user!.profileImageUrl!,
                                      )
                                      : null,
                              child:
                                  (_user!.profileImageUrl == null ||
                                          _user!.profileImageUrl!.isEmpty)
                                      ? const Icon(
                                        Icons.person,
                                        size: 40,
                                        color: Colors.grey,
                                      )
                                      : null,
                            ),
                          ),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildStat(
                                  "Posts",
                                  userPosts.length.toString(),
                                ),
                                _buildStat(
                                  "Followers",
                                  _followersCount.toString(),
                                ),
                                _buildStat(
                                  "Following",
                                  _followingCount.toString(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 12),

                      // Bio Section
                      Text(
                        _user!.username,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      if (_user!.bio != null && _user!.bio!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _user!.bio!,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),

                      const SizedBox(height: 16),

                      // Action Buttons
                      if (widget.isCurrentUser)
                        Row(
                          children: [
                            Expanded(
                              child: _buildProfileButton(
                                context,
                                "Edit Profile",
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => EditProfileScreen(
                                            user: _user!.toJson(),
                                          ),
                                    ),
                                  );
                                  _loadAllData();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildProfileButton(
                                context,
                                "Share Profile",
                                onTap: () {
                                  // Share logic
                                },
                              ),
                            ),
                          ],
                        )
                      else
                        Row(
                          children: [
                            Expanded(
                              child: _buildProfileButton(
                                context,
                                _isFollowing ? "Following" : "Follow",
                                isPrimary: !_isFollowing,
                                onTap: _toggleFollow,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildProfileButton(
                                context,
                                "Message",
                                onTap: () {
                                  // Message logic
                                },
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ]),
            ),
          ];
        },
        body: Column(
          children: [
            TabBar(
              controller: _tabController,
              indicatorColor: Theme.of(context).primaryColor,
              tabs: const [
                Tab(icon: Icon(Icons.grid_on)),
                Tab(icon: Icon(Icons.people_outline)), // Followers
                Tab(icon: Icon(Icons.person_outline)), // Following
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPostsGrid(userPosts),
                  _UserListTab(userId: widget.userId, type: 'followers'),
                  _UserListTab(userId: widget.userId, type: 'following'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostsGrid(List posts) {
    if (posts.isEmpty) return const Center(child: Text("No posts yet"));

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      itemCount: posts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemBuilder: (context, index) {
        final post = posts[index];
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (_) => Scaffold(
                      appBar: AppBar(title: const Text("Post")),
                      body: SingleChildScrollView(child: PostCard(post: post)),
                    ),
              ),
            );
          },
          child: _buildPostItem(post),
        );
      },
    );
  }

  Widget _buildPostItem(dynamic post) {
    if (post.mediaType == 'image' && post.mediaUrl != null) {
      return CachedNetworkImage(imageUrl: post.mediaUrl!, fit: BoxFit.cover);
    } else if (post.mediaType == 'video') {
      return Container(
        color: Colors.black12,
        child: const Icon(Icons.play_circle_outline, color: Colors.white),
      );
    } else {
      return Container(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        child: Center(
          child: Text(
            post.caption ?? '',
            maxLines: 3,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10),
          ),
        ),
      );
    }
  }

  Widget _buildProfileButton(
    BuildContext context,
    String text, {
    VoidCallback? onTap,
    bool isPrimary = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    final bgColor =
        isPrimary
            ? primaryColor
            : (isDark ? Colors.grey[900] : Colors.grey[200]);

    final textColor =
        isPrimary
            ? (isDark ? Colors.black : Colors.white)
            : (isDark ? Colors.white : Colors.black);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    );
  }
}

class _UserListTab extends StatefulWidget {
  final String userId;
  final String type;

  const _UserListTab({required this.userId, required this.type});

  @override
  State<_UserListTab> createState() => _UserListTabState();
}

class _UserListTabState extends State<_UserListTab> {
  final DatabaseService _dbService = DatabaseService();
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    List<String> ids;
    if (widget.type == 'followers') {
      ids = await _dbService.getFollowerIds(widget.userId);
    } else {
      ids = await _dbService.getFollowingIds(widget.userId);
    }

    final List<Map<String, dynamic>> users = [];
    for (String id in ids) {
      final user = await _dbService.getUser(id);
      if (user != null) {
        users.add(user);
      }
    }

    if (mounted) {
      setState(() {
        _users = users;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_users.isEmpty) return Center(child: Text("No ${widget.type} yet"));

    return ListView.builder(
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundImage:
                user['profileImageUrl'] != null &&
                        user['profileImageUrl'].isNotEmpty
                    ? CachedNetworkImageProvider(user['profileImageUrl'])
                    : null,
            child:
                user['profileImageUrl'] == null ||
                        user['profileImageUrl'].isEmpty
                    ? const Icon(Icons.person)
                    : null,
          ),
          title: Text(user['username'] ?? 'Unknown'),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ProfileScreen(userId: user['id']),
              ),
            );
          },
        );
      },
    );
  }
}
