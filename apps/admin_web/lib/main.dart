import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsHandle;
import 'package:flutter/services.dart' show TextInput;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_controller.dart';
import 'app_config.dart';
import 'models.dart';
import 'screens.dart';
import 'session.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Semantics is forced on only inside the signed-in console (see
  // _ConsoleSemantics). Forcing it app-wide made Flutter Web render the
  // login fields as accessibility-tree inputs, where the password input is
  // autocomplete="off" -- so browsers and password managers filled the email
  // but never the password. Screen readers still reach the login page through
  // Flutter's built-in accessibility activation.
  // Flutter Web defaults to hash-based URLs (/#/dashboard). Every route
  // before /accept-invite (Spec 19) was only ever reached by clicking
  // around *inside* the already-loaded app, where that default is
  // invisible -- client-side navigation works the same either way.
  // /accept-invite is the first route ever opened as a fresh page load
  // from an external link (the invite email), and that is exactly where
  // hash-routing breaks: the router only reads the # fragment, which is
  // empty for a plain https://admin.arangcada.app/accept-invite?token=...
  // URL, so it silently fell back to /login and the token was never read.
  // wrangler.jsonc's own not_found_handling: "single-page-application"
  // already anticipated clean-path URLs; this is what actually turns it on.
  usePathUrlStrategy();
  if (AdminAppConfig.isSupabaseConfigured) {
    await Supabase.initialize(
      url: AdminAppConfig.supabaseUrl,
      publishableKey: AdminAppConfig.supabaseAnonKey,
    );
  }
  final preferences = await SharedPreferences.getInstance();
  final savedAppearance = preferences.getString('admin-appearance');
  adminThemeMode.value = ThemeMode.values.firstWhere(
    (mode) => mode.name == savedAppearance,
    orElse: () => ThemeMode.system,
  );
  runApp(const ProviderScope(child: AdminApp()));
}

Widget _consolePage(Widget child) => LayoutBuilder(
  builder: (context, constraints) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      constraints.maxWidth < 600 ? 16 : 32,
      constraints.maxWidth < 600 ? 16 : 28,
      constraints.maxWidth < 600 ? 16 : 32,
      40,
    ),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1500),
        child: child,
      ),
    ),
  ),
);

class AdminApp extends ConsumerStatefulWidget {
  const AdminApp({super.key, this.initialLocation = '/login'});

  final String initialLocation;

