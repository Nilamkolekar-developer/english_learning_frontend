import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'api.dart';
import 'app_screens.dart';
import 'profile_screen.dart';

const _green = Color(0xFF0F7B63);
const _deepGreen = Color(0xFF0A5C4A);
const _amber = Color(0xFFE8A33D);

void _snack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

String _friendlyError(Object e) => e is ApiException ? e.message : 'Cannot reach the server';

// ======================================================================
// Conversation history
// ======================================================================

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.request('GET', '/sessions/history');
      if (mounted) setState(() => _rows = (r as List).cast<Map>());
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return Scaffold(
      appBar: AppBar(title: const Text('Past conversations')),
      body: rows == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: rows.isEmpty
                  ? ListView(padding: const EdgeInsets.all(32), children: const [
                      Text('Finished conversations appear here. Tap End after a chat to save it with feedback.',
                          textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                    ])
                  : ListView.separated(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(context).padding.bottom),
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final r = rows[i];
                        final sc = (r['scenario'] as Map?) ?? const {};
                        final mistakes = r['n_mistakes'] as int? ?? 0;
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            leading: Icon(scenarioIcons[sc['key']] ?? Icons.forum_outlined, color: _green),
                            title: Text((sc['title'] ?? 'Free talk').toString(),
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '${fmtDate(r['ended_at'])}, ${r['n_messages']} messages, '
                              '${mistakes == 0 ? 'no mistakes' : '$mistakes to practise'}',
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => ConversationDetailScreen(r['id'].toString()))),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class ConversationDetailScreen extends StatefulWidget {
  final String sessionId;
  const ConversationDetailScreen(this.sessionId, {super.key});
  @override
  State<ConversationDetailScreen> createState() => _ConversationDetailScreenState();
}

class _ConversationDetailScreenState extends State<ConversationDetailScreen> {
  Map<String, dynamic>? _s;
  String? _error;

  @override
  void initState() {
    super.initState();
    Api.request('GET', '/sessions/${widget.sessionId}').then((r) {
      if (mounted) setState(() => _s = Map<String, dynamic>.from(r as Map));
    }).catchError((Object e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator()),
      );
    }
    final sc = (s['scenario'] as Map?) ?? const {};
    final msgs = (s['messages'] as List).cast<Map>();
    final analysis = s['analysis'] as Map?;
    final maxW = MediaQuery.of(context).size.width * .78;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${sc['title'] ?? 'Conversation'}, ${fmtDate(s['ended_at'])}'),
          bottom: const TabBar(tabs: [Tab(text: 'Feedback'), Tab(text: 'Chat')]),
        ),
        body: TabBarView(children: [
          ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
            children: [
              if (analysis != null)
                AnalysisCards(analysis)
              else
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Feedback was not saved for this older conversation.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                ),
            ],
          ),
          ListView.builder(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.of(context).padding.bottom),
            itemCount: msgs.length,
            itemBuilder: (_, i) {
              final m = msgs[i];
              final user = m['sender'] == 'USER';
              return Align(
                alignment: user ? Alignment.centerRight : Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: user ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(maxWidth: maxW),
                      decoration: BoxDecoration(
                        color: user ? _green : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text((m['content'] ?? '').toString(),
                          style: TextStyle(color: user ? Colors.white : Colors.black87)),
                    ),
                    if (user && m['corrected'] != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        constraints: BoxConstraints(maxWidth: maxW),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF6E5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _amber),
                        ),
                        child: Text('Better: ${m['corrected']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                  ],
                ),
              );
            },
          ),
        ]),
      ),
    );
  }
}

// ======================================================================
// Personal practice from mistakes
// ======================================================================

