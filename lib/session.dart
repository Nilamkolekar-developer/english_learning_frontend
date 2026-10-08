import 'package:flutter/foundation.dart';
import 'api.dart';

class Session extends ChangeNotifier {
  bool loggedIn = false;
  bool subscribed = false;

  /// Latest /subscription/status from the server (prices, trial, why access ended).
  Map<String, dynamic>? sub;

  Future<void> load() async {
    loggedIn = await Api.hasSession();
    if (loggedIn) await refreshStatus();
    notifyListeners();
  }

  /// The server decides if the user has paid. The app only reads it.
  Future<void> refreshStatus() async {
    try {
      final s = await Api.request('GET', '/subscription/status');
      sub = Map<String, dynamic>.from(s as Map);
      subscribed = s['active'] == true;
    } on ApiException catch (e) {
      if (e.status == 401) await signOut();
    } catch (_) {
      // offline: keep the last known state
    }
    notifyListeners();
  }

  Future<void> signup(String name, String username, String phone, String email, String password) async {
    final t = await Api.request('POST', '/auth/signup',
        body: {'name': name, 'username': username, 'phone': phone, 'email': email, 'password': password});
    await _finishLogin(t);
  }

  Future<void> login(String email, String password) async {
    final t = await Api.request('POST', '/auth/login', body: {'email': email, 'password': password});
    await _finishLogin(t);
  }

  /// Step 1 of "Forgot password": the server emails a 6-digit code.
  Future<void> requestReset(String email) =>
      Api.request('POST', '/auth/forgot', body: {'email': email});

  /// Step 2: set the new password with the code. Signs the user in.
  Future<void> resetPassword(String email, String code, String newPassword) async {
    final t = await Api.request('POST', '/auth/reset',
        body: {'email': email, 'code': code, 'new_password': newPassword});
    await _finishLogin(t);
  }

  Future<void> _finishLogin(dynamic tokens) async {
    await Api.saveTokens(tokens);
    loggedIn = true;
    await refreshStatus();
  }

  /// DEV ONLY until Razorpay is connected (server needs DEV_MODE=1).
  Future<void> devActivate() async {
    await Api.request('POST', '/dev/activate');
    await refreshStatus();
  }

  Future<void> signOut() async {
    await Api.clear();
    loggedIn = false;
    subscribed = false;
    sub = null;
    notifyListeners();
  }
}