import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// Something the server or the network said no to, in words a person can act on.
class ApiError implements Exception {
  ApiError(this.message, {this.status = 0, this.code});
  final String message;

  /// The HTTP status, or 0 when the server could not be reached at all.
  final int status;
  final String? code;

  /// No answer from the server: no signal, or the server is away.
  bool get offline => status == 0;

  /// The sign-in has ended and the person has to sign in again.
  bool get isSignedOut => status == 401;

  @override
  String toString() => message;
}

const _noConnection = 'No connection. Check your signal and try again.';
const _timeout = 'The server is taking too long. Try again in a moment.';

/// A signed-in session: the short-lived access token and the refresh
/// token that renews it.
class Session {
  Session({required this.accessToken, required this.refreshToken, required this.expiresAt, required this.user});

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final Map<String, dynamic> user;

  String? get email => _nonEmpty(user['email']);
  String? get phone => _nonEmpty(user['phone']);

  static String? _nonEmpty(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

  static Session? fromJson(dynamic j) {
    if (j is! Map) return null;
    final access = j['access_token'];
    final refresh = j['refresh_token'];
    if (access is! String || refresh is! String) return null;
    DateTime expires;
    final at = j['expires_at'];
    final inSec = j['expires_in'];
    if (at is num) {
      expires = DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000);
    } else if (inSec is num) {
      expires = DateTime.now().add(Duration(seconds: inSec.toInt()));
    } else {
      expires = _jwtExpiry(access) ?? DateTime.now().add(const Duration(minutes: 50));
    }
    final user = j['user'] is Map ? Map<String, dynamic>.from(j['user'] as Map) : <String, dynamic>{};
    return Session(accessToken: access, refreshToken: refresh, expiresAt: expires, user: user);
  }

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.millisecondsSinceEpoch ~/ 1000,
        'user': user,
      };

  static DateTime? _jwtExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload is Map ? payload['exp'] : null;
      return exp is num ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000) : null;
    } catch (_) {
      return null;
    }
  }
}

/// Talks to the Monee server.
///
/// People sign in through /auth/v1 (the SkiFi login) and read and write
/// through /rest/v1, as themselves, so the database's row rules decide what
/// they see. Every request names the book being worked in (sent as
/// x-farm-id, the header the shared app base passes to the database).
class Api {
  Api._();
  static final Api instance = Api._();

  static const _storeKey = 'monee.session';
  static const _bookKey = 'monee.book';
  http.Client _http = http.Client();

  /// For tests and screenshots: answers from a stand-in server.
  set client(http.Client c) => _http = c;
  final StreamController<Session?> _changes = StreamController<Session?>.broadcast();
  Session? _session;
  Future<void>? _refreshing;

  /// The book being worked in: sent with every request.
  String? bookId;

  /// For screenshots and tests: every call fails at once, without the network.
  bool offline = false;

  Session? get session => _session;
  bool get signedIn => _session != null;
  Stream<Session?> get changes => _changes.stream;

