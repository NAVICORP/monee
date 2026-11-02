/// Numbers, money, dates and names the way Monee writes them.
library;

const List<String> kMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const List<String> kMonthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const List<String> kDaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// 65000 as "65,000" and 150000 as "1,50,000" (Indian grouping).
String groupDigits(num value) {
  final negative = value < 0;
  var s = value.abs().truncate().toString();
  if (s.length > 3) {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    s = '${parts.join(',')},$last3';
  }
  return negative ? '-$s' : s;
}

/// 150000 as "150,000" (groups of three).
String groupThousands(num value) {
  final negative = value < 0;
  final s = value.abs().truncate().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return negative ? '-$b' : b.toString();
}

/// A currency as Monee writes it: its sign, how many decimals it keeps, and
/// whether its digits group the Indian way (1,50,000).
class Currency {
  const Currency(this.code, this.symbol, this.name, {this.decimals = 2, this.indian = false, this.spaced = false});
  final String code;
  final String symbol;
  final String name;
  final int decimals;
  final bool indian;
  final bool spaced;

  /// The amount with its sign and every decimal the currency keeps: ₹1,750.00, SAR 12.50, BHD 4.700.
  String format(num value, {bool symbol = true, bool sign = false}) {
    final digits = number(value.abs());
    final minus = value < 0 && digits.replaceAll(RegExp(r'[0.,]'), '').isNotEmpty ? '-' : (sign && value > 0 ? '+' : '');
    if (!symbol) return '$minus$digits';
    return spaced ? '$minus${this.symbol} $digits' : '$minus${this.symbol}$digits';
  }

  /// The digits alone, grouped, with the currency's decimals.
  String number(num value) {
    final f = _pow(decimals);
    final v = (value * f).round() / f;
    final whole = indian ? groupDigits(v.truncate()) : groupThousands(v.truncate());
    if (decimals == 0) return whole;
    final frac = ((v.abs() - v.abs().truncate()) * f).round().toString().padLeft(decimals, '0');
    return '$whole.$frac';
  }

  static int _pow(int n) => n <= 0 ? 1 : 10 * _pow(n - 1);
}

const List<Currency> kCurrencies = [
  Currency('INR', '₹', 'Indian rupee', indian: true),
  Currency('SAR', 'SAR', 'Saudi riyal', spaced: true),
  Currency('AED', 'AED', 'UAE dirham', spaced: true),
  Currency('QAR', 'QAR', 'Qatari riyal', spaced: true),
  Currency('KWD', 'KWD', 'Kuwaiti dinar', decimals: 3, spaced: true),
  Currency('OMR', 'OMR', 'Omani rial', decimals: 3, spaced: true),
  Currency('BHD', 'BD', 'Bahraini dinar', decimals: 3, spaced: true),
  Currency('USD', r'$', 'US dollar'),
  Currency('EUR', '€', 'Euro'),
  Currency('GBP', '£', 'British pound'),
  Currency('CAD', r'CA$', 'Canadian dollar'),
  Currency('AUD', r'A$', 'Australian dollar'),
  Currency('NZD', r'NZ$', 'New Zealand dollar'),
  Currency('SGD', r'S$', 'Singapore dollar'),
  Currency('MYR', 'RM', 'Malaysian ringgit'),
  Currency('IDR', 'Rp', 'Indonesian rupiah', decimals: 0, spaced: true),
  Currency('PHP', '₱', 'Philippine peso'),
  Currency('THB', '฿', 'Thai baht'),
  Currency('VND', '₫', 'Vietnamese dong', decimals: 0),
  Currency('JPY', '¥', 'Japanese yen', decimals: 0),
  Currency('CNY', 'CN¥', 'Chinese yuan'),
  Currency('KRW', '₩', 'South Korean won', decimals: 0),
  Currency('HKD', r'HK$', 'Hong Kong dollar'),
  Currency('LKR', 'Rs', 'Sri Lankan rupee', spaced: true),
  Currency('PKR', 'Rs', 'Pakistani rupee', spaced: true),
  Currency('BDT', '৳', 'Bangladeshi taka'),
  Currency('NPR', 'Rs', 'Nepalese rupee', spaced: true),
  Currency('EGP', 'E£', 'Egyptian pound'),
  Currency('JOD', 'JD', 'Jordanian dinar', decimals: 3, spaced: true),
  Currency('TRY', '₺', 'Turkish lira'),
  Currency('ZAR', 'R', 'South African rand', spaced: true),
  Currency('NGN', '₦', 'Nigerian naira'),
  Currency('KES', 'KSh', 'Kenyan shilling', spaced: true),
  Currency('GHS', 'GH₵', 'Ghanaian cedi'),
  Currency('CHF', 'CHF', 'Swiss franc', spaced: true),
  Currency('SEK', 'kr', 'Swedish krona', spaced: true),
  Currency('NOK', 'kr', 'Norwegian krone', spaced: true),
  Currency('DKK', 'kr', 'Danish krone', spaced: true),
  Currency('PLN', 'zł', 'Polish zloty', spaced: true),
  Currency('RUB', '₽', 'Russian ruble'),
  Currency('BRL', r'R$', 'Brazilian real'),
  Currency('MXN', r'MX$', 'Mexican peso'),
];

Currency currencyOf(String? code) {
  final c = (code ?? '').trim().toUpperCase();
  for (final x in kCurrencies) {
    if (x.code == c) return x;
  }
  return c.length == 3 ? Currency(c, c, c, spaced: true) : kCurrencies.first;
}