  @override
  ConsumerState<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends ConsumerState<AdminApp> {
  late final GoRouter router = GoRouter(
    initialLocation: widget.initialLocation,
    refreshListenable: Listenable.merge([auth, authRestoring]),
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/login';
      // A recipient opening an invite link has no session at all -- this
      // route is public by design, same as /login, and must not bounce them
      // there. See .pipeline/specs.md Spec 19.
      final acceptingInvite =
          state.matchedLocation == '/accept-invite' ||
          state.matchedLocation == '/accept-driver-invite' ||
          state.matchedLocation == '/reset-password';

      // While a persisted session from local storage is being restored,
      // do not bounce the browser away to /login so the requested deep link
      // or refreshed route (/admins, /drivers, etc.) is preserved.
      if (authRestoring.value) {
        return null;
      }

      if (auth.value == null && !loggingIn && !acceptingInvite) {
        final uri = state.uri.toString();
        if (uri != '/' && uri != '/login') {
          return '/login?from=${Uri.encodeComponent(uri)}';
        }
        return '/login';
      }

      if (auth.value != null && (loggingIn || state.matchedLocation == '/')) {
        final from = state.uri.queryParameters['from'];
        if (from != null && from.startsWith('/') && !from.startsWith('//')) {
          return from;
        }
        return '/dashboard';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        redirect: (context, state) =>
            auth.value != null ? '/dashboard' : '/login',
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      // Opened from the "Forgot password?" email -- public, like the invites.
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/accept-invite',
        builder: (context, state) =>
            AcceptInviteScreen(token: state.uri.queryParameters['token']),
      ),
      // Driver enrollment (Spec 20) -- same public, no-session shape as
      // /accept-invite above.
      GoRoute(
        path: '/accept-driver-invite',
        builder: (context, state) =>
            AcceptDriverInviteScreen(token: state.uri.queryParameters['token']),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AdminShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            // Fits the viewport itself; see DashboardScreen.
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/live-map',
            builder: (context, state) => _consolePage(const LiveMapScreen()),
          ),
          GoRoute(
            path: '/drivers',
            builder: (context, state) => _consolePage(const DriversScreen()),
          ),
          GoRoute(
            path: '/admins',
            builder: (context, state) => _consolePage(const AdminsScreen()),
          ),
          GoRoute(
            path: '/safety',
            builder: (context, state) => _consolePage(const SafetyScreen()),
          ),
          // Folded into Safety reports as a compact panel (Spec 19
          // follow-up) -- redirect rather than delete, so an old bookmark
          // or link still lands somewhere real instead of 404ing.
          GoRoute(path: '/complaints', redirect: (context, state) => '/safety'),
          GoRoute(
            path: '/reviews',
            builder: (context, state) => _consolePage(const ReviewsScreen()),
          ),
          GoRoute(
            path: '/discount-claims',
            builder: (context, state) => _consolePage(const ClaimsScreen()),
          ),
          // The Evaluation sub-pages are flat sibling routes sharing one page
          // key: switching tabs updates that page in place (no page
          // transition) and EvaluationScreen slides only the tab content.
          for (final section in EvaluationSection.values)
            GoRoute(
              path: section.location,
              pageBuilder: (context, state) => NoTransitionPage(
                key: const ValueKey('evaluation'),
                child: _consolePage(EvaluationScreen(section: section)),
              ),
            ),
          GoRoute(path: '/survey', redirect: (context, state) => '/evaluation'),
          GoRoute(
            path: '/settings',
            builder: (context, state) => _consolePage(const SettingsScreen()),
          ),
        ],
      ),
    ],
  );

  @override
  void initState() {
    super.initState();
    final repository = ref.read(adminRepositoryProvider);
    // A reset link arrives with a recovery session; it must only be used to
    // choose a new password, never to open the console.
    final openingResetLink =
        Uri.base.path == '/reset-password' ||
        widget.initialLocation.startsWith('/reset-password');
    if ((repository?.hasSession ?? false) &&
        auth.value == null &&
        !openingResetLink) {
      authRestoring.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSession());
    }
  }

  Future<void> _restoreSession() async {
    final repository = ref.read(adminRepositoryProvider);
    if (repository == null || !repository.hasSession || auth.value != null) {
      authRestoring.value = false;
      return;
    }
    try {
      final session = await repository.restoreSession();
      await ref.read(adminProvider.notifier).connect(session);
      if (mounted) {
        auth.value = session;
      }
    } catch (_) {
      try {
        await repository.client.auth.signOut();
      } catch (_) {}
      if (mounted) {
        auth.value = null;
        authError.value = 'Your administrator session expired. Sign in again.';
      }
    } finally {
      authRestoring.value = false;
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
    valueListenable: adminThemeMode,
    builder: (context, mode, _) => MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'ArangCada Admin',
      theme: adminTheme(),
      darkTheme: adminTheme(brightness: Brightness.dark),
      themeMode: mode,
      routerConfig: router,
    ),
  );
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool obscure = true;
  bool submitting = false;
  String? signInError;

  @override
  void initState() {
    super.initState();
    signInError = authError.value;
    authError.value = null;
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() {
      submitting = true;
      signInError = null;
    });
    try {
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) {
        throw StateError('The administrator service is not configured.');
      }
      final session = await repository.signIn(
        email: email.text,
        password: password.text,
      );
      await ref.read(adminProvider.notifier).connect(session);
      // Tells the browser the credential form was submitted successfully, so
      // it offers to save or update the password.
      TextInput.finishAutofillContext();
      if (mounted) auth.value = session;
    } catch (_) {
      if (mounted) {
        setState(
          () => signInError =
              'Unable to sign in. Check your credentials and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: authRestoring,
      builder: (context, restoring, _) {
        if (restoring) {
          return const AdminLoadingScreen(label: 'Restoring your account');
        }
        final effectiveError = signInError ?? authError.value;
        return Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final hero = Container(
                decoration: const BoxDecoration(gradient: adminBrandGradient),
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 40,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const BrandTile(size: 96),
                            const SizedBox(height: 40),
                            Text(
                              'ARANGCADA · CALAMBA CITY LGU & TODA',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: AdminColors.railTextMuted,
                                    letterSpacing: 1.6,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 480),
                              child: Text(
                                'Local dispatch.\nClearer oversight.',
                                style: Theme.of(context).textTheme.displaySmall
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontSize: 44,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: -1.2,
                                      height: 1.12,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 440),
                              child: Text(
                                'Manage drivers, follow trips, and support your local TODA from one place.',
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: AdminColors.railText,
                                      fontSize: 17,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Administrator console · Calamba City pilot',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: AdminColors.railTextMuted,
                                    fontSize: 13,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
              final form = Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(wide ? 48 : 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AutofillGroup(
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Align(
                              alignment: Alignment.centerRight,
                              child: AdminAppearanceButton(),
                            ),
                            Text(
                              'Welcome back',
                              style: Theme.of(context).textTheme.headlineLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Use your assigned LGU or TODA administrator account.',
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: context.adminColor(
                                      AdminColors.muted,
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 32),
                            TextFormField(
                              controller: email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              autofillHints: const [
                                AutofillHints.username,
                                AutofillHints.email,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(Icons.mail_outline),
                              ),
                              validator: (value) =>
                                  value != null && value.contains('@')
                                  ? null
                                  : 'Enter a valid email address.',
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: password,
                              obscureText: obscure,
                              autofillHints: const [AutofillHints.password],
                              onFieldSubmitted: (_) => submit(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  tooltip: obscure
                                      ? 'Show password'
                                      : 'Hide password',
                                  onPressed: () =>
                                      setState(() => obscure = !obscure),
                                  icon: Icon(
                                    obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: (value) => (value?.length ?? 0) >= 6
                                  ? null
                                  : 'Use at least 6 characters.',
                            ),
                            const SizedBox(height: 20),
                            if (effectiveError != null) ...[
                              Text(
                                effectiveError,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: context.adminColor(
                                        AdminColors.danger,
                                      ),
                                    ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            FilledButton.icon(
                              onPressed: submitting ? null : submit,
                              icon: submitting
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.arrow_forward),
                              label: Text(
                                submitting ? 'Signing in…' : 'Open console',
                              ),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(54),
                              ),
                            ),
                            if (AdminAppConfig.isSupabaseConfigured) ...[
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.center,
                                child: TextButton(
                                  onPressed: submitting
                                      ? null
                                      : () => _showForgotPassword(context, ref),
                                  child: const Text('Forgot password?'),
                                ),
                              ),
                            ],
                            const SizedBox(height: 14),
                            Text(
                              'For authorized LGU and TODA administrators.',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
              return wide
                  ? Row(
                      children: [
                        // The brand panel keeps a fixed share so wide monitors
                        // widen the form's breathing room, not the blue.
                        SizedBox(
                          width: (constraints.maxWidth * .42).clamp(
                            460.0,
                            720.0,
                          ),
                          child: hero,
                        ),
                        Expanded(child: form),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            decoration: const BoxDecoration(
                              gradient: adminBrandGradient,
                            ),
                            padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                            child: SafeArea(
                              bottom: false,
                              child: Row(
                                children: [
                                  const BrandTile(size: 40),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'ArangCada Admin',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          form,
                        ],
                      ),
                    );
            },
          ),
        );
      },
    );
  }
}

Future<void> _showForgotPassword(BuildContext context, WidgetRef ref) async {
  final formKey = GlobalKey<FormState>();
  final resetEmail = TextEditingController();
  bool sending = false;
  bool sent = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Reset your password'),
        content: sent
            ? const Text(
                'If that address matches an account, a reset link has been sent.',
              )
            : SizedBox(
                width: 380,
                child: Form(
                  key: formKey,
                  child: TextFormField(
                    controller: resetEmail,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email address',
                    ),
                    validator: (value) => (value?.contains('@') ?? false)
                        ? null
                        : 'Enter a valid email address.',
                  ),
                ),
              ),
        actions: sent
            ? [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ]
            : [
                TextButton(
                  onPressed: sending
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: sending
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => sending = true);
                          try {
                            await ref
                                .read(adminRepositoryProvider)!
                                .sendPasswordReset(resetEmail.text);
                            setDialogState(() {
                              sending = false;
                              sent = true;
                            });
                          } catch (_) {
                            setDialogState(() => sending = false);
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'The reset email could not be sent. Try again.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  child: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send reset link'),
                ),
              ],
      ),
    ),
  );
  resetEmail.dispose();
}

class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;
  static const destinations = [
    ('/dashboard', 'Dashboard', Icons.dashboard_outlined),
    ('/live-map', 'Live map', Icons.map_outlined),
    ('/safety', 'Safety reports', Icons.health_and_safety_outlined),
    ('/drivers', 'Drivers', Icons.badge_outlined),
    ('/admins', 'Admins', Icons.admin_panel_settings_outlined),
    ('/discount-claims', 'Discount claims', Icons.percent_outlined),
    ('/reviews', 'Reviews', Icons.star_outline),
    ('/evaluation', 'Evaluation', Icons.fact_check_outlined),
    ('/settings', 'Settings', Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ValueListenableBuilder<AdminSession?>(
      valueListenable: auth,
      builder: (context, session, _) {
        if (session == null) {
          return const AdminLoadingScreen(label: 'Loading your console');
        }
        final state = ref.watch(adminProvider);
        final visible = [
          for (final item in destinations)
            if (session.role == AdminRole.lgu || item.$1 != '/admins') item,
        ];
        // Sub-pages such as /evaluation/iso belong to their parent section.
        bool inSection(String path) =>
            location == path || location.startsWith('$path/');
        final title =
            destinations.where((item) => inSection(item.$1)).firstOrNull?.$2 ??
            'Console';
        return _ConsoleSemantics(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final expanded = constraints.maxWidth >= 1000;
              Widget navigation({
                required bool labels,
                bool drawer = false,
              }) => Container(
                width: labels ? 264 : 84,
                decoration: BoxDecoration(gradient: adminRailGradient(context)),
                padding: EdgeInsets.symmetric(
                  horizontal: labels ? 16 : 14,
                  vertical: 22,
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: labels ? 6 : 0,
                        ),
                        child: Row(
                          mainAxisAlignment: labels
                              ? MainAxisAlignment.start
                              : MainAxisAlignment.center,
                          children: [
                            const BrandTile(size: 40),
                            if (labels) ...[
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ArangCada',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 21,
                                        letterSpacing: -.4,
                                        height: 1.1,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Calamba · Administration',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: AdminColors.railTextMuted,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Expanded(
                        child: ListView(
                          padding: EdgeInsets.zero,
                          children: [
                            for (final item in visible) ...[
                              if (labels &&
                                  [
                                    '/dashboard',
                                    '/drivers',
                                    '/reviews',
                                  ].contains(item.$1))
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    16,
                                    0,
                                    8,
                                  ),
                                  child: Text(
                                    switch (item.$1) {
                                      '/dashboard' => 'OPERATIONS',
                                      '/drivers' => 'MANAGEMENT',
                                      _ => 'INSIGHTS',
                                    },
                                    style: const TextStyle(
                                      color: AdminColors.railTextMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: _NavItem(
                                  path: item.$1,
                                  label: item.$2,
                                  icon: item.$3,
                                  selected: inSection(item.$1),
                                  expanded: labels,
                                  closeDrawer: drawer,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Divider(color: Colors.white.withValues(alpha: .16)),
                      const SizedBox(height: 12),
                      _RailAccountFooter(
                        session: session,
                        expanded: labels,
                        onSignOut: () async {
                          await ref.read(adminProvider.notifier).disconnect();
                          auth.value = null;
                          if (context.mounted) {
                            context.go('/login');
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
              final toolbar = Container(
                constraints: const BoxConstraints(minHeight: 76),
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 8 : 32,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(
                    bottom: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Row(
                  children: [
                    // Phones open the drawer from the More tab below.
                    if (compact)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, right: 12),
                        child: BrandTile(size: 32),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            session.scope,
                            style: Theme.of(context).textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const AdminAppearanceButton(),
                    IconButton(
                      tooltip: 'Notifications',
                      onPressed: () {
                        final count = state.unreadSafetyAlerts;
                        ref
                            .read(adminProvider.notifier)
                            .clearSafetyNotifications();
                        if (count > 0) context.go('/safety');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              count == 0
                                  ? 'No unread safety alerts.'
                                  : '$count new safety reports.',
                            ),
                          ),
                        );
                      },
                      icon: Badge(
                        isLabelVisible: state.unreadSafetyAlerts > 0,
                        label: Text('${state.unreadSafetyAlerts}'),
                        child: const Icon(Icons.notifications_none),
                      ),
                    ),
                  ],
                ),
              );
              // Phones: the four most-used sections one tap away, the rest
              // under More (the drawer). The owner found the drawer-only
              // console hard to navigate on a phone.
              final tabs = visible.take(4).toList();
              final tabIndex = tabs.indexWhere((item) => inSection(item.$1));
              return Scaffold(
                drawer: compact
                    ? Drawer(
                        width: 280,
                        child: navigation(labels: true, drawer: true),
                      )
                    : null,
                bottomNavigationBar: compact
                    ? Builder(
                        builder: (context) => NavigationBar(
                          height: 64,
                          labelBehavior:
                              NavigationDestinationLabelBehavior.alwaysShow,
                          selectedIndex: tabIndex < 0 ? tabs.length : tabIndex,
                          onDestinationSelected: (index) {
                            if (index == tabs.length) {
                              Scaffold.of(context).openDrawer();
                            } else {
                              context.go(tabs[index].$1);
                            }
                          },
                          destinations: [
                            for (final item in tabs)
                              NavigationDestination(
                                icon: Icon(item.$3),
                                label: switch (item.$1) {
                                  '/live-map' => 'Map',
                                  '/safety' => 'Safety',
                                  _ => item.$2,
                                },
                              ),
                            const NavigationDestination(
                              icon: Icon(Icons.menu),
                              label: 'More',
                            ),
                          ],
                        ),
                      )
                    : null,
                body: Row(
                  children: [
                    if (!compact) navigation(labels: expanded),
                    Expanded(
                      child: Column(
                        children: [
                          toolbar,
                          Expanded(
                            child: Semantics(container: true, child: child),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// Keeps Flutter's semantics tree enabled for as long as the signed-in
/// console is on screen, so every console control is exposed to assistive
/// technology and browser automation without affecting the login form.
class _ConsoleSemantics extends StatefulWidget {
  const _ConsoleSemantics({required this.child});
  final Widget child;

  @override
  State<_ConsoleSemantics> createState() => _ConsoleSemanticsState();
}

class _ConsoleSemanticsState extends State<_ConsoleSemantics> {
  late final SemanticsHandle _handle = WidgetsBinding.instance
      .ensureSemantics();

  @override
  void dispose() {
    _handle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _RailAccountFooter extends StatelessWidget {
  const _RailAccountFooter({
    required this.session,
    required this.expanded,
    required this.onSignOut,
  });

  final AdminSession session;
  final bool expanded;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    // Same reactive gap as _AccountProfilePanel -- this footer's own
    // `session` prop is captured once by AdminShell.build(), which does
    // not re-run just because a photo change updates auth.value on the
    // *same* route. Read auth live instead of trusting the prop to still
    // be current, so the rail avatar (visible on every screen) actually
    // picks up a new photo without needing an unrelated navigation first.
    return ValueListenableBuilder<AdminSession?>(
      valueListenable: auth,
      builder: (context, liveSession, _) {
        final session = liveSession ?? this.session;
        final avatarUrl = session.avatarUrl;
        final avatar = CircleAvatar(
          radius: 20,
          backgroundColor: Colors.white,
          foregroundColor: AdminColors.royal,
          backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
          child: avatarUrl != null
              ? null
              : Text(
                  session.initials,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: AdminColors.royal),
                ),
        );
        final signOut = Semantics(
          label: 'Sign out',
          button: true,
          child: IconButton(
            tooltip: 'Sign out',
            onPressed: onSignOut,
            color: AdminColors.railText,
            icon: const Icon(Icons.logout),
          ),
        );
        if (!expanded) {
          return Column(children: [avatar, const SizedBox(height: 8), signOut]);
        }
        return Semantics(
          container: true,
          label: 'Signed in as ${session.name}, ${session.deskLabel}',
          child: Row(
            children: [
              avatar,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.deskLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AdminColors.railTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
              signOut,
            ],
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.path,
    required this.label,
    required this.icon,
    required this.selected,
    required this.expanded,
    this.closeDrawer = false,
  });
  final bool closeDrawer;
  final String path;
  final String label;
  final IconData icon;
  final bool selected;
  final bool expanded;

  @override
  Widget build(BuildContext context) => Semantics(
    selected: selected,
    button: true,
    label: label,
    child: Tooltip(
      message: expanded ? '' : label,
      child: InkWell(
        onTap: () {
          if (closeDrawer) Navigator.of(context).pop();
          context.go(path);
        },
        borderRadius: BorderRadius.circular(10),
        hoverColor: Colors.white.withValues(alpha: .10),
        splashColor: Colors.white.withValues(alpha: .14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 0),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFF2F6FB) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF041A45).withValues(alpha: .28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? AdminColors.royal : AdminColors.railText,
              ),
              if (expanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: 15,
                      color: selected
                          ? AdminColors.royal
                          : AdminColors.railText,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
