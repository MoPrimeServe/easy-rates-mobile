// api_response.dart — the error half of the `{ data, error }` envelope that every
// EasyRates endpoint returns (api/conventions.md §2). The client switches on
// [ApiError.code] (snake_case, machine-readable), NEVER on the HTTP status — several
// codes share a status (e.g. three different 429s).
//
// On success the envelope's `data` is parsed into the endpoint's typed payload by the
// service layer; only the error half needs a shared model here.

class ApiError implements Exception {
  final String code; // snake_case, e.g. otp_expired, resend_cooldown_active
  final String message; // human-readable; safe to show in the UI
  final Map<String, dynamic> details; // always an object; may be {}

  const ApiError({
    required this.code,
    required this.message,
    this.details = const {},
  });

  @override
  String toString() => 'ApiError($code: $message)';
}
