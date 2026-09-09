import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  runApp(const ProviderScope(child: AdminApp()));
}

Widget _consolePage(Widget child) => SingleChildScrollView(
  padding: const EdgeInsets.fromLTRB(28, 26, 28, 40),
  child: Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1500),
      child: child,
    ),
  ),
);

class AdminApp extends StatefulWidget {
  const AdminApp({super.key});

  @override
  State<AdminApp> createState() => _AdminAppState();
}

class _AdminAppState extends State<AdminApp> {
  late final GoRouter router = GoRouter(
    initialLocation: '/login',
    refreshListenable: auth,
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/login';
      // A recipient opening an invite link has no session at all -- this
      // route is public by design, same as /login, and must not bounce them
      // there. See .pipeline/specs.md Spec 19.
      final acceptingInvite = state.matchedLocation == '/accept-invite' ||
          state.matchedLocation == '/accept-driver-invite';
      if (auth.value == null && !loggingIn && !acceptingInvite) return '/login';
      if (auth.value != null && loggingIn) return '/dashboard';
      return null;
    },
    routes: [
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
  Widget build(BuildContext context) => MaterialApp.router(
    debugShowCheckedModeBanner: false,
    title: 'ArangCada Admin',
    theme: adminTheme(),
    routerConfig: router,
  );
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
  // Supabase.initialize() (in main(), awaited before runApp()) restores any
  // persisted session synchronously, so repository.hasSession is already
  // correct on this very first build -- true here means _restoreSession()
  // below WILL run and is expected to succeed. Rendering the actual login
  // form for that brief async window (a real network round trip to reload
  // the admin's profile/scope) is what produced the reported "reload lands
  // on /login, then jumps to the dashboard a moment later" flash. Gate the
  // form behind this instead of ever showing it mid-restore.
  late bool restoring =
      (ref.read(adminRepositoryProvider)?.hasSession ?? false) &&
      auth.value == null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSession());
  }

  Future<void> _restoreSession() async {
    final repository = ref.read(adminRepositoryProvider);
    if (repository == null || !repository.hasSession || auth.value != null) {
      if (mounted && restoring) setState(() => restoring = false);
      return;
    }
    try {
      final session = await repository.restoreSession();
      await ref.read(adminProvider.notifier).connect(session);
      if (mounted) auth.value = session;
    } catch (_) {
      if (mounted) {
        setState(() {
          restoring = false;
          signInError = 'Your administrator session expired. Sign in again.';
        });
      }
    }
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
    } on AuthException catch (error) {
      if (mounted) setState(() => signInError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => signInError =
              'This account is not an active administrator, or its assigned scope could not be loaded.',
        );
      }
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
                      ).textTheme.bodyLarge?.copyWith(color: AdminColors.muted),
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
                    if (signInError != null) ...[
                      Text(
                        signInError!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AdminColors.danger,
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
                    SizedBox(height: 430, child: hero),
                    SizedBox(height: 600, child: form),
                  ],
                ),
              );
      },
    ),
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
    ('/drivers', 'Drivers', Icons.badge_outlined),
    ('/admins', 'Admins', Icons.admin_panel_settings_outlined),
    ('/safety', 'Safety reports', Icons.health_and_safety_outlined),
    ('/reviews', 'Reviews', Icons.star_outline),
    ('/discount-claims', 'Discount claims', Icons.percent_outlined),
    ('/evaluation', 'Evaluation', Icons.fact_check_outlined),
    ('/settings', 'Settings', Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = auth.value!;
    final state = ref.watch(adminProvider);
    // /admins is LGU-only (Spec 19) -- RLS backs this up server-side
    // regardless, this just keeps a TODA-scoped admin from seeing a tab
    // that would refuse every action on it anyway.
    final destinations = [
      for (final item in AdminShell.destinations)
        if (item.$1 != '/admins' || session.role == AdminRole.lgu) item,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final expanded = constraints.maxWidth >= 960;
        final railWidth = expanded ? 236.0 : 84.0;
        return Scaffold(
          body: Row(
            children: [
              Container(
                width: railWidth,
                color: AdminColors.rail,
                padding: EdgeInsets.fromLTRB(
                  expanded ? 18 : 12,
                  18,
                  expanded ? 18 : 12,
                  16,
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: expanded
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            'assets/branding/arangcada-mark-dark.svg',
                            width: 38,
                            height: 38,
                          ),
                          if (expanded) ...[
                            const SizedBox(width: 10),
                            Text(
                              'ArangCada',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(color: Colors.white),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 28),
                      // Expanded, not Flexible -- a loose Flexible sharing
                      // this Column with a Spacer (also flex: 1) only ever
                      // got HALF the remaining height, the other half wasted
                      // as blank space before the footer. Ten items (nine
                      // plus Admins, Spec 19) no longer fit in that half on
                      // an ordinary window, silently hiding Discount claims,
                      // Evaluation, and Settings below the visible list with
                      // no scroll affordance shown. Expanded takes the whole
                      // remaining space instead, so the list scrolls only
                      // when it genuinely needs to and the footer still ends
                      // up flush at the bottom -- no separate Spacer needed.
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (final item in destinations)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: _NavItem(
                                    path: item.$1,
                                    label: item.$2,
                                    icon: item.$3,
                                    selected: location == item.$1,
                                    expanded: expanded,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        height: 1,
                        color: AdminColors.railText.withValues(alpha: .2),
                      ),
                      const SizedBox(height: 12),
                      _RailAccountFooter(
                        session: session,
                        expanded: expanded,
                        onSignOut: () async {
                          await ref.read(adminProvider.notifier).disconnect();
                          auth.value = null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: 64,
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      decoration: const BoxDecoration(
                        color: AdminColors.card,
                        border: Border(
                          bottom: BorderSide(color: AdminColors.border),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            destinations
                                .firstWhere((item) => item.$1 == location)
                                .$2,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          StatusPill(session.scope, tone: StatusTone.brand),
                          const SizedBox(width: 8),
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
                                        : '$count new safety report${count == 1 ? '' : 's'}.',
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
                    ),
                    Expanded(child: Semantics(container: true, child: child)),
                  ],
                ),
              ),
            ],
          ),
        );
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
          backgroundColor: AdminColors.primaryTint,
          foregroundColor: AdminColors.primaryPress,
          backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
          child: avatarUrl != null
              ? null
              : Text(
                  session.initials,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: AdminColors.primaryPress,
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
  });
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
        onTap: () => context.go(path),
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 48,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
          decoration: BoxDecoration(
            color: selected ? AdminColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
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
