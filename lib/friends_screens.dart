import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'profile_screen.dart';

String _subtitle(Map u) => [
      if (u['username'] != null) '@${u['username']}',
      if (u['level'] != null) cap(u['level'] as String?),
    ].join(', ');

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class FriendsTab extends StatefulWidget {
  const FriendsTab({super.key});
  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  List<Map> _friends = [];
  List<Map> _requests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final r = await Future.wait([Api.request('GET', '/friends'), Api.request('GET', '/friends/requests')]);
      if (mounted) {
        setState(() {
          _friends = (r[0] as List).cast<Map>();
          _requests = (r[1] as List).cast<Map>();
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Cannot reach the server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(Map r, bool accept) async {
    try {
      await Api.request('POST', '/friends/requests/${r['id']}/${accept ? 'accept' : 'decline'}');
      if (mounted) _snack(context, accept ? 'You and ${r['name']} are now friends' : 'Request declined');
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    } catch (_) {
      if (mounted) _snack(context, 'Cannot reach the server');
    }
    _load();
  }

  Future<void> _openChat(Map f) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => FriendChatScreen(f)));
    _load(); // the friend may have been blocked
  }

  /// A pull-to-refresh list that still scrolls (and refreshes) when empty.
  Widget _list(int count, String empty, Widget Function(int) item) => RefreshIndicator(
        onRefresh: _load,
        child: count == 0
            ? ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(32), children: [
                Text(empty, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
              ])
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: count,
                itemBuilder: (_, i) => item(i),
              ),
      );

  @override
  Widget build(BuildContext context) {
    Widget body(Widget child) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      if (_error != null) {
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!),
            TextButton(onPressed: _load, child: const Text('Try again')),
          ]),
        );
      }
      return child;
    }

    return DefaultTabController(
      length: 3,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
          child: Row(children: [
            Expanded(
              child: Text('Friends',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
          ]),
        ),
        TabBar(tabs: [
          const Tab(text: 'Friends'),
          Tab(text: _requests.isEmpty ? 'Requests' : 'Requests (${_requests.length})'),
          const Tab(text: 'Find'),
        ]),
        Expanded(
          child: TabBarView(children: [
            body(_list(_friends.length, 'No friends yet. Find people by username in the Find tab.', (i) {
              final f = _friends[i];
              return ListTile(
                leading: userAvatar(f),
                title: Text((f['name'] ?? '').toString()),
                subtitle: Text(_subtitle(f)),
                trailing: const Icon(Icons.chat_bubble_outline),
                onTap: () => _openChat(f),
              );
            })),
            body(_list(_requests.length, 'No friend requests right now.', (i) {
              final r = _requests[i];
              return ListTile(
                leading: userAvatar(r, idKey: 'user_id'),
                title: Text((r['name'] ?? '').toString()),
                subtitle: Text(_subtitle(r)),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => UserProfileScreen(r['user_id'].toString(), preview: r))),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    onPressed: () => _respond(r, false),
                    icon: const Icon(Icons.close),
                    tooltip: 'Decline',
                  ),
                  IconButton.filled(
                    onPressed: () => _respond(r, true),
                    icon: const Icon(Icons.check),
                    tooltip: 'Accept',
                  ),
                ]),
              );
            })),
            FindPeople(onSent: _load),
          ]),
        ),
      ]),
    );
  }
}

class FindPeople extends StatefulWidget {
  final VoidCallback onSent;
  const FindPeople({super.key, required this.onSent});
  @override
  State<FindPeople> createState() => _FindPeopleState();
}

