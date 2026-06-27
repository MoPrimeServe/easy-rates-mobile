// services.dart — process-wide singletons shared by AuthService and OtpService.
//
// The screens construct `AuthService()` / `OtpService()` with no arguments, yet
// the auth flow (register/verify-LOGIN) and the OTP flow must write to the SAME
// token store and use the SAME 401-refresh client. So both services default to
// these shared singletons rather than spinning up a private Dio per service.
//
// Tests inject their own ApiClient/TokenStore via the constructors instead.

import 'api_client.dart';
import 'token_store.dart';

/// The one refresh/access token holder for the running app.
final TokenStore sharedTokenStore = TokenStore();

/// The one Dio client (envelope unwrap + 401-refresh-retry) for the running app,
/// wired to [sharedTokenStore].
final ApiClient sharedApiClient = ApiClient(tokenStore: sharedTokenStore);
