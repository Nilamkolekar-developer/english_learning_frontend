import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'session.dart';

class LoginScreen extends StatefulWidget {
  final Session session;
  const LoginScreen(this.session, {super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _signup = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  // Live username check while typing
  static final _usernameRule = RegExp(r'^[a-z0-9_]{3,20}$');
  Timer? _debounce;
  bool? _available; // null = not checked yet
  bool _checking = false;

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_name, _username, _phone, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  String get _cleanUsername => _username.text.trim().toLowerCase();

  void _onUsernameChanged(String _) {
    _debounce?.cancel();
    setState(() => _available = null);
    final u = _cleanUsername;
    if (!_usernameRule.hasMatch(u)) return;
    _debounce = Timer(const Duration(milliseconds: 400), () => _checkUsername(u));
  }

  Future<void> _checkUsername(String u) async {
    setState(() => _checking = true);
    try {
      final r = await Api.request('GET', '/auth/username-available?u=${Uri.encodeQueryComponent(u)}');
      if (mounted && u == _cleanUsername) setState(() => _available = r['available'] == true);
    } catch (_) {
      // the server checks again on signup
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String? get _usernameHint {
    final u = _cleanUsername;
    if (u.isEmpty) return 'Friends find you by this name';
    if (!_usernameRule.hasMatch(u)) return '3 to 20 letters, numbers or _';
    if (_checking) return 'Checking...';
    if (_available == true) return '@$u is available';
    if (_available == false) return '@$u is already taken';
    return null;
  }

  Future<void> _submit() async {
    if (_signup) {
      if (_name.text.trim().isEmpty) return setState(() => _error = 'Enter your name');
      if (!_usernameRule.hasMatch(_cleanUsername)) {
        return setState(() => _error = 'Username: 3 to 20 letters, numbers or _');
      }
      if (_available == false) return setState(() => _error = 'That username is taken. Try another.');
      if (!RegExp(r'^[6-9]\d{9}$').hasMatch(_phone.text.trim())) {
        return setState(() => _error = 'Enter a valid 10-digit mobile number');
      }
    }
    setState(() { _busy = true; _error = null; });
    try {
      if (_signup) {
        await widget.session.signup(
            _name.text.trim(), _cleanUsername, _phone.text.trim(), _email.text.trim(), _password.text);
      } else {
        await widget.session.login(_email.text, _password.text);
      }
    } on ApiException catch (e) {
      _error = e.message;
    } catch (_) {
      _error = 'Cannot reach the server';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          const SizedBox(height: 32),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(color: const Color(0xFF0F7B63), borderRadius: BorderRadius.circular(20)),
            alignment: Alignment.center,
            child: const Text('EP', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 24),
          Text(_signup ? 'Create your account' : 'Welcome back',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Sign in once. You stay signed in on this device.'),
          const SizedBox(height: 24),
          if (_signup) ...[
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              onChanged: _onUsernameChanged,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Username',
                prefixText: '@',
                helperText: _available == false ? null : _usernameHint,
                errorText: _available == false ? _usernameHint : null,
                suffixIcon: _checking
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : _available == true
                        ? const Icon(Icons.check_circle, color: Color(0xFF0F7B63))
                        : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
              decoration: const InputDecoration(
                labelText: 'Mobile number',
                prefixText: '+91 ',
                helperText: 'Friends who have your number can find you',
              ),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _hide,
            decoration: InputDecoration(
              labelText: 'Password',
              helperText: _signup ? 'At least 8 characters' : null,
              suffixIcon: IconButton(
                tooltip: _hide ? 'Show password' : 'Hide password',
                icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_signup ? 'Create account' : 'Log in'),
          ),
          if (!_signup)
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ForgotPasswordScreen(widget.session, email: _email.text.trim()))),
              child: const Text('Forgot password?'),
            ),
          TextButton(
            onPressed: () => setState(() { _signup = !_signup; _error = null; }),
            child: Text(_signup ? 'Already have an account? Log in' : 'New here? Create an account'),
          ),
        ]),
      ),
    );
  }
}

/// Forgot password: enter email, get a 6-digit code by email, set a new password.
class ForgotPasswordScreen extends StatefulWidget {
  final Session session;
  final String email;
  const ForgotPasswordScreen(this.session, {super.key, this.email = ''});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _email = TextEditingController(text: widget.email);
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (!email.contains('@')) return setState(() => _error = 'Enter the email you signed up with');
    setState(() { _busy = true; _error = null; });
    try {
      await widget.session.requestReset(email);
      if (mounted) setState(() => _codeSent = true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach the server');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) return setState(() => _error = 'Enter the 6-digit code');
    if (_password.text.length < 8) return setState(() => _error = 'Use at least 8 characters for the new password');
    setState(() { _busy = true; _error = null; });
    try {
      await widget.session.resetPassword(_email.text.trim(), _code.text.trim(), _password.text);
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst); // signed in: the app shows Home
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach the server');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.of(context).padding.bottom),
        children: [
          Text(_codeSent ? 'Check your email' : 'Reset your password',
              style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(_codeSent
              ? 'If ${_email.text.trim()} has an account, we sent a 6-digit code to it. It works for 15 minutes.'
              : "Enter your email and we'll send you a code to set a new password."),
          const SizedBox(height: 24),
          TextField(
            controller: _email,
            enabled: !_codeSent,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              decoration: const InputDecoration(labelText: '6-digit code'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: _hide,
              decoration: InputDecoration(
                labelText: 'New password',
                helperText: 'At least 8 characters',
                suffixIcon: IconButton(
                  tooltip: _hide ? 'Show password' : 'Hide password',
                  icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
              ),
            ),
          ],
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : (_codeSent ? _reset : _sendCode),
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_codeSent ? 'Set new password' : 'Send code'),
          ),
          if (_codeSent)
            TextButton(
              onPressed: _busy ? null : _sendCode,
              child: const Text("Didn't get it? Send a new code"),
            ),
        ],
      ),
    );
  }
}

