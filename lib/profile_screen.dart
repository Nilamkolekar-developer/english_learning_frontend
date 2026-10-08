import 'dart:convert';
import 'dart:typed_data';
import 'package:english_practice/admin_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'session.dart';


/// The signed-in user's profile, shared by every screen that shows the avatar.
final profile = ValueNotifier<Map<String, dynamic>?>(null);

Future<void> loadProfile() async {
  try {
    profile.value = Map<String, dynamic>.from(await Api.request('GET', '/me') as Map);
  } catch (_) {
    // keep the last known profile
  }
}

String initials(String? name) {
  final parts = (name ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

String fmtDate(dynamic iso) {
  final d = iso == null ? null : DateTime.tryParse(iso.toString())?.toLocal();
  if (d == null) return '-';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

const explainLanguages = {'en': 'English', 'hi': 'हिंदी (Hindi)', 'mr': 'मराठी (Marathi)'};

String cap(String? s) => (s == null || s.isEmpty) ? '-' : s[0].toUpperCase() + s.substring(1);

/// Downloaded profile photos, kept in memory. A new version number means a new photo.
class AvatarCache {
  static final _cache = <String, Future<Uint8List?>>{};

  static Future<Uint8List?> get(String userId, int version) {
    final key = '$userId:$version';
    return _cache.putIfAbsent(key, () async {
      final b = await Api.bytes('/users/$userId/avatar?v=$version');
      if (b == null) _cache.remove(key); // try again next time
      return b;
    });
  }
}

/// Round profile picture. Shows the photo when there is one, otherwise the initials.
class Avatar extends StatelessWidget {
  final String? name;
  final double radius;
  final String? userId;
  final int? version;
  const Avatar(this.name, {super.key, this.radius = 22, this.userId, this.version});

  @override
  Widget build(BuildContext context) {
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF0F7B63),
      child: Text(initials(name),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * 0.8)),
    );
    if (userId == null || version == null) return fallback;
    return FutureBuilder<Uint8List?>(
      future: AvatarCache.get(userId!, version!),
      builder: (_, snap) => snap.data == null
          ? fallback
          : CircleAvatar(radius: radius, backgroundImage: MemoryImage(snap.data!)),
    );
  }
}

/// Avatar for a user map from the API (needs 'name', the user id, and 'avatar_v').
Widget userAvatar(Map u, {double radius = 22, String idKey = 'id'}) => Avatar(
      u['name'] as String?,
      radius: radius,
      userId: u[idKey]?.toString(),
      version: u['avatar_v'] as int?,
    );

