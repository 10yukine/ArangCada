import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
  WidgetsBinding.instance.ensureSemantics();
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
    (mode) => mode.name == savedAppearance, orElse: () => ThemeMode.system,
  );
  runApp(const ProviderScope(child: AdminApp()));
}

Widget _consolePage(Widget child) => LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
  padding: EdgeInsets.fromLTRB(constraints.maxWidth < 600 ? 16 : 32, 28, constraints.maxWidth < 600 ? 16 : 32, 40),
  child: Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1500),
      child: child,
    ),
  ),
));

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
      final acceptingInvite = state.matchedLocation == '/accept-invite' ||
          state.matchedLocation == '/accept-driver-invite';

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
            builder: (context, state) => _consolePage(const DashboardScreen()),
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
          GoRoute(
            path: '/evaluation',
            builder: (context, state) => _consolePage(const EvaluationScreen()),
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
    if ((repository?.hasSession ?? false) && auth.value == null) {
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
  ));
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController(
    text: AdminAppConfig.isSupabaseConfigured
        ? ''
        : 'evaluator@calambacity.gov.ph',
  );
  final password = TextEditingController(
    text: AdminAppConfig.isSupabaseConfigured ? '' : 'arangcada-demo',
  );
  AdminRole role = AdminRole.lgu;
  bool obscure = true;
  bool demoMode = !AdminAppConfig.isSupabaseConfigured;
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
      if (demoMode) {
        await ref
            .read(adminProvider.notifier)
            .connect(
              AdminSession(
                name: role == AdminRole.lgu
                    ? 'LGU Evaluator'
                    : 'Brgy. Real Coordinator',
                email: email.text.trim(),
                role: role,
                toda: role == AdminRole.toda ? 'Brgy. Real' : null,
              ),
            );
        auth.value = AdminSession(
          name: role == AdminRole.lgu
              ? 'LGU Evaluator'
              : 'Brgy. Real Coordinator',
          email: email.text.trim(),
          role: role,
          toda: role == AdminRole.toda ? 'Brgy. Real' : null,
        );
        return;
      }
      final repository = ref.read(adminRepositoryProvider);
      if (repository == null) {
        throw StateError('The connected administrator service is unavailable.');
      }
      final session = await repository.signIn(
        email: email.text,
        password: password.text,
      );
      await ref.read(adminProvider.notifier).connect(session);
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
          return Scaffold(
            body: Container(
              decoration: const BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF083C97), Color(0xFF1683C9)],
              )),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 5)),
                        ],
                      ),
                      child: SvgPicture.asset('assets/branding/arangcada-mark-dark.svg'),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 24,
                    child: SafeArea(
                      top: false,
                      child: Center(
                        child: SizedBox(
                          width: 160,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: const LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: Color(0x55FFFFFF),
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              semanticsLabel: 'Restoring your account',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final effectiveError = signInError ?? authError.value;
        return Scaffold(
          body: LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final hero = Container(
          color: AdminColors.rail,
          padding: EdgeInsets.all(wide ? 64 : 28),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    SvgPicture.asset(
                      'assets/branding/arangcada-mark-dark.svg',
                      width: 48,
                      height: 48,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'ArangCada',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineMedium?.copyWith(color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 48),
                Text(
                  'Local dispatch.\nClearer oversight.',
                  style: Theme.of(
                    context,
                  ).textTheme.displaySmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 18),
                Text(
                  'A focused evaluation console for LGU and TODA administrators in Calamba City.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: AdminColors.railText),
                ),
                const SizedBox(height: 36),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    const StatusPill('Internal MVP', tone: StatusTone.brand),
                    StatusPill(
                      demoMode ? 'Local demo data' : 'Connected Supabase data',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
        final form = Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(wide ? 48 : 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(alignment: Alignment.centerRight, child: AdminAppearanceButton()),
                    Text(
                      'Welcome back',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      demoMode
                          ? 'Sign in to the local evaluation console.'
                          : 'Use your assigned LGU or TODA administrator account.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: context.adminColor(AdminColors.muted)),
                    ),
                    const SizedBox(height: 30),
                    if (demoMode) ...[
                      SegmentedButton<AdminRole>(
                        segments: const [
                          ButtonSegment(
                            value: AdminRole.lgu,
                            label: Text('LGU admin'),
                            icon: Icon(Icons.account_balance_outlined),
                          ),
                          ButtonSegment(
                            value: AdminRole.toda,
                            label: Text('TODA admin'),
                            icon: Icon(Icons.groups_outlined),
                          ),
                        ],
                        selected: {role},
                        onSelectionChanged: (selection) =>
                            setState(() => role = selection.first),
                      ),
                      const SizedBox(height: 20),
                    ],
                    TextFormField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                      validator: (value) => value != null && value.contains('@')
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
                          tooltip: obscure ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => obscure = !obscure),
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
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.adminColor(AdminColors.danger),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    FilledButton.icon(
                      onPressed: submitting ? null : submit,
                      icon: submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward),
                      label: Text(submitting ? 'Signing in…' : 'Open console'),
                    ),
                    if (!demoMode && AdminAppConfig.isSupabaseConfigured) ...[
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
                      demoMode
                          ? 'Demo only — credentials are checked locally and are not transmitted.'
                          : 'Administrator access and TODA scope are verified on the server.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (AdminAppConfig.isSupabaseConfigured) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: submitting
                            ? null
                            : () => setState(() {
                                demoMode = !demoMode;
                                signInError = null;
                                email.text = demoMode
                                    ? 'evaluator@calambacity.gov.ph'
                                    : '';
                                password.text = demoMode
                                    ? 'arangcada-demo'
                                    : '';
                              }),
                        child: Text(
                          demoMode
                              ? 'Use connected administrator sign-in'
                              : 'Use local demo',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
        return wide
            ? Row(
                children: [
                  Expanded(flex: 11, child: hero),
                  Expanded(flex: 9, child: form),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  children: [
                    Padding(padding: const EdgeInsets.fromLTRB(24, 28, 24, 0), child: Row(children: [
                      SvgPicture.asset('assets/branding/arangcada-mark-dark.svg', width: 36, height: 36, colorFilter: ColorFilter.mode(Theme.of(context).colorScheme.primary, BlendMode.srcIn)),
                      const SizedBox(width: 12),
                      Text('ArangCada Admin', style: Theme.of(context).textTheme.titleLarge),
                    ])),
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
          return Scaffold(
            backgroundColor: AdminColors.rail,
            body: Center(
              child: CircularProgressIndicator(
                color: context.adminColor(AdminColors.primary),
              ),
            ),
          );
        }
        final state = ref.watch(adminProvider);
    final visible = [
      for (final item in destinations)
        if (session.role == AdminRole.lgu || item.$1 != '/admins') item,
    ];
    final title = destinations.where((item) => item.$1 == location).firstOrNull?.$2 ?? 'Console';
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 600;
      final expanded = constraints.maxWidth >= 1000;
      Widget navigation({required bool labels, bool drawer = false}) => Container(
        width: labels ? 248 : 80,
        color: AdminColors.rail,
        padding: EdgeInsets.symmetric(horizontal: labels ? 20 : 12, vertical: 24),
        child: SafeArea(child: Column(children: [
          Row(mainAxisAlignment: labels ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
            SvgPicture.asset('assets/branding/arangcada-mark-dark.svg', width: 36, height: 36),
            if (labels) ...[
              const SizedBox(width: 10),
              const Expanded(child: Text('ArangCada', overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 21))),
            ],
          ]),
          if (labels) const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('CALAMBA · ADMINISTRATION', style: TextStyle(color: AdminColors.railText, fontSize: 10, letterSpacing: 1.3))),
          ),
          const SizedBox(height: 28),
          Expanded(child: ListView(padding: EdgeInsets.zero, children: [
            for (final item in visible) ...[
              if (labels && ['/dashboard', '/drivers', '/reviews'].contains(item.$1))
                Padding(padding: const EdgeInsets.fromLTRB(12, 18, 0, 10),
                  child: Text(switch(item.$1) {'/dashboard' => 'OPERATIONS', '/drivers' => 'MANAGEMENT', _ => 'INSIGHTS'},
                    style: const TextStyle(color: AdminColors.railTextMuted, fontSize: 10, letterSpacing: 1.5))),
              Padding(padding: const EdgeInsets.only(bottom: 4),
                child: _NavItem(path: item.$1, label: item.$2, icon: item.$3,
                  selected: location == item.$1, expanded: labels,
                  closeDrawer: drawer)),
            ],
          ])),
          const Divider(color: Color(0xFF304159)),
          const SizedBox(height: 12),
          _RailAccountFooter(session: session, expanded: labels,
            onSignOut: () async {
              await ref.read(adminProvider.notifier).disconnect();
              auth.value = null;
              if (context.mounted) {
                context.go('/login');
              }
            }),
        ])),
      );
      final toolbar = Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 24, vertical: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor))),
        child: Row(children: [
          if (compact) Builder(builder: (context) => IconButton(
            tooltip: 'Open navigation', icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer())),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            Text(session.scope, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          const AdminAppearanceButton(),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {
              final count = state.unreadSafetyAlerts;
              ref.read(adminProvider.notifier).clearSafetyNotifications();
              if (count > 0) context.go('/safety');
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(count == 0 ? 'No unread safety alerts.' : '$count new safety reports.')));
            },
            icon: Badge(isLabelVisible: state.unreadSafetyAlerts > 0,
              label: Text('${state.unreadSafetyAlerts}'),
              child: const Icon(Icons.notifications_none)),
          ),
        ]),
      );
      return Scaffold(
        drawer: compact ? Drawer(width: 280, child: navigation(labels: true, drawer: true)) : null,
        body: Row(children: [
          if (!compact) navigation(labels: expanded),
          Expanded(child: Column(children: [
            toolbar,
            Expanded(child: Semantics(container: true, child: child)),
          ])),
        ]),
      );
    });
      },
    );
  }
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
          backgroundColor: context.adminColor(AdminColors.primaryTint),
          foregroundColor: context.adminColor(AdminColors.primaryPress),
          backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
          child: avatarUrl != null
              ? null
              : Text(
                  session.initials,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: context.adminColor(AdminColors.primaryPress),
                  ),
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
          return Column(
            children: [avatar, const SizedBox(height: 8), signOut],
          );
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
          decoration: BoxDecoration(
            color: selected ? context.adminColor(AdminColors.primary) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(icon, color: selected ? Colors.white : AdminColors.railText),
              if (expanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? Colors.white : AdminColors.railText,
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