const _green = Color(0xFF0F7B63);
const _deepGreen = Color(0xFF0A5C4A);
const _amber = Color(0xFFE8A33D);

class SubscribeScreen extends StatelessWidget {
  final Session session;
  const SubscribeScreen(this.session, {super.key});

  String _date(dynamic iso) {
    final d = iso == null ? null : DateTime.tryParse(iso.toString())?.toLocal();
    if (d == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = session.sub ?? const {};
    final status = (s['status'] ?? 'none') as String;
    final trial = s['trial_available'] != false;
    final monthly = (s['monthly_price'] as num?)?.toInt() ?? 100;
    final first = (s['first_payment'] as num?)?.toInt() ?? (trial ? 1 : monthly);
    final today = trial ? first : monthly;
    final ended = _date(s['current_period_end']);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    // Why the user is here decides the message at the top.
    final (String? notice, bool warn) = switch (status) {
      'halted' => ('Your ₹$monthly payment did not go through, so your plan is paused. Pay ₹$monthly to continue.', true),
      'cancelled' || 'expired' => (
          ended.isEmpty ? 'Your plan has ended.' : 'Your plan ended on $ended.',
          false,
        ),
      _ => (null, false),
    };

    final cta = status == 'halted'
        ? 'Pay ₹$monthly and continue'
        : trial
            ? 'Start my first month for ₹$first'
            : status == 'cancelled' || status == 'expired'
                ? 'Renew for ₹$monthly'
                : 'Subscribe for ₹$monthly';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          // Top bar: logo and a quiet sign-out
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(11)),
                alignment: Alignment.center,
                child: const Text('EP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
              const Spacer(),
              TextButton(onPressed: session.signOut, child: const Text('Sign out')),
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: session.refreshStatus,
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24), children: [
                if (notice != null) ...[
                  _Notice(text: notice, warn: warn),
                  const SizedBox(height: 16),
                ],

                // Price, the one thing that matters most on this screen
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                  decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(26)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      trial ? 'Your first month' : 'English Practice',
                      style: const TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('₹$today',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 64, height: 1, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(trial ? 'only' : '/ month',
                            style: const TextStyle(color: Colors.white, fontSize: 18)),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Text(
                      trial
                          ? 'Then ₹$monthly a month. Stop anytime.'
                          : 'Paid monthly with UPI Autopay. Stop anytime.',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),

                // How payments happen, step by step
                Text('How it works', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                if (trial) ...[
                  _Step(when: 'Today', text: 'Pay ₹$first. Everything unlocks right away.', first: true),
                  _Step(when: 'Before day 30', text: 'We remind you before the first ₹$monthly payment.'),
                  _Step(when: 'Day 30', text: '₹$monthly is paid by autopay, then once every month.', last: true),
                ] else ...[
                  _Step(when: 'Today', text: 'Pay ₹$monthly. Everything unlocks right away.', first: true),
                  _Step(when: 'Every month', text: 'We remind you, then ₹$monthly is paid by autopay.', last: true),
                ],
                const SizedBox(height: 24),

                Text('What you get', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const _Benefit(Icons.chat_bubble_outline, 'Talk with AI anytime', 'Everyday conversations at your level'),
                const _Benefit(Icons.spellcheck, 'See your mistakes fixed', 'Check any message, plus a summary after each chat'),
                const _Benefit(Icons.bar_chart, 'Track your progress', 'Scores for tenses, vocabulary and more'),
                const _Benefit(Icons.people_outline, 'Practise with friends', 'Add friends and chat in English'),
                const SizedBox(height: 16),

                // Reassurance
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                  child: const Column(children: [
                    _Assure(Icons.notifications_none, 'A reminder before every payment'),
                    _Assure(Icons.block, 'Stop autopay anytime from your UPI app'),
                    _Assure(Icons.lock_outline, 'Your conversations and progress are always saved'),
                  ]),
                ),
                const SizedBox(height: 20),

                Text('Questions', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                _Faq(
                  'What happens after the first month?',
                  trial
                      ? 'Your plan continues at ₹$monthly a month by UPI Autopay. The ₹$first price is only for your very first month.'
                      : 'Your plan continues at ₹$monthly a month by UPI Autopay until you stop it.',
                ),
                const _Faq(
                  'How do I stop autopay?',
                  'Open your UPI app (Google Pay, PhonePe, Paytm or your bank app), go to Autopay or Mandates, and cancel it. You keep access until the month you paid for ends.',
                ),
                _Faq(
                  'What if a payment fails?',
                  'Your plan pauses and this screen asks you to pay ₹$monthly. Nothing is deleted. Pay, and you continue where you left off.',
                ),
              ]),
            ),
          ),

          // Payment button always in reach, above the phone's navigation bar
          Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + bottomInset),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              border: Border(top: BorderSide(color: Colors.black.withValues(alpha: .06))),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FilledButton(
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (_) => _AutopaySheet(session: session, today: today, monthly: monthly, trial: trial),
                ),
                child: Text(cta, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 6),
              Text(
                trial ? 'Then ₹$monthly a month after 30 days' : '₹$monthly every month',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final bool warn;
  const _Notice({required this.text, required this.warn});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: warn ? const Color(0xFFFFEDEA) : const Color(0xFFFFF6E5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: warn ? const Color(0xFFE5533D) : _amber),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(warn ? Icons.error_outline : Icons.info_outline,
              color: warn ? const Color(0xFFB3261E) : const Color(0xFF8A5A00)),
          const SizedBox(width: 10),
          Expanded(child: Text('$text Your progress is saved.', style: const TextStyle(height: 1.35))),
        ]),
      );
}