class _FindPeopleState extends State<FindPeople> {
  final _c = TextEditingController();
  Timer? _debounce;
  List<Map> _results = [];
  final _sent = <String>{};
  bool _searching = false;
  String _last = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(v.trim().toLowerCase()));
  }

  Future<void> _search(String text) async {
    _last = text;
    if (text.length < 2) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final r = await Api.request('GET', '/users/search?q_=${Uri.encodeQueryComponent(text)}');
      if (mounted && text == _last) setState(() => _results = (r as List).cast<Map>());
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    } catch (_) {
      if (mounted) _snack(context, 'Cannot reach the server');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(Map u) async {
    try {
      await Api.request('POST', '/friends/requests', body: {'to_user_id': u['id']});
      if (!mounted) return;
      setState(() => _sent.add(u['id'].toString()));
      _snack(context, 'Request sent to ${u['name']}');
      widget.onSent();
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    } catch (_) {
      if (mounted) _snack(context, 'Cannot reach the server');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          controller: _c,
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search by username',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : null,
          ),
        ),
      ),
      ValueListenableBuilder(
        valueListenable: profile,
        builder: (_, p, __) => p != null && p['username'] == null
            ? const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Set a username in your profile so friends can find you too.',
                    style: TextStyle(color: Colors.black54)),
              )
            : const SizedBox.shrink(),
      ),
      Expanded(
        child: _results.isEmpty
            ? Center(
                child: Text(_c.text.trim().length < 2 ? 'Type at least 2 letters' : 'No one found with that username',
                    style: const TextStyle(color: Colors.black54)),
              )
            : ListView.builder(
                itemCount: _results.length,
                itemBuilder: (_, i) {
                  final u = _results[i];
                  final sent = _sent.contains(u['id'].toString());
                  return ListTile(
                    leading: userAvatar(u),
                    title: Text((u['name'] ?? '').toString()),
                    subtitle: Text(_subtitle(u)),
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => UserProfileScreen(u['id'].toString(), preview: u))),
                    trailing: sent
                        ? const Text('Sent', style: TextStyle(color: Colors.black54))
                        : OutlinedButton(onPressed: () => _add(u), child: const Text('Add')),
                  );
                },
              ),
      ),
    ]);
  }
}

class FriendChatScreen extends StatefulWidget {
  final Map friend;
  const FriendChatScreen(this.friend, {super.key});
  @override
  State<FriendChatScreen> createState() => _FriendChatScreenState();
}

class _FriendChatScreenState extends State<FriendChatScreen> {
  final _c = TextEditingController();
  List<Map> _msgs = []; // newest first, as the server returns them
  Timer? _poll;
  bool _loading = true;
  bool _sending = false;

  String get _fid => widget.friend['id'].toString();
  String get _name => (widget.friend['name'] ?? 'Friend').toString();

  @override
  void initState() {
    super.initState();
    _fetch();
    // TODO: replace polling with a WebSocket for real-time chat.
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _fetch());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _c.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final r = (await Api.request('GET', '/friends/$_fid/messages') as List).cast<Map>();
      if (mounted) setState(() => _msgs = r);
    } catch (_) {
      // try again on the next poll
    } finally {
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _c.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await Api.request('POST', '/friends/$_fid/messages', body: {'content': text});
      _c.clear();
      await _fetch();
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    } catch (_) {
      if (mounted) _snack(context, 'Cannot reach the server');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _block() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Block $_name?'),
        content: const Text('You will no longer be friends, and they cannot message you or find you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.request('POST', '/blocks', body: {'user_id': _fid});
      if (!mounted) return;
      _snack(context, '$_name is blocked');
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    } catch (_) {
      if (mounted) _snack(context, 'Cannot reach the server');
    }
  }

  Future<void> _report() async {
    final reason = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Report $_name'),
        content: TextField(
          controller: reason,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'What happened?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, reason.text.trim()), child: const Text('Send report')),
        ],
      ),
    );
    reason.dispose();
    if (text == null || text.isEmpty) return;
    try {
      await Api.request('POST', '/reports', body: {'user_id': _fid, 'reason': text});
      if (mounted) _snack(context, 'Report sent. Thank you.');
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    } catch (_) {
      if (mounted) _snack(context, 'Cannot reach the server');
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = profile.value?['id']?.toString();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => UserProfileScreen(_fid, preview: widget.friend, fromChat: true))),
          child: Row(children: [
            userAvatar(widget.friend, radius: 16),
            const SizedBox(width: 10),
            Expanded(child: Text(_name, overflow: TextOverflow.ellipsis)),
          ]),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => v == 'block' ? _block() : _report(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: Text('Report')),
              PopupMenuItem(value: 'block', child: Text('Block')),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _msgs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text('Say hello to $_name and practise English together.',
                            textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                      ),
                    )
                  : ListView.builder(
                      reverse: true, // newest message at the bottom
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _msgs.length,
                      itemBuilder: (_, i) {
                        final m = _msgs[i];
                        final mine = m['from_user'].toString() == myId;
                        return Align(
                          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(12),
                            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
                            decoration: BoxDecoration(
                              color: mine ? const Color(0xFF0F7B63) : Colors.white,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text((m['content'] ?? '').toString(),
                                style: TextStyle(color: mine ? Colors.white : Colors.black87)),
                          ),
                        );
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  onSubmitted: (_) => _send(),
                  decoration: InputDecoration(hintText: 'Message $_name'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: const Color(0xFFE8A33D), foregroundColor: Colors.black87),
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send),
                tooltip: 'Send',
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}


