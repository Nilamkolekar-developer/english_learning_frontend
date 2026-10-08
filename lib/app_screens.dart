import 'package:english_practice/learn_screen.dart';
import 'package:english_practice/listen_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'api.dart';
import 'session.dart';
import 'profile_screen.dart';
import 'friends_screens.dart';


/// Bumped after a conversation ends so Home and Progress reload.
final progressRefresh = ValueNotifier<int>(0);

class HomeShell extends StatefulWidget {
  final Session session;
  const HomeShell(this.session, {super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _i = 0;
  late final List<Widget> _tabs;
  final _talk = GlobalKey<TalkScreenState>();

  @override
  void initState() {
    super.initState();
    loadProfile();
    _tabs = [
      HomeTab(
        session: widget.session,
        onStart: (scenario) {
          setState(() => _i = 1);
          _talk.currentState?.startScenario(scenario);
        },
      ),
      TalkScreen(key: _talk),
      const ListenTab(),
      const FriendsTab(),
      const ProgressTab(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps each tab alive, so the chat is not reloaded when switching tabs.
      body: SafeArea(child: IndexedStack(index: _i, children: _tabs)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (v) => setState(() => _i = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), label: 'Talk'),
          NavigationDestination(icon: Icon(Icons.headphones_outlined), label: 'Listen'),
          NavigationDestination(icon: Icon(Icons.people_outline), label: 'Friends'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Progress'),
        ],
      ),
    );
  }
}

/// Icons for the role-play situations (keys come from the server).
const scenarioIcons = <String, IconData>{
  'free': Icons.forum_outlined,
  'interview': Icons.work_outline,
  'restaurant': Icons.restaurant_outlined,
  'doctor': Icons.medical_services_outlined,
  'phone_call': Icons.phone_in_talk_outlined,
  'new_colleague': Icons.handshake_outlined,
  'travel': Icons.flight_takeoff,
  'shopping': Icons.shopping_bag_outlined,
};

class HomeTab extends StatefulWidget {
  final void Function(String scenario) onStart;
  final Session session;
  const HomeTab({super.key, required this.onStart, required this.session});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  Map<String, dynamic>? _p;
  List<Map> _scenarios = [];

  @override
  void initState() {
    super.initState();
    _load();
    progressRefresh.addListener(_load);
  }

  @override
  void dispose() {
    progressRefresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([Api.request('GET', '/progress'), Api.request('GET', '/scenarios')]);
      if (!mounted) return;
      setState(() {
        _p = Map<String, dynamic>.from(r[0] as Map);
        _scenarios = (r[1] as List).cast<Map>().where((s) => s['key'] != 'free').toList();
      });
    } catch (_) {
      // Home still works without stats
    }
  }

  void _openProfile() =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(widget.session)));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget stat(String l, String v) => Expanded(
          child: Card(
            color: Colors.white, elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l, style: t.bodySmall), Text(v, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        );
    final streak = _p?['streak'] ?? 0;
    final focus = _p?['focus'] as String?;

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_load(), loadProfile()]);
      },
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Row(children: [
          ValueListenableBuilder(
            valueListenable: profile,
            builder: (_, p, __) => Tooltip(
              message: 'Profile',
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _openProfile,
                child: p == null ? const Avatar(null, radius: 24) : userAvatar(p, radius: 24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('What would you like to practice?',
                style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: const Color(0xFF0F7B63), borderRadius: BorderRadius.circular(24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Talk like with a friend. Type or speak. Corrections come after.',
                style: TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFF0A5C4A)),
              onPressed: () => widget.onStart('free'),
              child: const Text('Start free talk'),
            ),
          ]),
        ),
        if (_scenarios.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('Practise a real situation', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.45,
            children: [
              for (final sc in _scenarios)
                Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => widget.onStart(sc['key'] as String),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(scenarioIcons[sc['key']] ?? Icons.chat_outlined, color: const Color(0xFF0F7B63)),
                        const Spacer(),
                        Text(sc['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(sc['subtitle'] as String,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Card(
          color: Colors.white, elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.fitness_center, color: Color(0xFF0F7B63)),
            title: const Text("Today's focus"),
            subtitle: Text(focus ?? 'Practise everyday grammar', style: focus != null ? t.titleLarge : null),
            trailing: const Text('Practise', style: TextStyle(color: Color(0xFF0A5C4A), fontWeight: FontWeight.w700)),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const PracticeScreen()));
              _load();
            },
          ),
        ),
        Card(
          color: Colors.white, elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.style_outlined, color: Color(0xFF0F7B63)),
            title: const Text('My words'),
            subtitle: Text((_p?['words_due'] ?? 0) == 0
                ? 'No cards to review right now'
                : '${_p?['words_due']} ${_p?['words_due'] == 1 ? 'card' : 'cards'} to review today'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const WordsScreen()));
              _load();
            },
          ),
        ),
        Row(children: [
          stat('Conversations', '${_p?['sessions'] ?? 0}'),
          stat('Streak', '$streak ${streak == 1 ? 'day' : 'days'}'),
        ]),
      ]),
    );
  }
}

