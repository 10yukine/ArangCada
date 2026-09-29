import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin_controller.dart';
import '../theme.dart';
import '../widgets.dart';

// =============================================================================
// Accept driver invite (Spec 20) -- public route, no session required
// =============================================================================

class AcceptDriverInviteScreen extends ConsumerStatefulWidget {
  const AcceptDriverInviteScreen({super.key, required this.token});
  final String? token;

  @override
  ConsumerState<AcceptDriverInviteScreen> createState() =>
      _AcceptDriverInviteScreenState();
}

class _AcceptDriverInviteScreenState
    extends ConsumerState<AcceptDriverInviteScreen> {
  final formKey = GlobalKey<FormState>();
  final errors = FieldErrorReset();
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final mobileNumber = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  bool passwordHidden = true;
  bool confirmHidden = true;
  bool loading = true;
  bool submitting = false;
  bool done = false;
  String? email;
  String? todaZoneName;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_lookup()));
  }

  @override
  void dispose() {
    firstName.dispose();
    lastName.dispose();
    mobileNumber.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'This invite link is missing its token.';
        });
      }
      return;
    }
    try {
      final resolved = await ref
          .read(adminProvider.notifier)
          .lookupDriverInvite(token);
      if (!mounted) return;
      setState(() {
        email = resolved.email;
        todaZoneName = resolved.todaZoneName;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error =
            'This invite is invalid or has expired. Ask an LGU administrator to send a new one.';
      });
    }
  }

  Future<void> _submit() async {
    final token = widget.token;
    if (token == null || email == null) return;
    if (!errors.validate(formKey)) return;
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      await ref
          .read(adminProvider.notifier)
          .acceptDriverInvite(
            token: token,
            displayName: '${firstName.text.trim()} ${lastName.text.trim()}',
            mobileNumber: mobileNumber.text,
            password: password.text,
          );
      if (!mounted) return;
      // Unlike the admin accept flow, a driver account cannot open an
      // admin_web session at all -- AdminSession.fromProfile requires
      // role = 'admin' -- and this app has no session of its own to offer
      // a driver. The confirmation below is the entire rest of this flow.
      setState(() {
        submitting = false;
        done = true;
      });
    } catch (caught) {
      if (!mounted) return;
      setState(() {
        submitting = false;
        error = caught is StateError
            ? caught.message
            : 'The account could not be created. Try again.';
      });
    }
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required String? hint,
    required bool hidden,
    required VoidCallback toggle,
    required String? Function(String?) validator,
  }) => TextFormField(
    errorBuilder: adminFieldError,
    controller: controller,
    obscureText: hidden,
    onChanged: (_) => errors.edited(controller, formKey),
    validator: errors.guard(controller, validator),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: IconButton(
        tooltip: hidden ? 'Show password' : 'Hide password',
        onPressed: toggle,
        icon: Icon(
          hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final Widget body;
    final resolvedEmail = email;
    if (loading) {
      body = const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (resolvedEmail == null) {
      body = Panel(
        child: EmptyState(
          message: error ?? 'This invite is invalid or has expired.',
        ),
      );
    } else if (done) {
      body = Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Account created',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Open the ArangCada mobile app and sign in with $resolvedEmail '
              'and the password you just set to start receiving dispatch '
              'requests for ${todaZoneName ?? 'your TODA'}.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    } else {
      body = Panel(
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Create your driver account',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'for $resolvedEmail -- joining ${todaZoneName ?? 'your TODA'}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              TextFormField(
                errorBuilder: adminFieldError,
                controller: firstName,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'First name'),
                onChanged: (_) => errors.edited(firstName, formKey),
                validator: errors.guard(
                  firstName,
                  (value) => (value?.trim().isNotEmpty ?? false)
                      ? null
                      : 'Enter your first name',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                errorBuilder: adminFieldError,
                controller: lastName,
                decoration: const InputDecoration(labelText: 'Last name'),
                onChanged: (_) => errors.edited(lastName, formKey),
                validator: errors.guard(
                  lastName,
                  (value) => (value?.trim().isNotEmpty ?? false)
                      ? null
                      : 'Enter your last name',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                errorBuilder: adminFieldError,
                controller: mobileNumber,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile number',
                  hintText: '09XXXXXXXXX',
                ),
                onChanged: (_) => errors.edited(mobileNumber, formKey),
                validator: errors.guard(
                  mobileNumber,
                  (value) =>
                      (value?.replaceAll(RegExp(r'\D'), '').length ?? 0) >= 10
                      ? null
                      : 'Enter a valid mobile number',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                errorBuilder: adminFieldError,
                initialValue: resolvedEmail,
                enabled: false,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              _passwordField(
                controller: password,
                label: 'Password',
                hint: null,
                hidden: passwordHidden,
                toggle: () => setState(() => passwordHidden = !passwordHidden),
                validator: adminPasswordProblem,
              ),
              const SizedBox(height: 12),
              _passwordField(
                controller: confirmPassword,
                label: 'Repeat password',
                hint: null,
                hidden: confirmHidden,
                toggle: () => setState(() => confirmHidden = !confirmHidden),
                validator: (value) => (value ?? '').isEmpty
                    ? 'Enter the password again'
                    : value == password.text
                    ? null
                    : 'Passwords do not match',
              ),
              const SizedBox(height: 6),
              AdminPasswordRequirements(
                password: password,
                repeat: confirmPassword,
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: submitting ? null : _submit,
                  child: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create account'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.adminColor(AdminColors.background),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandTile(size: 64),
                const SizedBox(height: 14),
                Text(
                  'ArangCada',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
