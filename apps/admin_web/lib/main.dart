import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import 'admin_controller.dart';
import 'models.dart';
import 'screens.dart';
import 'session.dart';
import 'theme.dart';
import 'widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.ensureSemantics();
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
      if (auth.value == null && !loggingIn) return '/login';
      if (auth.value != null && loggingIn) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
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
            path: '/safety',
            builder: (context, state) => _consolePage(const SafetyScreen()),
          ),
          GoRoute(
            path: '/evaluation',
            builder: (context, state) => _consolePage(const EvaluationScreen()),
          ),
          GoRoute(
            path: '/survey',
            builder: (context, state) => _consolePage(const SurveyScreen()),
          ),
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
  final email = TextEditingController(text: 'evaluator@calambacity.gov.ph');
  final password = TextEditingController(text: 'arangcada-demo');
  AdminRole role = AdminRole.lgu;
  bool obscure = true;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  void submit() {
    if (!formKey.currentState!.validate()) return;
    ref.read(adminProvider.notifier).resetViewFilters();
    auth.value = AdminSession(
      name: role == AdminRole.lgu ? 'LGU Evaluator' : 'Brgy. Real Coordinator',
      role: role,
      toda: role == AdminRole.toda ? 'Brgy. Real' : null,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFFC9C4BA),
                  ),
                ),
                const SizedBox(height: 36),
                const Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    StatusPill('Internal MVP', tone: StatusTone.clay),
                    StatusPill('Simulated admin data'),
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
                      'Sign in to the local evaluation console.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyLarge?.copyWith(color: AdminColors.muted),
                    ),
                    const SizedBox(height: 30),
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
                    FilledButton.icon(
                      onPressed: submit,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Open console'),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Demo only — credentials are checked locally and are not transmitted.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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

class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  static const destinations = [
    ('/dashboard', 'Dashboard', Icons.dashboard_outlined),
    ('/live-map', 'Live map', Icons.map_outlined),
    ('/drivers', 'Drivers', Icons.badge_outlined),
    ('/safety', 'Safety reports', Icons.health_and_safety_outlined),
    ('/evaluation', 'Evaluation', Icons.fact_check_outlined),
    ('/survey', 'Driver survey', Icons.query_stats_outlined),
    ('/settings', 'Settings', Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final session = auth.value!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final expanded = constraints.maxWidth >= 1120;
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
                      const Spacer(),
                      if (expanded)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .06),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.name,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                session.scope,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: const Color(0xFFBDB8AE)),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      Tooltip(
                        message: 'Sign out',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => auth.value = null,
                          child: SizedBox(
                            height: 48,
                            child: Row(
                              mainAxisAlignment: expanded
                                  ? MainAxisAlignment.start
                                  : MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.logout,
                                  color: Color(0xFFC9C4BA),
                                ),
                                if (expanded) ...[
                                  const SizedBox(width: 12),
                                  Text(
                                    'Sign out',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: const Color(0xFFC9C4BA),
                                        ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
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
                          StatusPill(session.scope, tone: StatusTone.clay),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Notifications',
                            onPressed: () =>
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'No new local notifications.',
                                    ),
                                  ),
                                ),
                            icon: const Icon(Icons.notifications_none),
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
            color: selected ? AdminColors.clay : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisAlignment: expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : const Color(0xFFC9C4BA),
              ),
              if (expanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? Colors.white : const Color(0xFFC9C4BA),
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
