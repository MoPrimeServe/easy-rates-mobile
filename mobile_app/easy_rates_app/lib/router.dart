import 'package:go_router/go_router.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/account_lookup/account_lookup_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/login/login_screen.dart';
import 'screens/signup/signup_screen.dart';
import 'screens/otp/otp_screen.dart';
import 'screens/gallery/gallery_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/pay/pay_screen.dart';
import 'screens/success/success_screen.dart';
import 'screens/usage/usage_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, _) => const SplashScreen()),
    GoRoute(path: '/onboarding', builder: (context, _) => const OnboardingScreen()),
    GoRoute(path: '/account-lookup', builder: (context, _) => const AccountLookupScreen()),
    GoRoute(path: '/dashboard', builder: (context, _) => const DashboardScreen()),
    GoRoute(path: '/login', builder: (context, _) => const LoginScreen()),
    GoRoute(path: '/signup', builder: (context, _) => const SignUpScreen()),
    GoRoute(
      path: '/otp',
      builder: (context, state) => OtpScreen(args: state.extra as OtpArgs),
    ),
    GoRoute(path: '/gallery', builder: (context, _) => const GalleryScreen()),
    GoRoute(path: '/home', builder: (context, _) => const HomeScreen()),
    GoRoute(path: '/pay',     builder: (context, _) => const PayScreen()),
    GoRoute(
      path: '/success',
      builder: (context, state) => SuccessScreen(
        amount: (state.extra as double?) ?? 1250.00,
      ),
    ),
    GoRoute(path: '/usage',   builder: (context, _) => const UsageScreen()),
  ],
);