/// Another user's profile. Shows the mobile number only when their privacy setting allows it.
class UserProfileScreen extends StatefulWidget {
  final String userId;
  final Map? preview; // shown while the full profile loads
  final bool fromChat;
  const UserProfileScreen(this.userId, {super.key, this.preview, this.fromChat = false});
  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  Map<String, dynamic>? _u;
  String? _error;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.request('GET', '/users/${widget.userId}');
      if (mounted) setState(() => _u = Map<String, dynamic>.from(r as Map));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Cannot reach the server');
    }
  }

  Future<void> _add() async {
    try {
      await Api.request('POST', '/friends/requests', body: {'to_user_id': widget.userId});
      if (!mounted) return;
      setState(() => _sent = true);
      _snack(context, 'Friend request sent');
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    } catch (_) {
      if (mounted) _snack(context, 'Cannot reach the server');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final u = _u ?? (widget.preview == null ? null : Map<String, dynamic>.from(widget.preview!));
    final phone = _u?['phone'] as String?;

    Widget row(IconData icon, String label, String value, {Widget? trailing}) => ListTile(
          leading: Icon(icon),
          title: Text(label, style: const TextStyle(fontSize: 13, color: Colors.black54)),
          subtitle: Text(value, style: const TextStyle(fontSize: 16, color: Colors.black87)),
          trailing: trailing,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: u == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
              children: [
              Center(child: userAvatar(u, radius: 48, idKey: u.containsKey('user_id') && _u == null ? 'user_id' : 'id')),
              const SizedBox(height: 12),
              Center(
                child: Text((u['name'] ?? '').toString(),
                    style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              if (u['username'] != null)
                Center(child: Text('@${u['username']}', style: const TextStyle(color: Colors.black54))),
              const SizedBox(height: 20),
              Card(
                color: Colors.white, elevation: 0,
                child: Column(children: [
                  row(Icons.school_outlined, 'English level', cap(u['level'] as String?)),
                  if (_u?['created_at'] != null)
                    row(Icons.calendar_today_outlined, 'Member since', fmtDate(_u!['created_at'])),
                  if (phone != null)
                    row(
                      Icons.phone_outlined,
                      'Mobile',
                      phone,
                      trailing: IconButton(
                        tooltip: 'Copy number',
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: phone));
                          _snack(context, 'Number copied');
                        },
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 16),
              if (_u != null && _u!['is_me'] != true)
                if (_u!['is_friend'] == true)
                  FilledButton.icon(
                    onPressed: () {
                      if (widget.fromChat) {
                        Navigator.pop(context);
                      } else {
                        Navigator.pushReplacement(
                            context, MaterialPageRoute(builder: (_) => FriendChatScreen(_u!)));
                      }
                    },
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Message'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _sent ? null : _add,
                    icon: Icon(_sent ? Icons.check : Icons.person_add_alt),
                    label: Text(_sent ? 'Request sent' : 'Add friend'),
                  ),
            ]),
    );
  }
}