import 'package:flutter/foundation.dart';

import 'api.dart';
import 'format.dart';

/// A book: one person's (or one family's) money, and how its periods run.
class Book {
  Book(this.j);
  final Map<String, dynamic> j;

  String get id => j['book_id'] as String;
  String get name => j['name'] as String? ?? 'My money';
  String get currency => j['currency'] as String? ?? 'INR';
  String get timezone => j['timezone'] as String? ?? 'Asia/Kolkata';
  String get role => j['role'] as String? ?? 'viewer';
  String get memberName => j['member_name'] as String? ?? '';
  bool get canEdit => role == 'owner' || role == 'editor';
  bool get isOwner => role == 'owner';
  DateTime get today => parseDay(j['today']) ?? dayOnly(DateTime.now());

  int get monthStartDay => (j['month_start_day'] as num?)?.toInt() ?? 1;

  /// 0 Sunday .. 6 Saturday, as the database counts.
  int get weekStart => (j['week_start'] as num?)?.toInt() ?? 0;
  int get fyStartMonth => (j['fy_start_month'] as num?)?.toInt() ?? 1;
  String get startScreen => j['start_screen'] as String? ?? 'daily';
  bool get carryOver => j['carry_over'] == true;
  bool get subcategories => j['subcategories'] != false;
  String get cardDisplay => j['card_display'] as String? ?? 'at_time';
  String get repeatShow => j['repeat_show'] as String? ?? 'on_date';

  Currency get main => currencyOf(currency);

  // ---------------------------------------------------------------- periods

  /// A day of a month, or the month's last day when the month is shorter.
  static DateTime monthDay(int y, int m, int d) {
    final last = DateTime(y, m + 1, 0).day;
    return DateTime(y, m, d > last ? last : d);
  }

  /// The month labelled y-m: from its start day to the day before the next
  /// month's start day. Same rule as month_range() in the database.
  (DateTime, DateTime) month(int y, int m) {
    final from = monthDay(y, m, monthStartDay);
    final next = m == 12 ? monthDay(y + 1, 1, monthStartDay) : monthDay(y, m + 1, monthStartDay);
    return (from, next.subtract(const Duration(days: 1)));
  }

  /// The month a day falls in: (year, month) of its label.
  (int, int) monthOf(DateTime d) {
    var y = d.year, m = d.month;
    if (d.isBefore(monthDay(y, m, monthStartDay))) {
      m -= 1;
      if (m < 1) {
        m = 12;
        y -= 1;
      }
    }
    return (y, m);
  }

  /// The week a day falls in, from the book's week start day.
  (DateTime, DateTime) week(DateTime d) {
    final dow = d.weekday % 7; // Sunday 0
    final back = (dow - weekStart + 7) % 7;
    final from = addDays(dayOnly(d), -back);
    return (from, addDays(from, 6));
  }

  /// The year a day falls in, from the financial year's first month.
  (DateTime, DateTime) year(DateTime d) {
    var y = d.year;
    if (d.month < fyStartMonth) y -= 1;
    final from = DateTime(y, fyStartMonth, 1);
    return (from, DateTime(y + 1, fyStartMonth, 1).subtract(const Duration(days: 1)));
  }

  /// The day names for a calendar row, starting on the week start day.
  List<String> get weekdayNames {
    const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return [for (var i = 0; i < 7; i++) names[(weekStart + i) % 7]];
  }
}

class Group {
  Group(this.j);
  final Map<String, dynamic> j;
  String get id => j['id'] as String;
  String get name => j['name'] as String? ?? '';
  String? get emoji => j['emoji'] as String?;
  String get kind => j['kind'] as String? ?? 'other';
  int get sort => (j['sort'] as num?)?.toInt() ?? 0;
  bool get hidden => j['hidden'] == true;
  bool get collapsed => j['collapsed'] == true;
  bool get deleted => j['deleted_at'] != null;
  String get label => emoji == null ? name : '$emoji $name';
}

/// The kinds of account group, in words.
const kGroupKinds = <String, String>{
  'cash': 'Cash',
  'bank': 'Bank account',
  'card': 'Credit card',
  'debit_card': 'Debit card',
  'prepaid': 'Wallet or prepaid',
  'savings': 'Savings',
  'investment': 'Investment',
  'loan': 'Loan',
  'insurance': 'Insurance',
  'overdraft': 'Overdraft',
  'other': 'Other',
};