  /// Picks up the session saved on this device, if there is one.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bookId = prefs.getString(_bookKey);
      final raw = prefs.getString(_storeKey);
      if (raw == null) return;
      _session = Session.fromJson(jsonDecode(raw));
      if (_session != null && _session!.expiresAt.isBefore(DateTime.now().add(const Duration(seconds: 60)))) {
        try {
          await _refresh();
        } on ApiError catch (e) {
          if (e.status == 400 || e.status == 401 || e.status == 403 || e.status == 404) await _setSession(null);
        }
      }
    } catch (_) {
      _session = null;
    }
  }

  Future<void> chooseBook(String? id) async {
    bookId = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id == null) {
        await prefs.remove(_bookKey);
      } else {
        await prefs.setString(_bookKey, id);
      }
    } catch (_) {
      // Kept for this visit either way.
    }
  }

  Future<void> _setSession(Session? s) async {
    _session = s;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (s == null) {
        await prefs.remove(_storeKey);
      } else {
        await prefs.setString(_storeKey, jsonEncode(s.toJson()));
      }
    } catch (_) {
      // The session still works for now; it just will not survive a restart.
    }
    _changes.add(s);
  }

  Map<String, String> _headers(bool withUser, [Map<String, String>? extra]) => {
        'apikey': 'public',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-Client-Info': 'monee-app/1.0',
        'Authorization': 'Bearer ${withUser && _session != null ? _session!.accessToken : 'public'}',
        // The app base passes x-farm-id through to the database; Monee's
        // database reads the book from it (requested_book).
        if (withUser && bookId != null) 'x-farm-id': bookId!,
        ...?extra,
      };

  Future<void> _fresh() async {
    final s = _session;
    if (s == null) return;
    if (s.expiresAt.isAfter(DateTime.now().add(const Duration(seconds: 60)))) return;
    try {
      await _refresh();
    } on ApiError catch (e) {
      if (e.status == 400 || e.status == 401 || e.status == 403 || e.status == 404) {
        await _setSession(null);
        throw ApiError('Your sign-in has ended. Please sign in again.', status: 401);
      }
      // No signal: carry on with the old token and let the server decide.
    }
  }

  Future<void> _refresh() {
    return _refreshing ??= () async {
      try {
        final r = await _raw('POST', '/auth/v1/token',
            query: {'grant_type': 'refresh_token'}, body: {'refresh_token': _session!.refreshToken}, withUser: false, retry: false);
        final next = Session.fromJson(r.json);
        if (next == null) throw ApiError('Please sign in again.', status: 401);
        await _setSession(next);
      } finally {
        _refreshing = null;
      }
    }();
  }

  Future<_Reply> _raw(String method, String path,
      {Object? body, Map<String, String>? query, bool withUser = true, bool retry = true, Map<String, String>? headers}) async {
    if (offline) throw ApiError(_noConnection);
    if (withUser) await _fresh();
    final uri = Uri.parse('$kApiBase$path').replace(queryParameters: query);
    http.Response r;
    try {
      final req = http.Request(method, uri)..headers.addAll(_headers(withUser, headers));
      if (body != null) req.body = jsonEncode(body);
      final streamed = await _http.send(req).timeout(const Duration(seconds: 30));
      r = await http.Response.fromStream(streamed).timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw ApiError(_timeout);
    } catch (_) {
      throw ApiError(_noConnection);
    }
    final text = utf8.decode(r.bodyBytes, allowMalformed: true);
    dynamic j;
    if (text.isNotEmpty) {
      try {
        j = jsonDecode(text);
      } catch (_) {
        j = null;
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return _Reply(j, r.headers);
    // An access token that ran out early: renew once and try again.
    if (r.statusCode == 401 && withUser && retry && _session != null) {
      try {
        await _refresh();
      } on ApiError catch (e) {
        if (!e.offline) await _setSession(null);
        throw ApiError('Your sign-in has ended. Please sign in again.', status: 401);
      }
      return _raw(method, path, body: body, query: query, withUser: withUser, retry: false, headers: headers);
    }
    throw error(r.statusCode, j);
  }

  static ApiError error(int status, dynamic j) {
    String raw = '';
    String? code;
    if (j is Map) {
      raw = (j['message'] ?? j['msg'] ?? j['error_description'] ?? j['error'] ?? '').toString();
      code = (j['code'] ?? j['error_code'])?.toString();
    }
    if (raw.isEmpty) raw = status >= 500 ? 'The server had a problem. Try again in a minute.' : 'That did not work ($status).';
    return ApiError(nice(raw, code), status: status, code: code);
  }

  /// Server wording, turned into what to do next.
  static String nice(String m, [String? code]) {
    final s = m.toLowerCase();
    if (s.contains('row-level security') || s.contains('permission denied') || code == '42501' && s.contains('policy')) {
      return 'You do not have permission to do that. Ask the book\'s owner.';
    }
    if (s.contains('not on whatsapp')) return 'That number is not on WhatsApp. Use email instead.';
    if (s.contains('could not send')) return 'The code could not be sent. Try again in a minute.';
    if (s.contains('rate limit') || s.contains('too many')) return 'Too many tries. Wait a few minutes, then try again.';
    if ((s.contains('invalid') || s.contains('expired') || s.contains('not right')) &&
        (s.contains('token') || s.contains('otp') || s.contains('code')) &&
        !s.contains('jwt')) {
      return 'That code is not right, or it has expired.';
    }
    if (s.contains('invalid login credentials')) return 'That email and password do not match.';
    if (s.contains('jwt') || s.contains('not signed in')) return 'Your sign-in has ended. Please sign in again.';
    if (s.contains('duplicate key') && s.contains('tags_book_name')) return 'There is already a tag with that name.';
    if (s.contains('duplicate key') && s.contains('book_members_email')) return 'Someone in this book already has that email.';
    if (s.contains('duplicate key') && s.contains('book_members_phone')) return 'Someone in this book already has that number.';
    if (s.contains('duplicate key') && s.contains('budgets_one')) return 'That budget is already set for this month.';
    if (s.contains('duplicate key')) return 'That is already saved.';
    if (s.contains('violates foreign key')) return 'Other records still use this, so it cannot be deleted.';
    return m;
  }

  // ---------------------------------------------------------------- sign in

  Future<void> sendWhatsAppCode(String phone) async {
    await _raw('POST', '/auth/v1/otp',
        body: {'phone': phone, 'create_user': true, 'channel': 'whatsapp', 'data': <String, dynamic>{}}, withUser: false);
  }

  Future<void> verifyWhatsAppCode(String phone, String code) async {
    final r = await _raw('POST', '/auth/v1/verify', body: {'phone': phone, 'token': code.trim(), 'type': 'sms'}, withUser: false);
    await _take(r.json);
  }

  Future<void> sendEmailCode(String email) async {
    await _raw('POST', '/auth/v1/otp',
        body: {'email': email.trim().toLowerCase(), 'create_user': true, 'data': <String, dynamic>{}}, withUser: false);
  }

  Future<void> verifyEmailCode(String email, String code) async {
    final r = await _raw('POST', '/auth/v1/verify',
        body: {'email': email.trim().toLowerCase(), 'token': code.trim(), 'type': 'email'}, withUser: false);
    await _take(r.json);
  }

  Future<void> signInWithPassword(String email, String password) async {
    final r = await _raw('POST', '/auth/v1/token',
        query: {'grant_type': 'password'}, body: {'email': email.trim().toLowerCase(), 'password': password}, withUser: false);
    await _take(r.json);
  }

  /// A password of the signed-in person's own choosing, for their email.
  Future<void> setPassword(String password) async {
    await _raw('PUT', '/auth/v1/user', body: {'password': password});
  }

  Future<void> _take(dynamic j) async {
    final s = Session.fromJson(j);
    if (s == null) throw ApiError('Sign-in did not finish. Please try again.');
    await _setSession(s);
  }

  Future<void> signOut() async {
    if (_session != null) {
      try {
        await _raw('POST', '/auth/v1/logout', retry: false);
      } catch (_) {
        // Signed out on this device either way.
      }
    }
    await chooseBook(null);
    await _setSession(null);
  }

  /// Deletes every book this person owns, leaves the ones they share, and
  /// deletes their Monee account. The SkiFi login itself (shared with other
  /// SkiFi apps) stays.
  Future<void> deleteAccount() async {
    await rpc('delete_my_data');
    await signOut();
  }

  // ---------------------------------------------------------------- database

  Future<dynamic> rpc(String fn, [Map<String, dynamic>? args]) async =>
      (await _raw('POST', '/rest/v1/rpc/$fn', body: args ?? const {})).json;

  /// Calls a server function in supabase/functions.
  Future<dynamic> function(String name, [Map<String, dynamic>? body]) async =>
      (await _raw('POST', '/functions/v1/$name', body: body ?? const {})).json;

  static const int page = 1000;

  /// Every row a query matches. The database API answers at most a page of
  /// rows at a time and says nothing when it stops, so this asks page after
  /// page until one comes back short.
  Future<List<Map<String, dynamic>>> select(String table,
      {String columns = '*', Map<String, String>? where, String? order, int? limit}) async {
    final out = <Map<String, dynamic>>[];
    for (var from = 0;; from += page) {
      final size = limit == null ? page : (limit - out.length).clamp(0, page);
      if (size == 0) break;
      final q = <String, String>{'select': columns, ...?where};
      if (order != null) q['order'] = order;
      final r = await _raw('GET', '/rest/v1/$table', query: q, headers: {'Range-Unit': 'items', 'Range': '$from-${from + size - 1}'});
      final rows = (r.json as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      out.addAll(rows);
      if (rows.length < size) break;
    }
    return out;
  }

  Future<Map<String, dynamic>> insert(String table, Map<String, dynamic> row, {String columns = '*'}) async {
    final r = await _raw('POST', '/rest/v1/$table',
        query: {'select': columns}, body: row, headers: {'Prefer': 'return=representation'});
    final list = r.json as List? ?? const [];
    if (list.isEmpty) throw ApiError('That was not saved. You may not have permission.');
    return Map<String, dynamic>.from(list.first as Map);
  }

  /// Changes rows and returns them. A change the database refuses does not
  /// raise an error: it simply changes nothing. So an update that comes back
  /// empty is reported, never shown as saved.
  Future<List<Map<String, dynamic>>> update(String table, Map<String, dynamic> patch,
      {required Map<String, String> where, String columns = '*'}) async {
    final r = await _raw('PATCH', '/rest/v1/$table',
        query: {'select': columns, ...where}, body: patch, headers: {'Prefer': 'return=representation'});
    final list = (r.json as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    if (list.isEmpty) throw ApiError('Nothing was changed. You may not have permission, or it was removed.');
    return list;
  }

  /// Puts a file in storage (a receipt photo) and returns its path.
  Future<String> upload(String bucket, String path, List<int> bytes, String contentType) async {
    if (offline) throw ApiError(_noConnection);
    await _fresh();
    final uri = Uri.parse('$kApiBase/storage/v1/object/$bucket/$path');
    try {
      final req = http.Request('POST', uri)
        ..headers.addAll(_headers(true, {'Content-Type': contentType, 'x-upsert': 'true'}))
        ..bodyBytes = bytes;
      final r = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 60)));
      if (r.statusCode >= 200 && r.statusCode < 300) return path;
      dynamic j;
      try {
        j = jsonDecode(r.body);
      } catch (_) {}
      throw error(r.statusCode, j);
    } on TimeoutException {
      throw ApiError(_timeout);
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError(_noConnection);
    }
  }

  /// A file from storage, as bytes (for showing a receipt).
  Future<List<int>> download(String bucket, String path) async {
    if (offline) throw ApiError(_noConnection);
    await _fresh();
    try {
      final r = await _http
          .get(Uri.parse('$kApiBase/storage/v1/object/authenticated/$bucket/$path'), headers: _headers(true))
          .timeout(const Duration(seconds: 45));
      if (r.statusCode >= 200 && r.statusCode < 300) return r.bodyBytes;
      throw error(r.statusCode, null);
    } on TimeoutException {
      throw ApiError(_timeout);
    } on ApiError {
      rethrow;
    } catch (_) {
      throw ApiError(_noConnection);
    }
  }

  Future<int> delete(String table, {required Map<String, String> where}) async {
    final r = await _raw('DELETE', '/rest/v1/$table',
        query: {'select': 'id', ...where}, headers: {'Prefer': 'return=representation'});
    final n = (r.json as List? ?? const []).length;
    if (n == 0) throw ApiError('Nothing was deleted. You may not have permission, or it was already gone.');
    return n;
  }
}

class _Reply {
  _Reply(this.json, this.headers);
  final dynamic json;
  final Map<String, String> headers;
}

