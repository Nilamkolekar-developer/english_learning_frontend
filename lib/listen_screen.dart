import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'api.dart';
import 'profile_screen.dart';

const _green = Color(0xFF0F7B63);
const _deepGreen = Color(0xFF0A5C4A);

String _levelLabel(String? l) => cap(l);

/// The Listen tab: English listening videos, filtered by level.
class ListenTab extends StatefulWidget {
  const ListenTab({super.key});
  @override
  State<ListenTab> createState() => _ListenTabState();
}

class _ListenTabState extends State<ListenTab> {
  List<Map> _videos = [];
  bool _loading = true;
  String? _error;
  String? _level; // null = all levels
  bool _levelPicked = false;

  @override
  void initState() {
    super.initState();
    // Start on the learner's own level once the profile is known.
    _level = profile.value?['level'] as String?;
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final path = _level == null ? '/listening' : '/listening?level=$_level';
      final r = await Api.request('GET', path);
      if (mounted) setState(() => _videos = (r as List).cast<Map>());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Cannot reach the server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pick(String? level) {
    setState(() {
      _level = level;
      _levelPicked = true;
      _loading = true;
    });
    _load();
  }

  Future<void> _open(Map v) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => VideoScreen(v['id'] as int)));
    _load(); // refresh done / score
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    // If the profile arrived after this tab opened, follow the learner's level.
    if (!_levelPicked && _level == null && profile.value?['level'] != null && _videos.isEmpty && !_loading) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pick(profile.value?['level'] as String?));
    }

    Widget chip(String? level, String label) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _level == level,
            onSelected: (_) => _pick(level),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: Text('Listen', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Text('Watch short videos, then answer a few questions.', style: TextStyle(color: Colors.black54)),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 8),
        child: Row(children: [
          chip(null, 'All'),
          chip('beginner', 'Beginner'),
          chip('intermediate', 'Intermediate'),
          chip('advanced', 'Advanced'),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error!),
                      TextButton(onPressed: _load, child: const Text('Try again')),
                    ]),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _videos.isEmpty
                        ? ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(32), children: [
                            Text(
                              _level == null
                                  ? 'No videos yet. New listening lessons are on the way.'
                                  : 'No ${_levelLabel(_level).toLowerCase()} videos yet. Try All.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.black54),
                            ),
                          ])
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                            itemCount: _videos.length,
                            itemBuilder: (_, i) => _VideoCard(_videos[i], onTap: () => _open(_videos[i])),
                          ),
                  ),
      ),
    ]);
  }
}

