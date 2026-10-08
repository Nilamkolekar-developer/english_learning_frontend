import 'package:flutter/material.dart';
import 'api.dart';
import 'profile_screen.dart';

const _green = Color(0xFF0F7B63);

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

String _err(Object e) => e is ApiException ? e.message : 'Cannot reach the server';

/// Admin: all listening videos, published or hidden.
class AdminVideosScreen extends StatefulWidget {
  const AdminVideosScreen({super.key});
  @override
  State<AdminVideosScreen> createState() => _AdminVideosScreenState();
}

class _AdminVideosScreenState extends State<AdminVideosScreen> {
  List<Map>? _videos;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.request('GET', '/admin/videos');
      if (mounted) setState(() => _videos = (r as List).cast<Map>());
    } catch (e) {
      if (mounted) setState(() => _error = _err(e));
    }
  }

  Future<void> _open([Map? v]) async {
    final changed = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => VideoEditorScreen(video: v)));
    if (changed == true) _load();
  }

  Future<void> _togglePublished(Map v, bool on) async {
    try {
      await Api.request('PATCH', '/admin/videos/${v['id']}', body: {'published': on});
      _load();
    } catch (e) {
      if (mounted) _snack(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final videos = _videos;
    return Scaffold(
      appBar: AppBar(title: const Text('Manage videos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(),
        icon: const Icon(Icons.add),
        label: const Text('Add video'),
      ),
      body: videos == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: videos.isEmpty
                  ? ListView(padding: const EdgeInsets.all(32), children: const [
                      Text('No videos yet. Tap Add video and paste a YouTube link.',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                    ])
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(12, 8, 12, 96 + MediaQuery.of(context).padding.bottom),
                      itemCount: videos.length,
                      itemBuilder: (_, i) {
                        final v = videos[i];
                        final nq = (v['questions'] as List?)?.length ?? 0;
                        return Card(
                          color: Colors.white,
                          elevation: 0,
                          child: ListTile(
                            onTap: () => _open(v),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                'https://img.youtube.com/vi/${v['youtube_id']}/default.jpg',
                                width: 72, height: 54, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(width: 72, height: 54, color: Colors.black12),
                              ),
                            ),
                            title: Text((v['title'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${cap(v['level'] as String?)}, $nq questions, ${v['views']} learners'),
                            trailing: Switch(
                              value: v['published'] == true,
                              onChanged: (on) => _togglePublished(v, on),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

/// Add or edit one video and its questions.
class VideoEditorScreen extends StatefulWidget {
  final Map? video; // null = new video
  const VideoEditorScreen({super.key, this.video});
  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  late final _link = TextEditingController(text: (widget.video?['youtube_id'] ?? '').toString());
  late final _title = TextEditingController(text: (widget.video?['title'] ?? '').toString());
  late final _topic = TextEditingController(text: (widget.video?['topic'] ?? '').toString());
  late final _minutes = TextEditingController(text: widget.video?['minutes']?.toString() ?? '');
  late final _desc = TextEditingController(text: (widget.video?['description'] ?? '').toString());
  late String _level = (widget.video?['level'] as String?) ?? 'intermediate';
  late bool _published = widget.video?['published'] != false;
  late final List<Map<String, dynamic>> _questions = [
    for (final x in (widget.video?['questions'] as List? ?? const []))
      {
        'q': x['q'],
        'options': List<String>.from((x['options'] as List).map((e) => e.toString())),
        'answer': x['answer'],
        'explanation': x['explanation'] ?? '',
      }
  ];
  String? _videoId;
  String? _notice;
  bool _looking = false;
  bool _saving = false;
  bool _generating = false;

  bool get _isNew => widget.video == null;

  @override
  void initState() {
    super.initState();
    _videoId = widget.video?['youtube_id'] as String?;
  }

  @override
  void dispose() {
    for (final c in [_link, _title, _topic, _minutes, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _lookup() async {
    if (_link.text.trim().isEmpty) return;
    setState(() { _looking = true; _notice = null; });
    try {
      final r = await Api.request('POST', '/admin/videos/lookup', body: {'url': _link.text.trim()});
      setState(() {
        _videoId = r['youtube_id'] as String;
        if (_title.text.trim().isEmpty && r['title'] != null) _title.text = r['title'] as String;
        _notice = r['embeddable'] == false
            ? 'The owner of this video turned off embedding. It will not play inside the app. Pick another video.'
            : r['author'] != null
                ? 'Found: ${r['title']} by ${r['author']}'
                : null;
      });
    } catch (e) {
      if (mounted) _snack(context, _err(e));
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  Future<void> _generate() async {
    final transcript = TextEditingController();
    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) {
        final mq = MediaQuery.of(c);
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + mq.viewInsets.bottom + mq.padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Write questions from the transcript',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('On YouTube: open the video, tap ... then Show transcript, and copy the text.',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            TextField(
              controller: transcript,
              minLines: 6,
              maxLines: 10,
              decoration: const InputDecoration(hintText: 'Paste the transcript here'),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Write 4 questions')),
          ]),
        );
      },
    );
    final text = transcript.text;
    transcript.dispose();
    if (go != true || text.trim().isEmpty) return;
    setState(() => _generating = true);
    try {
      final r = await Api.request('POST', '/admin/videos/generate-questions',
          body: {'transcript': text, 'level': _level, 'count': 4});
      final qs = (r['questions'] as List).cast<Map>();
      setState(() {
        for (final x in qs) {
          _questions.add({
            'q': x['q'],
            'options': List<String>.from((x['options'] as List).map((e) => e.toString())),
            'answer': x['answer'],
            'explanation': x['explanation'] ?? '',
          });
        }
      });
      if (mounted) _snack(context, 'Added ${qs.length} questions. Check them before saving.');
    } catch (e) {
      if (mounted) _snack(context, _err(e));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _editQuestion([int? index]) async {
    final existing = index == null ? null : _questions[index];
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _QuestionDialog(existing),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _questions.add(result);
      } else {
        _questions[index] = result;
      }
    });
  }

  Future<void> _save() async {
    if (_videoId == null && _link.text.trim().isEmpty) return _snack(context, 'Paste a YouTube link');
    if (_title.text.trim().isEmpty) return _snack(context, 'Enter a title');
    setState(() => _saving = true);
    final body = {
      'youtube': _link.text.trim().isNotEmpty ? _link.text.trim() : _videoId,
      'title': _title.text.trim(),
      'level': _level,
      'topic': _topic.text.trim(),
      'minutes': int.tryParse(_minutes.text.trim()) ?? 0,
      'description': _desc.text.trim(),
      'questions': _questions,
      'published': _published,
    };
    try {
      if (_isNew) {
        await Api.request('POST', '/admin/videos', body: body);
      } else {
        await Api.request('PATCH', '/admin/videos/${widget.video!['id']}', body: body);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _snack(context, _err(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this video?'),
        content: const Text('Learners lose their scores for it. To hide it for now, turn off Published instead.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Api.request('DELETE', '/admin/videos/${widget.video!['id']}');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) _snack(context, _err(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Add video' : 'Edit video'),
        actions: [
          if (!_isNew)
            IconButton(tooltip: 'Delete video', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          TextField(
            controller: _link,
            onSubmitted: (_) => _lookup(),
            decoration: InputDecoration(
              labelText: 'YouTube link',
              hintText: 'https://youtu.be/...',
              suffixIcon: _looking
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : TextButton(onPressed: _lookup, child: const Text('Fetch')),
            ),
          ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_notice!,
                  style: TextStyle(color: _notice!.startsWith('The owner') ? Colors.red : _green)),
            ),
          if (_videoId != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network('https://img.youtube.com/vi/$_videoId/hqdefault.jpg', fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: Colors.black12)),
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _level,
                decoration: const InputDecoration(labelText: 'Level'),
                items: const [
                  DropdownMenuItem(value: 'beginner', child: Text('Beginner')),
                  DropdownMenuItem(value: 'intermediate', child: Text('Intermediate')),
                  DropdownMenuItem(value: 'advanced', child: Text('Advanced')),
                ],
                onChanged: (v) => setState(() => _level = v ?? _level),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _minutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minutes'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _topic, decoration: const InputDecoration(labelText: 'Topic', hintText: 'e.g. Travel')),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Short description for learners'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Published'),
            subtitle: const Text('Learners can see it in the Listen tab'),
            value: _published,
            onChanged: (v) => setState(() => _published = v),
          ),
          const Divider(height: 28),
          Row(children: [
            Expanded(child: Text('Questions (${_questions.length})', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            TextButton.icon(onPressed: () => _editQuestion(), icon: const Icon(Icons.add), label: const Text('Add')),
          ]),
          OutlinedButton.icon(
            onPressed: _generating ? null : _generate,
            icon: _generating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome),
            label: Text(_generating ? 'Writing questions...' : 'Write questions with AI from the transcript'),
          ),
          const SizedBox(height: 8),
          if (_questions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No questions. Learners will see a Mark as watched button instead.',
                  style: TextStyle(color: Colors.black54)),
            ),
          for (var i = 0; i < _questions.length; i++)
            Card(
              color: Colors.white,
              elevation: 0,
              margin: const EdgeInsets.only(top: 8),
              child: ListTile(
                onTap: () => _editQuestion(i),
                title: Text('${i + 1}. ${_questions[i]['q']}'),
                subtitle: Text('Answer: ${(_questions[i]['options'] as List)[_questions[i]['answer'] as int]}'),
                trailing: IconButton(
                  tooltip: 'Remove question',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _questions.removeAt(i)),
                ),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isNew ? 'Add video' : 'Save changes'),
          ),
        ],
      ),
    );
  }
}

/// Write or edit one multiple-choice question.
class _QuestionDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _QuestionDialog(this.existing);
  @override
  State<_QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<_QuestionDialog> {
  late final _q = TextEditingController(text: (widget.existing?['q'] ?? '').toString());
  late final List<TextEditingController> _opts = [
    for (var i = 0; i < 3; i++)
      TextEditingController(
          text: i < ((widget.existing?['options'] as List?)?.length ?? 0)
              ? (widget.existing!['options'] as List)[i].toString()
              : ''),
  ];
  late final _expl = TextEditingController(text: (widget.existing?['explanation'] ?? '').toString());
  late int _answer = (widget.existing?['answer'] as int?) ?? 0;
  String? _error;

  @override
  void dispose() {
    _q.dispose();
    _expl.dispose();
    for (final c in _opts) {
      c.dispose();
    }
    super.dispose();
  }

  void _done() {
    final options = _opts.map((c) => c.text.trim()).toList();
    if (_q.text.trim().isEmpty || options.where((o) => o.isNotEmpty).length < 2 || options[_answer].isEmpty) {
      setState(() => _error = 'Write the question, at least 2 options, and pick the correct one');
      return;
    }
    // Drop empty options but keep the correct answer's position right
    final kept = <String>[];
    var answer = 0;
    for (var i = 0; i < options.length; i++) {
      if (options[i].isEmpty) continue;
      if (i == _answer) answer = kept.length;
      kept.add(options[i]);
    }
    Navigator.pop(context, {'q': _q.text.trim(), 'options': kept, 'answer': answer, 'explanation': _expl.text.trim()});
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New question' : 'Edit question'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _q, decoration: const InputDecoration(labelText: 'Question')),
          const SizedBox(height: 8),
          for (var i = 0; i < 3; i++)
            Row(children: [
              Radio<int>(value: i, groupValue: _answer, onChanged: (v) => setState(() => _answer = v!)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(controller: _opts[i], decoration: InputDecoration(labelText: 'Option ${i + 1}')),
                ),
              ),
            ]),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Tap the circle next to the correct option.', style: TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          const SizedBox(height: 8),
          TextField(controller: _expl, decoration: const InputDecoration(labelText: 'Explanation (optional)')),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _done, child: const Text('Done')),
      ],
    );
  }
}