class Account {
  Account(this.j, this.group);
  final Map<String, dynamic> j;
  final Group? group;
  String get id => j['id'] as String;
  String get groupId => j['group_id'] as String;
  String get name => j['name'] as String? ?? '';
  String get currency => j['currency'] as String? ?? 'INR';
  String get kind => group?.kind ?? 'other';
  num get opening => toNum(j['opening_balance']);
  String? get note => j['note'] as String?;
  bool get inTotals => j['in_totals'] != false;
  bool get hidden => j['hidden'] == true;
  bool get deleted => j['deleted_at'] != null;
  bool get transferExpense => j['transfer_expense'] == true;
  int get sort => (j['sort'] as num?)?.toInt() ?? 0;
  String? get billingAccountId => j['billing_account_id'] as String?;
  int? get settlementDay => (j['settlement_day'] as num?)?.toInt();
  int? get paymentDay => (j['payment_day'] as num?)?.toInt();
  bool get autoPay => j['auto_pay'] == true;
  String? get linkedAccountId => j['linked_account_id'] as String?;
  bool get isCard => kind == 'card';
  bool get isDebit => kind == 'debit_card';
  bool get canTransferExpense => const {'savings', 'investment', 'loan', 'insurance'}.contains(kind);
}

class Category {
  Category(this.j);
  final Map<String, dynamic> j;
  String get id => j['id'] as String;
  String get kind => j['kind'] as String? ?? 'expense';
  String? get parentId => j['parent_id'] as String?;
  String get name => j['name'] as String? ?? '';
  String? get emoji => j['emoji'] as String?;
  int get sort => (j['sort'] as num?)?.toInt() ?? 0;
  bool get deleted => j['deleted_at'] != null;
  String get label => emoji == null ? name : '$emoji $name';
}

/// Who is signed in, the book being worked in, and that book's accounts,
/// categories, tags and rates. Pages listen to it: after any save, call
/// [changed] and every page showing money loads again.
class Me extends ChangeNotifier {
  Me._();
  static final Me instance = Me._();

  String? userId;
  String? email;
  String? phone;
  List<Book> books = [];
  Book? book;

  List<Group> groups = [];
  List<Account> accounts = [];
  List<Category> categories = [];
  List<Map<String, dynamic>> tags = [];

  /// currency code -> how much of the main currency one unit is worth.
  Map<String, num> rates = {};

  /// Goes up by one after every change, so pages know to load again.
  int version = 0;

  /// Who is signed in and which books they have; then the book's lists.
  Future<void> load() async {
    final w = await Api.instance.rpc('whoami');
    final m = w is Map ? Map<String, dynamic>.from(w) : <String, dynamic>{};
    userId = m['id'] as String?;
    email = m['email'] as String?;
    phone = m['phone'] as String?;
    books = ((m['books'] as List?) ?? const []).whereType<Map>().map((b) => Book(Map<String, dynamic>.from(b))).toList();
    final want = Api.instance.bookId;
    book = books.where((b) => b.id == want).firstOrNull ?? books.firstOrNull;
    if (book != null && book!.id != want) await Api.instance.chooseBook(book!.id);
    if (book != null) {
      try {
        await Api.instance.rpc('catch_up');
      } catch (_) {
        // Repeats and card payments wait for the next time.
      }
      await loadLists(notify: false);
    }
    version++;
    notifyListeners();
  }

  Future<void> choose(String bookId) async {
    await Api.instance.chooseBook(bookId);
    await load();
  }

  /// The book's accounts, groups, categories, tags and rates.
  Future<void> loadLists({bool notify = true}) async {
    final r = await Future.wait([
      Api.instance.select('account_groups', order: 'sort,name'),
      Api.instance.select('accounts', order: 'sort,name'),
      Api.instance.select('categories', order: 'sort,name'),
      Api.instance.select('tags', order: 'name'),
      Api.instance.select('currency_rates'),
    ]);
    groups = r[0].map(Group.new).toList();
    final byId = {for (final g in groups) g.id: g};
    accounts = r[1].map((a) => Account(a, byId[a['group_id']])).toList()
      ..sort((a, b) {
        final ga = a.group?.sort ?? 0, gb = b.group?.sort ?? 0;
        return ga != gb ? ga.compareTo(gb) : (a.sort != b.sort ? a.sort.compareTo(b.sort) : a.name.compareTo(b.name));
      });
    categories = r[2].map(Category.new).toList();
    tags = r[3];
    rates = {for (final x in r[4]) x['currency'] as String: toNum(x['rate'])};
    if (notify) {
      version++;
      notifyListeners();
    }
  }

  /// After a save anywhere: reload the lists (when they may have changed) and
  /// tell every page.
  Future<void> changed({bool lists = false}) async {
    if (lists) {
      try {
        await loadLists(notify: false);
      } catch (_) {
        // The pages still reload what they show.
      }
    }
    version++;
    notifyListeners();
  }