class _VideoCard extends StatelessWidget {
  final Map v;
  final VoidCallback onTap;
  const _VideoCard(this.v, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final done = v['done'] == true;
    final total = v['total'] as int?;
    final meta = [
      _levelLabel(v['level'] as String?),
      if (v['minutes'] != null) '${v['minutes']} min',
      if (v['topic'] != null) v['topic'].toString(),
    ].join(', ');

    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(fit: StackFit.expand, children: [
              Image.network(
                'https://img.youtube.com/vi/${v['youtube_id']}/hqdefault.jpg',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: _green.withValues(alpha: .15)),
              ),
              const Center(
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.play_arrow, color: Colors.white, size: 32),
                ),
              ),
              if (done)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      total != null && total > 0 ? 'Score ${v['score']}/$total' : 'Watched',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((v['title'] ?? '').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 4),
              Text(meta, style: const TextStyle(color: Colors.black54)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// One video with its questions.
class VideoScreen extends StatefulWidget {
  final int videoId;
  const VideoScreen(this.videoId, {super.key});
  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  Map<String, dynamic>? _v;
  YoutubePlayerController? _player;
  String? _error;
  final Map<int, int> _picked = {}; // question index -> option index
  Map<String, dynamic>? _result; // after "Check answers"
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _player?.close();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = Map<String, dynamic>.from(await Api.request('GET', '/listening/${widget.videoId}') as Map);
      if (!mounted) return;
      setState(() {
        _v = r;
        _player = YoutubePlayerController.fromVideoId(
          videoId: r['youtube_id'] as String,
          autoPlay: false,
          params: const YoutubePlayerParams(showFullscreenButton: true, strictRelatedVideos: true),
        );
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Cannot reach the server');
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _check(int count) async {
    if (_picked.length < count) {
      _snack('Answer all ${count == 1 ? 'the question' : '$count questions'} first');
      return;
    }
    setState(() => _sending = true);
    try {
      final r = await Api.request('POST', '/listening/${widget.videoId}/answers',
          body: {'answers': [for (var i = 0; i < count; i++) _picked[i]]});
      if (mounted) setState(() => _result = Map<String, dynamic>.from(r as Map));
    } on ApiException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Cannot reach the server');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _markWatched() async {
    try {
      await Api.request('POST', '/listening/${widget.videoId}/watched');
      if (mounted) setState(() => _v!['done'] = true);
      _snack('Marked as watched');
    } catch (_) {
      _snack('Cannot reach the server');
    }
  }

  void _tryAgain() => setState(() {
        _result = null;
        _picked.clear();
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final v = _v;
    if (v == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator()),
      );
    }
    final qs = (v['questions'] as List).cast<Map>();
    final results = (_result?['results'] as List?)?.cast<Map>();

    return Scaffold(
      appBar: AppBar(title: Text((v['title'] ?? '').toString(), overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: EdgeInsets.only(bottom: 24 + MediaQuery.of(context).padding.bottom),
        children: [
          if (_player != null) YoutubePlayer(controller: _player!, aspectRatio: 16 / 9),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text((v['title'] ?? '').toString(), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                [
                  _levelLabel(v['level'] as String?),
                  if (v['minutes'] != null) '${v['minutes']} min',
                  if (v['topic'] != null) v['topic'].toString(),
                ].join(', '),
                style: const TextStyle(color: Colors.black54),
              ),
              if ((v['description'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Text(v['description'] as String, style: const TextStyle(height: 1.4)),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: _green.withValues(alpha: .08), borderRadius: BorderRadius.circular(14)),
                child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.headphones_outlined, color: _deepGreen),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Watch once without subtitles and try to follow. Then watch again with subtitles (CC) on.',
                      style: TextStyle(height: 1.35),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              if (qs.isEmpty)
                FilledButton.icon(
                  onPressed: v['done'] == true ? null : _markWatched,
                  icon: const Icon(Icons.check),
                  label: Text(v['done'] == true ? 'Watched' : 'Mark as watched'),
                )
              else ...[
                Row(children: [
                  Expanded(
                    child: Text('Check your understanding',
                        style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (_result == null && v['total'] != null)
                    Text('Last score ${v['score']}/${v['total']}', style: const TextStyle(color: Colors.black54)),
                ]),
                const SizedBox(height: 8),
                for (var i = 0; i < qs.length; i++) _question(i, qs[i], results?[i]),
                const SizedBox(height: 8),
                if (_result == null)
                  FilledButton(
                    onPressed: _sending ? null : () => _check(qs.length),
                    child: _sending
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Check answers'),
                  )
                else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(16)),
                    child: Text(
                      'You got ${_result!['score']} of ${_result!['total']} right'
                      '${_result!['score'] == _result!['total'] ? '. Excellent listening!' : '. Watch again and try once more.'}',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: _tryAgain, child: const Text('Try again')),
                ],
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _question(int i, Map qn, Map? res) {
    final options = (qn['options'] as List).map((e) => e.toString()).toList();
    final answer = res?['answer'] as int?;
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('${i + 1}. ${qn['q']}', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          for (var o = 0; o < options.length; o++)
            RadioListTile<int>(
              dense: true,
              value: o,
              groupValue: _picked[i],
              onChanged: res != null ? null : (val) => setState(() => _picked[i] = val!),
              title: Text(options[o]),
              secondary: res == null
                  ? null
                  : o == answer
                      ? const Icon(Icons.check_circle, color: _green)
                      : o == _picked[i]
                          ? const Icon(Icons.cancel, color: Color(0xFFB3261E))
                          : null,
            ),
          if (res != null && (res['explanation'] as String?)?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Text(res['explanation'] as String, style: const TextStyle(color: Colors.black54)),
            ),
        ]),
      ),
    );
  }
}