class Msg {
  final bool user;
  final String text;
  int? id; // server id, needed to check the message
  bool checked;
  String? corrected; // null after a check means the message was already correct
  String? note;
  bool checking = false;
  Msg(this.user, this.text, {this.id, this.checked = false, this.corrected, this.note});
}

class TalkScreen extends StatefulWidget {
  const TalkScreen({super.key});
  @override
  State<TalkScreen> createState() => TalkScreenState();
}

class TalkScreenState extends State<TalkScreen> {
  final _c = TextEditingController();
  final _scroll = ScrollController();
  final _msgs = <Msg>[];
  String? _sid;
  Map _scenario = const {'key': 'free', 'title': 'Free talk', 'subtitle': 'Chat about anything'};
  bool _starting = true; // loading the conversation
  bool _waiting = false; // waiting for an AI reply
  bool _ending = false; // waiting for the analysis

  // Voice: speech to text for the learner, text to speech for the AI
  final _speech = stt.SpeechToText();
  final _tts = FlutterTts();
  bool _speechReady = false;
  bool _listening = false;
  String? _speechLocale;
  bool _autoSpeak = false;
  int? _speakingIndex;

  @override
  void initState() {
    super.initState();
    _startSession();
    _initVoice();
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initVoice() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45); // a little slower than normal, easier for learners
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speakingIndex = null);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _speakingIndex = null);
    });
  }

  Future<bool> _ensureSpeech() async {
    if (_speechReady) return true;
    _speechReady = await _speech.initialize(
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && mounted) setState(() => _listening = false);
      },
      onError: (e) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (_speechReady) {
      // Prefer Indian English, then US English, then the phone's default.
      final locales = await _speech.locales();
      final ids = locales.map((l) => l.localeId).toList();
      _speechLocale = ids.contains('en_IN') ? 'en_IN' : (ids.contains('en_US') ? 'en_US' : null);
    }
    return _speechReady;
  }

  Future<void> _toggleMic() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    if (!await _ensureSpeech()) {
      _showError('Speech is not available. Allow microphone access in your phone settings.');
      return;
    }
    await _tts.stop();
    setState(() => _listening = true);
    await _speech.listen(
      localeId: _speechLocale,
      listenOptions: stt.SpeechListenOptions(partialResults: true),
      onResult: (r) {
        _c.text = r.recognizedWords;
        _c.selection = TextSelection.collapsed(offset: _c.text.length);
        if (r.finalResult && mounted) setState(() => _listening = false);
      },
    );
  }

  Future<void> _speak(int index) async {
    if (_speakingIndex == index) {
      await _tts.stop();
      setState(() => _speakingIndex = null);
      return;
    }
    await _tts.stop();
    setState(() => _speakingIndex = index);
    await _tts.speak(_msgs[index].text);
  }

  void _showError(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  /// Called from Home when the learner picks free talk or a situation.
  Future<void> startScenario(String key) async {
    final sameAndOpen = _sid != null && _scenario['key'] == key;
    if (sameAndOpen) return; // just continue the current chat
    final hasWritten = _msgs.any((m) => m.user);
    if (hasWritten) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Start a new conversation?'),
          content: const Text('Your current chat will close without feedback. Tap End first if you want your results.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep current chat')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Start new')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _startSession(forceNew: true, topic: key);
  }

  /// Opens the last unfinished conversation, or starts a new one.
  Future<void> _startSession({bool forceNew = false, String topic = 'free'}) async {
    await _tts.stop();
    setState(() {
      _starting = true;
      _msgs.clear();
      _sid = null;
    });
    try {
      if (!forceNew) {
        final a = await Api.request('GET', '/sessions/active');
        if (a != null) {
          _sid = a['id'] as String;
          if (a['scenario'] != null) _scenario = a['scenario'] as Map;
          final old = (a['messages'] as List).map((m) => Msg(
                m['sender'] == 'USER',
                m['content'] as String,
                id: m['id'] as int?,
                checked: m['checked'] == true,
                corrected: m['corrected'] as String?,
                note: m['correction_note'] as String?,
              ));
          if (mounted) setState(() => _msgs.addAll(old));
          _scrollDown();
          return;
        }
      }
      final s = await Api.request('POST', '/sessions', body: {'topic': topic});
      _sid = s['id'] as String;
      if (s['scenario'] != null) _scenario = s['scenario'] as Map;
      final opener = (s['opener'] as String?) ?? 'Hi! How was your day?';
      if (mounted) setState(() => _msgs.add(Msg(false, opener)));
      if (_autoSpeak) _speak(_msgs.length - 1);
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Cannot reach the server');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _send() async {
    if (_listening) await _speech.stop();
    final text = _c.text.trim();
    if (text.isEmpty || _sid == null || _waiting) return;
    _c.clear();
    final mine = Msg(true, text);
    setState(() {
      _msgs.add(mine);
      _waiting = true;
      _listening = false;
    });
    _scrollDown();
    try {
      final r = await Api.request('POST', '/sessions/$_sid/messages', body: {'content': text});
      if (mounted) {
        setState(() {
          mine.id = r['message_id'] as int?;
          _msgs.add(Msg(false, r['reply'] as String));
        });
        if (_autoSpeak) _speak(_msgs.length - 1);
      }
      _scrollDown();
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Cannot reach the server');
    } finally {
      if (mounted) setState(() => _waiting = false);
    }
  }

  /// Asks the server for a corrected version of one of the learner's messages.
  Future<void> _check(Msg m) async {
    if (m.id == null || m.checking) return;
    setState(() => m.checking = true);
    try {
      final r = await Api.request('POST', '/messages/${m.id}/check');
      if (mounted) {
        setState(() {
          m.checked = true;
          m.corrected = r['corrected'] as String?;
          m.note = r['explanation'] as String?;
        });
      }
      _scrollDown();
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Cannot reach the server');
    } finally {
      if (mounted) setState(() => m.checking = false);
    }
  }

  /// The small "Check" button under a learner message, or the result once checked.
  Widget _checkArea(Msg m) {
    final maxW = MediaQuery.of(context).size.width * .78;
    if (!m.checked) {
      return TextButton.icon(
        onPressed: m.id == null || m.checking ? null : () => _check(m),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          foregroundColor: const Color(0xFF0A5C4A),
        ),
        icon: m.checking
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.spellcheck, size: 16),
        label: Text(m.checking ? 'Checking' : 'Check'),
      );
    }
    if (m.corrected == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 6, right: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle, size: 16, color: Color(0xFF0F7B63)),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW - 24),
            child: Text(m.note?.isNotEmpty == true ? m.note! : 'Looks good',
                style: const TextStyle(fontSize: 13, color: Color(0xFF0A5C4A))),
          ),
        ]),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.all(12),
      constraints: BoxConstraints(maxWidth: maxW),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8A33D)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Better way to say it', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(m.corrected!, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        if (m.note?.isNotEmpty == true) ...[
          const SizedBox(height: 6),
          Text(m.note!, style: const TextStyle(fontSize: 13, color: Colors.black87)),
        ],
      ]),
    );
  }

  /// Asks the server to analyse the conversation, then shows the results.
  Future<void> _end() async {
    if (_sid == null || _ending) return;
    if (!_msgs.any((m) => m.user)) {
      _showError('Send at least one message before ending');
      return;
    }
    await _tts.stop();
    setState(() => _ending = true);
    try {
      final result = Map<String, dynamic>.from(await Api.request('POST', '/sessions/$_sid/end') as Map);
      progressRefresh.value++;
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => AnalysisScreen(result)));
      if (mounted) _startSession(forceNew: true, topic: (_scenario['key'] as String?) ?? 'free');
    } on ApiException catch (e) {
      _showError(e.message);
    } catch (_) {
      _showError('Cannot reach the server');
    } finally {
      if (mounted) setState(() => _ending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _starting || _waiting;
    final key = (_scenario['key'] as String?) ?? 'free';
    return Column(children: [
      ListTile(
        leading: Icon(scenarioIcons[key] ?? Icons.forum_outlined, color: const Color(0xFF0F7B63)),
        title: Text((_scenario['title'] ?? 'Free talk').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text((_scenario['subtitle'] ?? '').toString()),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: _autoSpeak ? 'Stop reading replies aloud' : 'Read replies aloud',
            icon: Icon(_autoSpeak ? Icons.volume_up : Icons.volume_off_outlined),
            onPressed: () {
              setState(() => _autoSpeak = !_autoSpeak);
              if (!_autoSpeak) _tts.stop();
            },
          ),
          OutlinedButton(
            onPressed: (_ending || _starting) ? null : _end,
            child: _ending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('End'),
          ),
        ]),
      ),
      Expanded(
        child: _starting && _msgs.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _msgs.length + (_waiting ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == _msgs.length) {
                    return const Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Typing...', style: TextStyle(color: Colors.black54)),
                      ),
                    );
                  }
                  final m = _msgs[i];
                  final bubble = Container(
                    margin: EdgeInsets.only(top: 6, bottom: m.user ? 0 : 6),
                    padding: const EdgeInsets.all(12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .72),
                    decoration: BoxDecoration(
                      color: m.user ? const Color(0xFF0F7B63) : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(m.text, style: TextStyle(color: m.user ? Colors.white : Colors.black87)),
                  );
                  if (!m.user) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        bubble,
                        IconButton(
                          tooltip: _speakingIndex == i ? 'Stop' : 'Listen',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(_speakingIndex == i ? Icons.stop_circle_outlined : Icons.volume_up_outlined,
                              size: 20, color: const Color(0xFF0A5C4A)),
                          onPressed: () => _speak(i),
                        ),
                      ]),
                    );
                  }
                  return Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [bubble, _checkArea(m)],
                    ),
                  );
                },
              ),
      ),
      if (!_starting && _sid == null)
        TextButton(onPressed: _startSession, child: const Text('Try again')),
      if (_listening)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Listening... speak now, then tap the mic to stop',
              style: TextStyle(color: Color(0xFFB3261E), fontWeight: FontWeight.w600)),
        ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _c,
              enabled: _sid != null,
              minLines: 1,
              maxLines: 4,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(hintText: _listening ? 'Listening...' : 'Type or tap the mic'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: _listening ? const Color(0xFFB3261E) : const Color(0xFFE8A33D),
              foregroundColor: _listening ? Colors.white : Colors.black87,
            ),
            onPressed: _sid == null || busy ? null : _toggleMic,
            icon: Icon(_listening ? Icons.stop : Icons.mic),
            tooltip: _listening ? 'Stop listening' : 'Speak',
          ),
          const SizedBox(width: 4),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: const Color(0xFF0F7B63), foregroundColor: Colors.white),
            onPressed: busy || _sid == null ? null : _send,
            icon: const Icon(Icons.send),
            tooltip: 'Send',
          ),
        ]),
      ),
    ]);
  }
}