  /// After the book's own settings changed (periods, carry-over).
  Future<void> reloadBook() => load();

  // ---------------------------------------------------------------- lookups

  Account? account(String? id) => id == null ? null : accounts.where((a) => a.id == id).firstOrNull;
  Category? category(String? id) => id == null ? null : categories.where((c) => c.id == id).firstOrNull;
  Group? group(String? id) => id == null ? null : groups.where((g) => g.id == id).firstOrNull;

  /// Accounts money can be put on now (not deleted), in the Accounts tab's order.
  List<Account> get liveAccounts => accounts.where((a) => !a.deleted && !(a.group?.deleted ?? false)).toList();

  /// Top-level categories of a kind, in order.
  List<Category> topCategories(String kind) =>
      categories.where((c) => c.kind == kind && c.parentId == null && !c.deleted).toList()..sort((a, b) => a.sort != b.sort ? a.sort.compareTo(b.sort) : a.name.compareTo(b.name));

  List<Category> subsOf(String id) =>
      categories.where((c) => c.parentId == id && !c.deleted).toList()..sort((a, b) => a.sort != b.sort ? a.sort.compareTo(b.sort) : a.name.compareTo(b.name));

  /// "Food / Groceries", or just "Food".
  String categoryPath(String? id) {
    final c = category(id);
    if (c == null) return '';
    final p = category(c.parentId);
    return p == null ? c.label : '${p.label} / ${c.name}';
  }

  /// How much of the main currency one unit of a currency is worth (1 for the main one).
  num? rateOf(String currency) => currency == book?.currency ? 1 : rates[currency];

  /// An amount in another currency, in the main one (null when the rate is not set).
  num? toMain(num amount, String currency) {
    final r = rateOf(currency);
    return r == null ? null : amount * r;
  }

  void signOut() {
    userId = null;
    books = [];
    book = null;
    groups = [];
    accounts = [];
    categories = [];
    tags = [];
    rates = {};
    version++;
    notifyListeners();
  }
}

/// A transaction as txn_list() returns it.
class Txn {
  Txn(this.j);
  final Map<String, dynamic> j;
  String get id => j['id'] as String;
  String get kind => j['kind'] as String? ?? 'expense';
  DateTime get at => parseStamp(j['at']) ?? DateTime.now();
  DateTime get day => dayOnly(at);
  String get accountId => j['account_id'] as String;
  String get account => j['account'] as String? ?? '';
  String get currency => j['currency'] as String? ?? 'INR';
  String? get toAccountId => j['to_account_id'] as String?;
  String get toAccount => j['to_account'] as String? ?? '';
  String? get toCurrency => j['to_currency'] as String?;
  String? get categoryId => j['category_id'] as String?;
  String? get category => j['category'] as String?;
  String? get emoji => j['emoji'] as String?;
  String? get parentId => j['parent_id'] as String?;
  String? get parent => j['parent'] as String?;
  String? get parentEmoji => j['parent_emoji'] as String?;
  num get amount => toNum(j['amount']);
  num? get toAmount => j['to_amount'] == null ? null : toNum(j['to_amount']);
  num get fee => toNum(j['fee']);
  num get rate => toNum(j['rate'] ?? 1);
  num get amountMain => toNum(j['amount_main']);
  String? get note => j['note'] as String?;
  String? get description => j['description'] as String?;
  String? get repeatId => j['repeat_id'] as String?;
  String? get planId => j['plan_id'] as String?;
  int? get planNo => (j['plan_no'] as num?)?.toInt();
  int? get planMonths => (j['plan_months'] as num?)?.toInt();

  /// What the row counts as: income, expense, transfer, or card (card
  /// spending that counts as a lump on payment day).
  String get countsAs => j['counts_as'] as String? ?? kind;
  List<String> get tags => ((j['tags'] as List?) ?? const []).map((e) => '$e').toList();
  int get photos => (j['photos'] as num?)?.toInt() ?? 0;
  List<Map<String, dynamic>> get splits => ((j['splits'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  /// The top line of a row: the category (parent first), or Transfer.
  String get title {
    if (kind == 'transfer') return 'Transfer';
    if (splits.isNotEmpty) return 'Split';
    if (parent != null) return '${parentEmoji ?? ''}${parentEmoji == null ? '' : ' '}$parent';
    if (category != null) return '${emoji ?? ''}${emoji == null ? '' : ' '}$category';
    return 'Uncategorised';
  }

  /// The subcategory under the title, when there is one.
  String? get subtitle => parent != null ? category : null;
}