/// ₹1,750.00 or SAR 1,750.00.
String money(num? value, [String? currency]) => currencyOf(currency).format(value ?? 0);

/// The digits alone: 1,750.00.
String amountText(num? value, [String? currency]) => currencyOf(currency).format(value ?? 0, symbol: false);

num toNum(Object? v) => v is num ? v : num.tryParse('${v ?? ''}') ?? 0;

/// A rate without trailing zeros: 0.044, 22.5.
String rateText(num v) {
  var s = v.toStringAsFixed(6);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  return s;
}

// ---------------------------------------------------------------- dates

/// A date as the database writes it: 2026-10-28.
String isoDay(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseDay(Object? v) {
  if (v is! String || v.length < 10) return null;
  return DateTime.tryParse(v.substring(0, 10));
}

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Wed 28 Oct
String dayLabel(DateTime d) => '${kDaysShort[d.weekday - 1]} ${d.day} ${kMonthsShort[d.month - 1]}';

/// 28 Oct 2026
String dateLabel(DateTime d) => '${d.day} ${kMonthsShort[d.month - 1]} ${d.year}';

/// 28 Oct, or 28 Oct 2025 when not this year.
String shortDate(DateTime d, [DateTime? now]) {
  final n = now ?? DateTime.now();
  return d.year == n.year ? '${d.day} ${kMonthsShort[d.month - 1]}' : dateLabel(d);
}

/// October 2026
String monthLabel(DateTime d) => '${kMonths[d.month - 1]} ${d.year}';

/// today, tomorrow, yesterday, or Wed 28 Oct: for the middle of a sentence.
String dayInSentence(DateTime d, DateTime today) {
  final r = relativeDay(d, today);
  return r == 'Today' || r == 'Tomorrow' || r == 'Yesterday' ? r.toLowerCase() : r;
}

/// today, tomorrow, yesterday, or on Wed 28 Oct.
String onDay(DateTime d, DateTime today) {
  final r = dayInSentence(d, today);
  return r == 'today' || r == 'tomorrow' || r == 'yesterday' ? r : 'on $r';
}

/// Today, Tomorrow, Yesterday, or Wed 28 Oct.
String relativeDay(DateTime d, DateTime today) {
  final diff = dayOnly(d).difference(dayOnly(today)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return dayLabel(d);
}

/// 1 Oct to 15 Oct
String periodLabel(DateTime a, DateTime b) =>
    a.year == b.year ? '${a.day} ${kMonthsShort[a.month - 1]} to ${b.day} ${kMonthsShort[b.month - 1]} ${b.year}' : '${dateLabel(a)} to ${dateLabel(b)}';

/// 7:31 pm
String clock(DateTime d) {
  final h = d.hour, m = d.minute;
  final hh = (h % 12) == 0 ? 12 : h % 12;
  return '$hh:${m.toString().padLeft(2, '0')} ${h < 12 ? 'am' : 'pm'}';
}

/// "06:00:00" from the database as 6:00 am.
String timeOfDay(Object? v) {
  final s = '${v ?? ''}';
  final p = s.split(':');
  if (p.length < 2) return s;
  final h = int.tryParse(p[0]) ?? 0, m = int.tryParse(p[1]) ?? 0;
  return clock(DateTime(2000, 1, 1, h, m));
}

/// 20 Oct, 7:31 pm
String stamp(DateTime d) => '${shortDate(d)}, ${clock(d.toLocal())}';

// ---------------------------------------------------------------- people

/// Digits only, with the country code; 10 digits on their own are Indian.
String phoneDigits(String raw, {String defaultCountry = '91'}) {
  final t = raw.trim();
  var d = t.replaceAll(RegExp(r'[^0-9]'), '');
  if (t.startsWith('00')) d = d.substring(2);
  if (t.startsWith('+') || t.startsWith('00')) return d;
  if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
  if (d.length == 10) return '$defaultCountry$d';
  return d;
}

/// +91 90721 50276
String prettyPhone(String? digits) {
  final d = (digits ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return '';
  if (d.length == 12 && d.startsWith('91')) return '+91 ${d.substring(2, 7)} ${d.substring(7)}';
  return '+$d';
}

/// The number without the country code, as people say it: 9895177896.
String localPhone(String? digits) {
  final d = (digits ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  return d.length > 10 ? d.substring(d.length - 10) : d;
}

/// Up to two letters for an avatar.
String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  String first(String s) => String.fromCharCodes(s.runes.take(1));
  if (parts.length == 1) return first(parts.first).toUpperCase();
  return (first(parts.first) + first(parts.last)).toUpperCase();
}

/// A CSV cell: quoted when it needs to be.
String csvCell(Object? v) {
  final s = v == null ? '' : '$v';
  if (s.contains(RegExp(r'[",\n\r]'))) return '"${s.replaceAll('"', '""')}"';
  return s;
}

/// 28.10 (the Monthly list's week ranges).
String dotDay(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

/// A timestamp from the database (no time zone: the book's own clock).
DateTime? parseStamp(Object? v) => v is String ? DateTime.tryParse(v.replaceFirst(' ', 'T')) : null;

/// 2026-10-28T13:05:00, for the database.
String isoStamp(DateTime d) => '${isoDay(d)}T${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:00';