class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});
  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  Map<String, dynamic>? _set;
  String? _error;
  final Map<int, int> _picked = {};
  Map<String, dynamic>? _result;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _set = null;
      _error = null;
      _result = null;
      _picked.clear();
    });
    try {
      final r = await Api.request('POST', '/practice/start');
      if (mounted) setState(() => _set = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    }
  }

  Future<void> _check(int count) async {
    if (_picked.length < count) {
      _snack(context, 'Answer all $count questions first');
      return;
    }
    setState(() => _sending = true);
    try {
      final r = await Api.request('POST', '/practice/${_set!['id']}/answers',
          body: {'answers': [for (var i = 0; i < count; i++) _picked[i]]});
      if (mounted) setState(() => _result = Map<String, dynamic>.from(r as Map));
      progressRefresh.value++;
    } catch (e) {
      if (mounted) _snack(context, _friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final set = _set;
    if (set == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Practice')),
        body: Center(
          child: _error != null
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  Padding(padding: const EdgeInsets.all(16), child: Text(_error!, textAlign: TextAlign.center)),
                  TextButton(onPressed: _start, child: const Text('Try again')),
                ])
              : const Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Making exercises from your mistakes...'),
                ]),
        ),
      );
    }
    final ex = (set['exercises'] as List).cast<Map>();
    final results = (_result?['results'] as List?)?.cast<Map>();

    return Scaffold(
      appBar: AppBar(title: const Text('Practice')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + MediaQuery.of(context).padding.bottom),
        children: [
          Text(cap(set['title'] as String?), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            set['category'] != null
                ? 'Built from the mistakes in your recent conversations.'
                : 'Finish a few conversations and these exercises will focus on your own mistakes.',
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < ex.length; i++)
            QuizQuestion(
              index: i,
              question: ex[i]['q'].toString(),
              options: (ex[i]['options'] as List).map((e) => e.toString()).toList(),
              picked: _picked[i],
              result: results?[i],
              onPick: (v) => setState(() => _picked[i] = v),
            ),
          const SizedBox(height: 8),
          if (_result == null)
            FilledButton(
              onPressed: _sending ? null : () => _check(ex.length),
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
                '${_result!['score'] == _result!['total'] ? '. Well done!' : '. Read the explanations and try a new set.'}',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _start, child: const Text('New set of exercises')),
          ],
        ],
      ),
    );
  }
}

/// A multiple-choice question; shows right/wrong marks once [result] is set.
class QuizQuestion extends StatelessWidget {
  final int index;
  final String question;
  final List<String> options;
  final int? picked;
  final Map? result;
  final ValueChanged<int> onPick;
  const QuizQuestion({
    super.key,
    required this.index,
    required this.question,
    required this.options,
    required this.picked,
    required this.result,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final answer = result?['answer'] as int?;
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('${index + 1}. $question', style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          for (var o = 0; o < options.length; o++)
            RadioListTile<int>(
              dense: true,
              value: o,
              groupValue: picked,
              onChanged: result != null ? null : (v) => onPick(v!),
              title: Text(options[o]),
              secondary: result == null
                  ? null
                  : o == answer
                      ? const Icon(Icons.check_circle, color: _green)
                      : o == picked
                          ? const Icon(Icons.cancel, color: Color(0xFFB3261E))
                          : null,
            ),
          if (result != null && (result!['explanation'] as String?)?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Text(result!['explanation'] as String, style: const TextStyle(color: Colors.black54)),
            ),
        ]),
      ),
    );
  }
}

// ======================================================================
// Words (flashcards)
// ======================================================================

class WordsScreen extends StatefulWidget {
  const WordsScreen({super.key});
  @override
  State<WordsScreen> createState() => _WordsScreenState();
}

class _WordsScreenState extends State<WordsScreen> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.request('GET', '/vocab');
      if (mounted) setState(() => _data = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    }
  }

  Future<void> _review() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ReviewScreen()));
    _load();
    progressRefresh.value++;
  }

  Future<void> _add() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddCardSheet(),
    );
    if (added == true) _load();
  }

  Future<void> _delete(Map item) async {
    try {
      await Api.request('DELETE', '/vocab/${item['id']}');
      _load();
    } catch (e) {
      if (mounted) _snack(context, _friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final due = d?['due'] as int? ?? 0;
    final items = (d?['items'] as List?)?.cast<Map>() ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('My words')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add word'),
      ),
      body: d == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 96 + MediaQuery.of(context).padding.bottom),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(22)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(due == 0 ? 'All caught up' : '$due ${due == 1 ? 'card' : 'cards'} to review',
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${d['total']} words saved, ${d['learned']} learned',
                          style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 14),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _deepGreen),
                        onPressed: due == 0 ? null : _review,
                        child: Text(due == 0 ? 'Come back later' : 'Start review'),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  if (items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Words and sentences from your conversations and checks are saved here automatically. '
                        'You can also add your own.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  for (final it in items)
                    Dismissible(
                      key: ValueKey(it['id']),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        color: const Color(0xFFFFEDEA),
                        child: const Icon(Icons.delete_outline, color: Color(0xFFB3261E)),
                      ),
                      onDismissed: (_) => _delete(it),
                      child: Card(
                        color: Colors.white,
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text((it['front'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: (it['back'] as String?)?.isNotEmpty == true ? Text(it['back'] as String) : null,
                          trailing: _BoxDots((it['box'] as int?) ?? 0),
                        ),
                      ),
                    ),
                  if (items.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('Swipe left on a word to delete it.',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black45)),
                    ),
                ],
              ),
            ),
    );
  }
}