class ProfileScreen extends StatefulWidget {
  final Session session;
  const ProfileScreen(this.session, {super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _sub;
  Map<String, dynamic>? _stats;
  bool _busy = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _load() async {
    await Future.wait([
      loadProfile(),
      Api.request('GET', '/subscription/status')
          .then((v) { if (mounted) setState(() => _sub = Map<String, dynamic>.from(v as Map)); })
          .catchError((_) {}),
      Api.request('GET', '/progress')
          .then((v) { if (mounted) setState(() => _stats = Map<String, dynamic>.from(v as Map)); })
          .catchError((_) {}),
    ]);
  }

  Future<void> _setDiscoverable(bool v) async {
    setState(() => _busy = true);
    try {
      profile.value = Map<String, dynamic>.from(await Api.request('PATCH', '/me', body: {'discoverable': v}) as Map);
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Cannot reach the server');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePhoto() async {
    final hasPhoto = profile.value?['avatar_v'] != null;
    final mobile = defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(c, 'gallery'),
          ),
          if (mobile)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(c, 'camera'),
            ),
          if (hasPhoto)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Remove photo', style: TextStyle(color: Colors.red)),
              onTap: () => Navigator.pop(c, 'remove'),
            ),
        ]),
      ),
    );
    if (choice == null) return;

    XFile? file;
    if (choice != 'remove') {
      // Resized on the phone so uploads stay small (about 50 KB).
      file = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );
      if (file == null) return; // picker cancelled
    }

    setState(() => _uploading = true);
    try {
      if (file == null) {
        profile.value = Map<String, dynamic>.from(await Api.request('DELETE', '/me/avatar') as Map);
        _snack('Photo removed');
      } else {
        final bytes = await file.readAsBytes();
        final r = await Api.request('POST', '/me/avatar', body: {'image': base64Encode(bytes)});
        profile.value = Map<String, dynamic>.from(r as Map);
        _snack('Photo updated');
      }
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not update the photo');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _chooseExplainLanguage() async {
    final current = (profile.value?['explain_language'] as String?) ?? 'en';
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Explain my mistakes in', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Corrected sentences always stay in English.', style: TextStyle(color: Colors.black54)),
          ),
          for (final e in explainLanguages.entries)
            RadioListTile<String>(
              value: e.key,
              groupValue: current,
              title: Text(e.value),
              onChanged: (v) => Navigator.pop(c, v),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || choice == current) return;
    setState(() => _busy = true);
    try {
      final r = await Api.request('PATCH', '/me', body: {'explain_language': choice});
      profile.value = Map<String, dynamic>.from(r as Map);
      _snack('Explanations: ${explainLanguages[choice]}');
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Cannot reach the server');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPhonePublic(bool show) async {
    setState(() => _busy = true);
    try {
      final r = await Api.request('PATCH', '/me', body: {'phone_visibility': show ? 'public' : 'private'});
      profile.value = Map<String, dynamic>.from(r as Map);
      _snack(show ? 'Your mobile number is now shown on your profile' : 'Your mobile number is now private');
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Cannot reach the server');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final p = profile.value;
    if (p == null) return;
    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditProfileSheet(p),
    );
    if (updated != null) {
      profile.value = updated;
      _snack('Profile saved');
    }
  }

  Future<void> _signOut() async {
    final session = widget.session;
    Navigator.of(context).popUntil((r) => r.isFirst);
    profile.value = null;
    await session.signOut();
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text('Your conversations, progress and friends will be removed. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.request('DELETE', '/me');
      await _signOut();
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Cannot reach the server');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(label, style: const TextStyle(color: Colors.black54))),
            const SizedBox(width: 12),
            Flexible(child: Text(value, textAlign: TextAlign.right)),
          ]),
        );

    Widget section(String title, List<Widget> rows) => Card(
          color: Colors.white, elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              ...rows,
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Edit profile', onPressed: _edit),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: profile,
        builder: (_, p, __) {
          if (p == null) return const Center(child: CircularProgressIndicator());
          final active = _sub?['active'] == true;
          final streak = _stats?['streak'] ?? 0;
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
                // extra bottom space so the last buttons are not hidden behind the phone's navigation bar
                padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
                children: [
              Center(
                child: Tooltip(
                  message: 'Change profile photo',
                  child: GestureDetector(
                    onTap: _uploading ? null : _changePhoto,
                    child: Stack(children: [
                      userAvatar(p, radius: 48),
                      if (_uploading)
                        Positioned.fill(
                          child: Container(
                            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black38),
                            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
                          ),
                        ),
                      const Positioned(
                        right: 0,
                        bottom: 0,
                        child: CircleAvatar(
                          radius: 16,
                          backgroundColor: Color(0xFFE8A33D),
                          child: Icon(Icons.photo_camera, size: 17, color: Colors.black87),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Center(child: Text((p['name'] ?? '').toString(),
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
              Center(child: Text(p['username'] != null ? '@${p['username']}' : 'No username yet',
                  style: const TextStyle(color: Colors.black54))),
              const SizedBox(height: 20),
              section('Account', [
                row('Email', (p['email'] ?? '-').toString()),
                row('Mobile', p['phone'] == null
                    ? 'Not added'
                    : '${p['phone']}${p['phone_visibility'] == 'public' ? ' (public)' : ' (private)'}'),
              ]),
              section('Learning', [
                row('Level', cap(p['level'] as String?)),
                row('Goal', (p['goal'] as String?)?.isNotEmpty == true ? p['goal'] as String : 'Not set'),
                row('Member since', fmtDate(p['created_at'])),
              ]),
              if (p['is_admin'] == true)
                Card(
                  color: const Color(0xFFFFF6E5), elevation: 0,
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('Admin: manage videos'),
                    subtitle: const Text('Add, edit and hide listening videos'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminVideosScreen())),
                  ),
                ),
              Card(
                color: Colors.white, elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.translate),
                  title: const Text('Explain my mistakes in'),
                  subtitle: Text(explainLanguages[p['explain_language']] ?? 'English'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _chooseExplainLanguage,
                ),
              ),
              if (_stats != null)
                section('Activity', [
                  row('Conversations', '${_stats!['sessions']}'),
                  row('Streak', '$streak ${streak == 1 ? 'day' : 'days'}'),
                  row('Messages sent', '${_stats!['messages']}'),
                ]),
              if (_sub != null)
                section('Subscription', [
                  row('Plan', '₹${_sub!['monthly_price'] ?? 100} / month'),
                  row('Status', !active
                      ? cap(_sub!['status'] as String?)
                      : _sub!['auto_renew'] == true
                          ? 'Active'
                          : 'Autopay stopped'),
                  if (_sub!['current_period_end'] != null)
                    row(
                      !active
                          ? 'Ended on'
                          : _sub!['auto_renew'] == true
                              ? 'Next payment on'
                              : 'Access until',
                      fmtDate(_sub!['current_period_end']),
                    ),
                ]),
              Card(
                color: Colors.white, elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Privacy', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  if (p['phone'] != null)
                    SwitchListTile(
                      secondary: const Icon(Icons.phone_outlined),
                      title: const Text('Show my mobile number'),
                      subtitle: Text(p['phone_visibility'] == 'public'
                          ? 'Everyone who opens your profile can see it'
                          : 'Private. Only you can see it'),
                      value: p['phone_visibility'] == 'public',
                      onChanged: _busy ? null : _setPhonePublic,
                    ),
                  SwitchListTile(
                    secondary: const Icon(Icons.search),
                    title: const Text('Let others find me'),
                    subtitle: const Text('People can search your username and send you a friend request'),
                    value: p['discoverable'] == true,
                    onChanged: _busy ? null : _setDiscoverable,
                  ),
                ]),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _deleteAccount,
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete account'),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class EditProfileSheet extends StatefulWidget {
  final Map<String, dynamic> p;
  const EditProfileSheet(this.p, {super.key});
  @override
  State<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<EditProfileSheet> {
  late final _name = TextEditingController(text: widget.p['name'] as String? ?? '');
  late final _user = TextEditingController(text: widget.p['username'] as String? ?? '');
  late final _goal = TextEditingController(text: widget.p['goal'] as String? ?? '');
  // Stored as +91XXXXXXXXXX; the field shows only the 10 digits.
  late final _phone = TextEditingController(
      text: ((widget.p['phone'] as String?) ?? '').replaceFirst(RegExp(r'^\+91'), ''));
  late String _level = (widget.p['level'] as String?) ?? 'intermediate';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _user.dispose();
    _goal.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final user = _user.text.trim().toLowerCase();
    if (name.isEmpty) return setState(() => _error = 'Enter your name');
    if (user.isNotEmpty && !RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(user)) {
      return setState(() => _error = 'Username: 3 to 20 letters, numbers or _');
    }
    final phone = _phone.text.trim();
    if (phone.isNotEmpty && !RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) {
      return setState(() => _error = 'Enter a valid 10-digit mobile number');
    }
    setState(() { _saving = true; _error = null; });
    final body = <String, dynamic>{
      'name': name,
      'username': user.isEmpty ? null : user,
      'phone': phone.isEmpty ? null : phone,
      'level': _level,
      'goal': _goal.text.trim().isEmpty ? null : _goal.text.trim(),
    }..removeWhere((_, v) => v == null);
    try {
      final r = await Api.request('PATCH', '/me', body: body);
      if (mounted) Navigator.pop(context, Map<String, dynamic>.from(r as Map));
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach the server');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20,
          20 + MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Edit profile', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name')),
        const SizedBox(height: 12),
        TextField(
          controller: _user,
          decoration: const InputDecoration(labelText: 'Username', prefixText: '@',
              helperText: 'Friends find you by this name'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
          decoration: const InputDecoration(labelText: 'Mobile number', prefixText: '+91 '),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _level,
          decoration: const InputDecoration(labelText: 'English level'),
          items: const [
            DropdownMenuItem(value: 'beginner', child: Text('Beginner')),
            DropdownMenuItem(value: 'intermediate', child: Text('Intermediate')),
            DropdownMenuItem(value: 'advanced', child: Text('Advanced')),
          ],
          onChanged: (v) => setState(() => _level = v ?? _level),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _goal,
          decoration: const InputDecoration(labelText: 'Goal', hintText: 'e.g. Speak confidently in interviews'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save changes'),
        ),
        ]),
      ),
    );
  }
}