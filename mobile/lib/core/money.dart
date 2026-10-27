import 'package:intl/intl.dart';

/// Exact money value stored as integer minor units (2 decimal places).
///
/// The API sends amounts as decimal strings; we never parse them into
/// `double`. Client-side totals are previews only — the server's figures are
/// authoritative.
class Money implements Comparable<Money> {
  const Money._(this.minor);

  final BigInt minor;

  static final Money zero = Money._(BigInt.zero);

  factory Money.fromMinor(BigInt minor) => Money._(minor);

  factory Money.whole(int units) => Money._(BigInt.from(units) * BigInt.from(100));

  /// Parses "1234", "1234.5", "1234.50" or "-12.30". Throws [FormatException] otherwise.
  factory Money.parse(String input) {
    final s = input.trim().replaceAll(',', '');
    final match = RegExp(r'^(-)?(\d+)(?:\.(\d{1,2}))?$').firstMatch(s);
    if (match == null) throw FormatException('Not a valid amount', input);
    final whole = BigInt.parse(match.group(2)!);
    final frac = BigInt.parse((match.group(3) ?? '0').padRight(2, '0'));
    final value = whole * BigInt.from(100) + frac;
    return Money._(match.group(1) == null ? value : -value);
  }

  static Money? tryParse(String? input) {
    if (input == null || input.trim().isEmpty) return null;
    try {
      return Money.parse(input);
    } on FormatException {
      return null;
    }
  }

  Money operator +(Money other) => Money._(minor + other.minor);
  Money operator -(Money other) => Money._(minor - other.minor);

  /// Multiply by an exact decimal quantity (see [Quantity]), rounding half-up to the cent.
  Money times(Quantity q) {
    final product = minor * q.thousandths; // scaled by 1000
    final thousand = BigInt.from(1000);
    final half = BigInt.from(500);
    final rounded = product.isNegative ? -(((-product) + half) ~/ thousand) : (product + half) ~/ thousand;
    return Money._(rounded);
  }

  bool get isZero => minor == BigInt.zero;
  bool get isNegative => minor.isNegative;

  @override
  int compareTo(Money other) => minor.compareTo(other.minor);
  bool operator >(Money o) => minor > o.minor;
  bool operator <(Money o) => minor < o.minor;
  bool operator >=(Money o) => minor >= o.minor;
  bool operator <=(Money o) => minor <= o.minor;

  @override
  bool operator ==(Object other) => other is Money && other.minor == minor;

  @override
  int get hashCode => minor.hashCode;

  /// Canonical API representation, e.g. "450000.00".
  String toApi() {
    final abs = minor.abs();
    final whole = abs ~/ BigInt.from(100);
    final cents = (abs % BigInt.from(100)).toString().padLeft(2, '0');
    return '${minor.isNegative ? '-' : ''}$whole.$cents';
  }

  /// Human format, e.g. "UGX 450,000" (cents shown only when present).
  String format(String currency, {bool showCurrency = true}) {
    final abs = minor.abs();
    final whole = abs ~/ BigInt.from(100);
    final cents = abs % BigInt.from(100);
    final grouped = NumberFormat.decimalPattern('en').format(whole.toInt());
    final body = cents == BigInt.zero ? grouped : '$grouped.${cents.toString().padLeft(2, '0')}';
    final sign = minor.isNegative ? '-' : '';
    return showCurrency ? '$sign$currency $body' : '$sign$body';
  }

  @override
  String toString() => toApi();
}

/// Exact quantity with 3 decimal places (stored as thousandths).
class Quantity {
  const Quantity._(this.thousandths);

  final BigInt thousandths;

  factory Quantity.whole(int n) => Quantity._(BigInt.from(n) * BigInt.from(1000));

  factory Quantity.parse(String input) {
    final match = RegExp(r'^(-)?(\d+)(?:\.(\d{1,3}))?$').firstMatch(input.trim());
    if (match == null) throw FormatException('Not a valid quantity', input);
    final v =
        BigInt.parse(match.group(2)!) * BigInt.from(1000) + BigInt.parse((match.group(3) ?? '0').padRight(3, '0'));
    return Quantity._(match.group(1) == null ? v : -v);
  }

  static Quantity? tryParse(String? input) {
    if (input == null) return null;
    try {
      return Quantity.parse(input);
    } on FormatException {
      return null;
    }
  }

  Quantity operator +(Quantity o) => Quantity._(thousandths + o.thousandths);
  Quantity operator -(Quantity o) => Quantity._(thousandths - o.thousandths);
  bool operator >(Quantity o) => thousandths > o.thousandths;
  bool operator <=(Quantity o) => thousandths <= o.thousandths;
  bool get isPositive => thousandths > BigInt.zero;

  @override
  bool operator ==(Object other) => other is Quantity && other.thousandths == thousandths;

  @override
  int get hashCode => thousandths.hashCode;

  @override
  String toString() {
    final abs = thousandths.abs();
    final whole = abs ~/ BigInt.from(1000);
    final frac = (abs % BigInt.from(1000)).toString().padLeft(3, '0').replaceFirst(RegExp(r'0+$'), '');
    return '${thousandths.isNegative ? '-' : ''}$whole${frac.isEmpty ? '' : '.$frac'}';
  }
}