/// Five dots showing how well a card is learned.
class _BoxDots extends StatelessWidget {
  final int box;
  const _BoxDots(this.box);
  @override
  Widget build(BuildContext context) => Tooltip(
        message: box >= 4 ? 'Learned' : 'Learning',
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 5; i++)
            Container(
              width: 7, height: 7,
              margin: const EdgeInsets.only(left: 3),
              decoration: BoxDecoration(shape: BoxShape.circle, color: i < box ? _green : Colors.black12),
            ),
        ]),
      );
}

class _AddCardSheet extends StatefulWidget {
  const _AddCardSheet();
  @override
  State<_AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends State<_AddCardSheet> {
  final _front = TextEditingController();
  final _back = TextEditingController();
  final _example = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    _example.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_front.text.trim().isEmpty) return setState(() => _error = 'Enter a word or sentence');
    setState(() { _saving = true; _error = null; });
    try {
      await Api.request('POST', '/vocab', body: {
        'front': _front.text.trim(),
        'back': _back.text.trim(),
        if (_example.text.trim().isNotEmpty) 'example': _example.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + mq.viewInsets.bottom + mq.padding.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Add a word', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(controller: _front, autofocus: true, decoration: const InputDecoration(labelText: 'Word or sentence')),
          const SizedBox(height: 12),
          TextField(controller: _back, decoration: const InputDecoration(labelText: 'Meaning')),
          const SizedBox(height: 12),
          TextField(controller: _example, decoration: const InputDecoration(labelText: 'Example (optional)')),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save word'),
          ),
        ]),
      ),
    );
  }
}

/// Flip-card review: see the front, tap to reveal, then "Again" or "I knew it".
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});
  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  final _tts = FlutterTts();
  List<Map>? _cards;
  int _i = 0;
  bool _revealed = false;
  int _known = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.45);
    Api.request('GET', '/vocab/due').then((r) {
      if (mounted) setState(() => _cards = (r as List).cast<Map>());
    }).catchError((Object e) {
      if (mounted) setState(() => _error = _friendlyError(e));
    });
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _answer(bool known) async {
    final card = _cards![_i];
    Api.request('POST', '/vocab/${card['id']}/review', body: {'known': known}).catchError((_) => null);
    setState(() {
      if (known) {
        _known++;
      } else {
        _cards!.add(card); // see it again at the end of this review
      }
      _i++;
      _revealed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards;
    final bottom = MediaQuery.of(context).padding.bottom;
    if (cards == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator()),
      );
    }
    if (_i >= cards.length) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle, size: 64, color: _green),
              const SizedBox(height: 12),
              Text(cards.isEmpty ? 'Nothing to review right now.' : 'Review done! You knew $_known.',
                  style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
            ]),
          ),
        ),
      );
    }
    final c = cards[_i];
    return Scaffold(
      appBar: AppBar(title: Text('Review ${_i + 1} of ${cards.length}')),
      body: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _revealed = true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: _revealed ? Colors.white : _green,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: _green, width: 2),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text((c['front'] ?? '').toString(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w700, color: _revealed ? _deepGreen : Colors.white)),
                  IconButton(
                    tooltip: 'Listen',
                    icon: Icon(Icons.volume_up_outlined, color: _revealed ? _deepGreen : Colors.white),
                    onPressed: () => _tts.speak((c['front'] ?? '').toString()),
                  ),
                  if (_revealed) ...[
                    const Divider(height: 28),
                    if ((c['back'] as String?)?.isNotEmpty == true)
                      Text(c['back'] as String, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
                    if ((c['example'] as String?)?.isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      Text(c['example'] as String,
                          textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
                    ],
                  ] else
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text('Say what it means, then tap to check', style: TextStyle(color: Colors.white70)),
                    ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!_revealed)
            FilledButton(onPressed: () => setState(() => _revealed = true), child: const Text('Show answer'))
          else
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  onPressed: () => _answer(false),
                  child: const Text('Again'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(onPressed: () => _answer(true), child: const Text('I knew it')),
              ),
            ]),
        ]),
      ),
    );
  }
}