/// The feedback cards shown after a conversation (also used in History).
class AnalysisCards extends StatelessWidget {
  final Map result;
  const AnalysisCards(this.result, {super.key});

  @override
  Widget build(BuildContext context) {
    Widget card(String title, Widget body) => Card(
          color: Colors.white, elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                body,
              ]),
            ),
          ),
        );

    final strengths = (result['strengths'] as List? ?? []).map((e) => e.toString()).toList();
    final weaknesses = (result['weaknesses'] as List? ?? []).cast<Map>();
    final remember = (result['remember'] ?? '').toString();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      card('What you did well',
          Text(strengths.isEmpty ? 'Keep talking. More practice gives better feedback.' : strengths.join('\n'))),
      card(
        'Practice next',
        weaknesses.isEmpty
            ? const Text('No repeated mistakes found in this conversation.')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final w in weaknesses.take(3))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(cap((w['category'] ?? '').toString().replaceAll('_', ' ')),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (w['example'] != null)
                          Text('You said: ${w['example']}', style: const TextStyle(color: Colors.black54)),
                        if (w['correction'] != null)
                          Text('Better: ${w['correction']}', style: const TextStyle(color: Color(0xFF0F7B63))),
                        if (w['explanation'] != null) Text(w['explanation'].toString()),
                      ]),
                    ),
                ],
              ),
      ),
      if (remember.isNotEmpty) card('One sentence to remember', Text('"$remember"')),
    ]);
  }
}