/// One point on the payment timeline.
class _Step extends StatelessWidget {
  final String when;
  final String text;
  final bool first;
  final bool last;
  const _Step({required this.when, required this.text, this.first = false, this.last = false});
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 22,
            child: Column(children: [
              Container(width: 2, height: 6, color: first ? Colors.transparent : _green.withValues(alpha: .3)),
              Container(
                width: 14, height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: first ? _green : Colors.white,
                  border: Border.all(color: _green, width: 2),
                ),
              ),
              Expanded(child: Container(width: 2, color: last ? Colors.transparent : _green.withValues(alpha: .3))),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(when, style: const TextStyle(fontWeight: FontWeight.w700, color: _deepGreen)),
                const SizedBox(height: 2),
                Text(text, style: const TextStyle(height: 1.35)),
              ]),
            ),
          ),
        ]),
      );
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  const _Benefit(this.icon, this.title, this.sub);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(color: _green.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: _green),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              Text(sub, style: const TextStyle(color: Colors.black54)),
            ]),
          ),
        ]),
      );
}

class _Assure extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Assure(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Icon(icon, size: 20, color: _deepGreen),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      );
}

class _Faq extends StatelessWidget {
  final String q;
  final String a;
  const _Faq(this.q, this.a);
  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          expandedAlignment: Alignment.centerLeft,
          title: Text(q, style: const TextStyle(fontWeight: FontWeight.w600)),
          children: [Text(a, style: const TextStyle(color: Colors.black87, height: 1.4))],
        ),
      );
}

/// Bottom sheet where the user enters their UPI ID and approves autopay.
class _AutopaySheet extends StatefulWidget {
  final Session session;
  final int today;
  final int monthly;
  final bool trial;
  const _AutopaySheet({required this.session, required this.today, required this.monthly, required this.trial});
  @override
  State<_AutopaySheet> createState() => _AutopaySheetState();
}

class _AutopaySheetState extends State<_AutopaySheet> {
  final _upi = TextEditingController();
  bool _busy = false;
  String? _error;

  static final _upiRule = RegExp(r'^[\w.\-]{2,}@[a-zA-Z]{2,}$');

  @override
  void dispose() {
    _upi.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final upi = _upi.text.trim();
    if (!_upiRule.hasMatch(upi)) {
      setState(() => _error = 'Enter your UPI ID, for example name@okaxis');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      // DEV ONLY: devActivate() needs DEV_MODE=1 on the server.
      // TODO: call /subscription/start, open Razorpay checkout with this UPI ID,
      // and let the server webhook confirm the payment.
      await widget.session.devActivate();
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Cannot reach the server. Check your internet and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    Widget line(String a, String b, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400))),
            Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ]),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + mq.viewInsets.bottom + mq.padding.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Pay with UPI Autopay',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _green.withValues(alpha: .07), borderRadius: BorderRadius.circular(14)),
            child: Column(children: [
              line('Pay today', '₹${widget.today}', bold: true),
              line(widget.trial ? 'From day 30, every month' : 'Every month after', '₹${widget.monthly}'),
            ]),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _upi,
            autofocus: true,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            onSubmitted: (_) => _pay(),
            decoration: InputDecoration(
              labelText: 'Your UPI ID',
              hintText: 'name@okaxis',
              errorText: _error,
              prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'You will get a request in your UPI app. Approve it with your UPI PIN to start.',
            style: TextStyle(color: Colors.black54, height: 1.35),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _busy ? null : _pay,
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Pay ₹${widget.today}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }
}