/// Philippine mobile number normalisation.
///
/// Supabase Auth requires E.164 (`+639171234567`). Real users do not type
/// E.164. In the Philippines the same number is written at least five ways:
///
///   0917 123 4567      the way it is said out loud and printed on receipts
///   09171234567        the way it is stored in most phonebooks
///   +639171234567      E.164
///   639171234567       E.164 without the plus, common in exported CSVs
///   917 123 4567       when the leading zero is assumed
///
/// A driver signing up on a low-end phone will type whichever they know. If the
/// app forwards that string unchanged, Supabase rejects it or — worse — accepts
/// something that never reaches a handset, and the account is stranded with no
/// way to verify. So normalise here, and reject at the form rather than at the
/// gateway.
///
/// Deliberately not a package. `libphonenumber` and friends pull in a large
/// metadata blob to solve a global problem; this app serves one city in one
/// country, and the rule fits in a page.
library;

/// The result of normalising a user-entered mobile number.
class PhMobileNumber {
  const PhMobileNumber._({this.e164, this.error});

  /// `+639XXXXXXXXX`, ready for Supabase. Null when [error] is set.
  final String? e164;

  /// A message safe to show under the text field. Null on success.
  final String? error;

  bool get isValid => e164 != null;

  /// `0917 123 4567` — how a Filipino user expects to see their own number
  /// read back to them. Falls back to the raw E.164 if anything is unexpected.
  String get display {
    final value = e164;
    if (value == null || value.length != 13) return value ?? '';
    final national = '0${value.substring(3)}';
    return '${national.substring(0, 4)} ${national.substring(4, 7)} '
        '${national.substring(7)}';
  }

  /// `+63 917 *** 4567` — for a verify screen, where the user needs to confirm
  /// they recognise the number without it being fully readable over a shoulder.
  String get masked {
    final value = e164;
    if (value == null || value.length != 13) return '';
    return '+63 ${value.substring(3, 6)} *** ${value.substring(9)}';
  }
}

/// Philippine mobile numbers are `9` followed by nine digits, after the
/// `+63` country code. Landlines and short codes are not mobile numbers and
/// cannot receive an OTP the way this flow expects.
const int _nationalLength = 10;

PhMobileNumber normalizePhMobile(String? input) {
  final raw = (input ?? '').trim();
  if (raw.isEmpty) {
    return const PhMobileNumber._(error: 'Enter your mobile number.');
  }

  // Strip everything a human might use as a separator: spaces, dashes,
  // parentheses, dots. Keep a leading plus only to detect intent; the digits
  // are what matter.
  final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) {
    return const PhMobileNumber._(error: 'Enter your mobile number.');
  }

  // Order matters. The bare-national branch is guarded on a leading 9 so that
  // a ten-digit string like 0917123456 -- an ordinary 09xx number with a digit
  // missing -- falls through to the length message rather than being read as a
  // national-format number and rejected with "should start with 09", which is
  // baffling advice when the user did type 09.
  String national;
  if (digits.startsWith('63') && digits.length == _nationalLength + 2) {
    // 639171234567 or +639171234567
    national = digits.substring(2);
  } else if (digits.startsWith('0') && digits.length == _nationalLength + 1) {
    // 09171234567
    national = digits.substring(1);
  } else if (digits.startsWith('9') && digits.length == _nationalLength) {
    // 9171234567, leading zero assumed
    national = digits;
  } else if (digits.startsWith('0') || digits.startsWith('9')) {
    // Looks like a Philippine mobile, wrong number of digits.
    return const PhMobileNumber._(
      error: 'Enter all 11 digits, like 0917 123 4567.',
    );
  } else {
    return const PhMobileNumber._(
      error: 'Enter a Philippine mobile number, like 0917 123 4567.',
    );
  }

  if (!national.startsWith('9')) {
    return const PhMobileNumber._(
      error: 'That does not look like a mobile number. It should start with 09.',
    );
  }

  return PhMobileNumber._(e164: '+63$national');
}