class AnalysisScreen extends StatelessWidget {
  final Map<String, dynamic> result;
  const AnalysisScreen(this.result, {super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversation complete')),
      body: ListView(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
          children: [
        AnalysisCards(result),
        if ((result['remember'] ?? '').toString().isNotEmpty || (result['weaknesses'] as List? ?? []).isNotEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Key sentences from this chat were added to your Words for review.',
                style: TextStyle(color: Colors.black54)),
          ),
        const SizedBox(height: 4),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Start new conversation')),
      ]),
    );
  }
}

class ProgressTab extends StatefulWidget {
  const ProgressTab({super.key});
  @override
  State<ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<ProgressTab> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    progressRefresh.addListener(_load);
  }

  @override
  void dispose() {
    progressRefresh.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final d = await Api.request('GET', '/progress');
      if (mounted) setState(() => _data = Map<String, dynamic>.from(d as Map));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Cannot reach the server');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _data == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!),
          TextButton(onPressed: _load, child: const Text('Try again')),
        ]),
      );
    }

    final d = _data!;
    final skills = (d['skills'] as List).cast<Map>();
    final sessions = d['sessions'] as int;

    Widget stat(String label, String value) => Expanded(
          child: Card(
            color: Colors.white, elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: t.bodySmall),
                Text(value, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        );

    Widget trendIcon(String trend) => switch (trend) {
          'up' => const Tooltip(
              message: 'Improving', child: Icon(Icons.trending_up, size: 18, color: Color(0xFF0F7B63))),
          'down' => const Tooltip(
              message: 'More mistakes lately', child: Icon(Icons.trending_down, size: 18, color: Color(0xFFE8A33D))),
          _ => const SizedBox.shrink(),
        };

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('Your Progress', style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Row(children: [
          stat('Conversations', '$sessions'),
          stat('Streak', '${d['streak']} ${d['streak'] == 1 ? 'day' : 'days'}'),
          stat('Messages', '${d['messages']}'),
        ]),
        const SizedBox(height: 4),
        Card(
          color: Colors.white, elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.history, color: Color(0xFF0F7B63)),
            title: const Text('Past conversations'),
            subtitle: const Text('Read old chats and their feedback'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
        ),
        if (((d['practice'] as Map?)?['sets'] ?? 0) > 0)
          Card(
            color: Colors.white, elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.fitness_center, color: Color(0xFF0F7B63)),
              title: const Text('Practice exercises'),
              subtitle: Text(() {
                final pr = d['practice'] as Map;
                final total = (pr['total'] as num?) ?? 0;
                final pct = total == 0 ? 0 : ((pr['correct'] as num) * 100 / total).round();
                return '${pr['sets']} sets done, $pct% correct';
              }()),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PracticeScreen())),
            ),
          ),
        const SizedBox(height: 12),
        if (sessions == 0)
          const Card(
            color: Colors.white, elevation: 0,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Finish a conversation with End to see your skill scores here.'),
            ),
          )
        else ...[
          if (d['focus'] != null)
            Card(
              color: Colors.white, elevation: 0,
              child: ListTile(
                title: const Text('Practice next'),
                subtitle: Text(d['focus'] as String, style: t.titleLarge),
              ),
            ),
          const SizedBox(height: 12),
          for (final s in skills)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(s['label'] as String)),
                  trendIcon(s['trend'] as String),
                  const SizedBox(width: 6),
                  Text('${s['score']}%'),
                ]),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: (s['score'] as int) / 100,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
              ]),
            ),
          Text('Based on your last ${sessions < 10 ? sessions : 10} conversations. Pull down to refresh.',
              style: t.bodySmall),
        ],
      ]),
    );
  }
}