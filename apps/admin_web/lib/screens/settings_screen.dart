import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../admin_controller.dart';
import '../models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(adminProvider);
    final controller = ref.read(adminProvider.notifier);
    final session = auth.value!;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AccountProfilePanel(session: session),
            const SizedBox(height: 16),
            _PasswordSettingsPanel(session: session),
            const SizedBox(height: 16),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Console preferences',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Compact table density'),
                    subtitle: const Text(
                      'Reduce row height on data-heavy views.',
                    ),
                    value: state.compactDensity,
                    onChanged: controller.setCompactDensity,
                  ),
                  const Divider(),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Local desktop alerts'),
                    subtitle: Text(
                      state.connected
                          ? 'Play an unobtrusive chime for new SOS reports.'
                          : 'Show local status notifications during evaluation.',
                    ),
                    value: state.desktopAlerts,
                    onChanged: controller.setDesktopAlerts,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Driver app-feedback rules',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    session.role == AdminRole.lgu
                        ? 'Global settings apply to all TODAs and are enforced on the server.'
                        : 'Global settings are managed by the LGU and shown here as read-only.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  _FeedbackIntervalSetting(session: session),
                  const SizedBox(height: 10),
                  Text(
                    'Participation target: ${state.respondentTarget} unique drivers per TODA.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Map and data status',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  const _SettingRow(
                    icon: Icons.map_outlined,
                    title: 'Base map',
                    detail:
                        'MapLibre with OpenStreetMap raster tiles; optional MapTiler key at build time.',
                  ),
                  _SettingRow(
                    icon: Icons.layers_outlined,
                    title: 'TODA boundaries',
                    detail: state.connected
                        ? 'Server-defined jurisdictions; developer test boundary is provisional.'
                        : 'Prototype boundary · evaluation only',
                  ),
                  _SettingRow(
                    icon: Icons.storage_outlined,
                    title: 'Admin records',
                    detail: state.connected
                        ? 'Supabase records secured by administrator scope and row-level security.'
                        : 'Synthetic in-memory records; refresh resets changes.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About this build',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  const Text('ArangCada Admin · Internal MVP'),
                  const SizedBox(height: 5),
                  Text(
                    'Standalone Flutter Web target. It does not import or depend on the commuter/driver mobile client.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 14),
                  const StatusPill(
                    'Evaluation build · 2026-08-22',
                    tone: StatusTone.brand,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountProfilePanel extends ConsumerStatefulWidget {
  const _AccountProfilePanel({required this.session});

  final AdminSession session;

  @override
  ConsumerState<_AccountProfilePanel> createState() =>
      _AccountProfilePanelState();
}

class _AccountProfilePanelState extends ConsumerState<_AccountProfilePanel> {
  bool _uploading = false;

  bool get _canChange => widget.session.connected;

  Future<void> _changePhoto() async {
    if (!_canChange || _uploading) return;
    // Root cause, confirmed live 9 Sep 2026: an earlier diagnostic
    // SnackBar shown right here -- before ever calling pickImage() --
    // proved the tap itself was landing (it appeared every time), but no
    // file dialog ever followed it. image_picker's web implementation
    // opens the browser's file chooser via a plain synchronous
    // <input type="file">.click() call with nothing awaited first (see
    // image_picker_for_web's getFiles()), which is correct -- but a
    // browser's "user activation" for a click is a one-shot flag, and
    // showing that SnackBar first was enough on its own to consume it,
    // with zero error: the browser just silently refuses the .click(),
    // no onchange/oncancel/onerror ever fires on the input it refused to
    // open, and the awaited Future below hangs forever instead of
    // resolving to null. Nothing may run ahead of this call. Picked
    // generously (maxWidth 2000, no compression) -- the cropper below,
    // not this pick step, does the real sizing/compression, same split
    // apps/mobile's own profile_screen.dart already uses.
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2000,
    );
    if (picked == null || !mounted) return;

    // Square/circle crop before upload, matching apps/mobile's own
    // profile photo flow exactly (image_cropper, same version) --
    // WebUiSettings instead of AndroidUiSettings since this is a browser
    // console, not a phone. image_cropper_for_web works directly against
    // the blob: URL image_picker_for_web's XFile.path already is, no
    // extra plumbing needed for either package to interoperate.
    //
    // dragMode: move -- cropperjs's own default (crop) draws a NEW
    // selection box wherever you drag, which fights a fixed 1:1
    // aspectRatio and made the box feel stuck in place. move drags the
    // *photo* under a fixed-size box instead -- the same pan/zoom-the-
    // photo-under-a-frame model apps/mobile's own cropper already uses,
    // and it also fixes "can't zoom out far enough to fit the whole
    // photo": with the box no longer resizable/movable itself, zooming
    // the photo out and panning it is the only way to choose what's
    // inside, exactly as expected. Confirmed live, 9 Sep 2026 -- zoom
    // and rotate already worked; only repositioning did not.
    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      maxWidth: 1200,
      maxHeight: 1200,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 85,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        if (mounted)
          WebUiSettings(
            context: context,
            dragMode: WebDragMode.move,
            cropBoxMovable: false,
            cropBoxResizable: false,
          ),
      ],
    );
    // Null means Cancel on the crop dialog -- nothing uploads, same as
    // tapping Cancel anywhere else in this flow.
    if (cropped == null || !mounted) return;

    setState(() => _uploading = true);
    try {
      final bytes = await cropped.readAsBytes();
      // Always a jpg -- compressFormat above fixes it, regardless of what
      // the originally picked file's own extension was.
      final session = await ref
          .read(adminProvider.notifier)
          .changeProfilePhoto(bytes: bytes, fileExtension: 'jpg');
      if (!mounted) return;
      // AdminSession lives outside AdminController's own AdminState (see
      // main.dart's LoginScreen/session restore), so the fresh session with
      // its new avatarUrl is applied the same way sign-in already does.
      auth.value = session;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo updated.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update your photo. Try again.')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A photo change updates auth.value in place, on the *same* route --
    // unlike every other place auth.value is set (sign-in, session
    // restore), which always immediately navigates to a different route
    // and so always gets a fresh build for free. Reading widget.session
    // directly (captured once by SettingsScreen's own build) left this
    // panel showing the pre-change session forever after a real,
    // successfully saved photo change -- the write succeeded (confirmed
    // directly against the hosted project), the screen just never asked
    // auth for its current value again. ValueListenableBuilder makes this
    // panel its own listener instead of trusting a parent to have one.
    return ValueListenableBuilder<AdminSession?>(
      valueListenable: auth,
      builder: (context, liveSession, _) {
        final session = liveSession ?? widget.session;
        final avatarUrl = session.avatarUrl;
        return Panel(
          child: Row(
            children: [
              Semantics(
                label: _canChange ? 'Change profile photo' : null,
                button: _canChange,
                // Rebuilt on Material + InkWell rather than a bare
                // GestureDetector -- InkWell is the framework's own
                // battle-tested tap-target implementation (used for every
                // other clickable surface in this app, e.g. Panel's own
                // onTap) instead of a hand-rolled Stack/Positioned
                // combination that already hid one hit-test bug. The
                // ripple is also a real, visible confirmation that a tap
                // landed at all, which the silent GestureDetector version
                // never gave anyone -- owner included -- a way to tell
                // apart from "did nothing."
                //
                // No shape/clipBehavior on this Material -- a CircleBorder
                // clip here clips to the circle *inscribed* in the 56x56
                // box, which cut the corner-positioned edit badge off
                // (it renders outside that inscribed circle by design).
                // customBorder below still gives the ripple itself a
                // circular shape; it just doesn't also clip the child.
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: const ValueKey('avatarHitTestBox'),
                    customBorder: const CircleBorder(),
                    onTap: _canChange ? _changePhoto : null,
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: context.adminColor(AdminColors.primaryTint),
                            foregroundColor: context.adminColor(AdminColors.primaryPress),
                            backgroundImage: avatarUrl == null
                                ? null
                                : NetworkImage(avatarUrl),
                            child: avatarUrl == null
                                ? Text(session.initials)
                                : null,
                          ),
                          if (_uploading)
                            const CircleAvatar(
                              radius: 26,
                              backgroundColor: Colors.black45,
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              ),
                            )
                          else if (_canChange)
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: AdminColors.rail,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.edit,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 4,
                      children: [
                        Text(
                          '${session.deskLabel} ·',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          session.email ?? 'Local demo account',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StatusPill(session.roleLabel, tone: StatusTone.brand),
            ],
          ),
        );
      },
    );
  }
}

class _PasswordSettingsPanel extends ConsumerStatefulWidget {
  const _PasswordSettingsPanel({required this.session});

  final AdminSession session;

  @override
  ConsumerState<_PasswordSettingsPanel> createState() =>
      _PasswordSettingsPanelState();
}

class _PasswordSettingsPanelState
    extends ConsumerState<_PasswordSettingsPanel> {
  final formKey = GlobalKey<FormState>();
  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  bool currentHidden = true;
  bool newHidden = true;
  bool confirmHidden = true;
  bool saving = false;

  bool get canChange =>
      widget.session.connected && (widget.session.email?.isNotEmpty ?? false);

  @override
  void dispose() {
    currentPassword.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!formKey.currentState!.validate()) return;
    if (!canChange) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connect an administrator account to change its password.',
          ),
        ),
      );
      return;
    }
    setState(() => saving = true);
    try {
      await ref
          .read(adminProvider.notifier)
          .updateOwnPassword(
            session: widget.session,
            currentPassword: currentPassword.text,
            newPassword: newPassword.text,
          );
      currentPassword.clear();
      newPassword.clear();
      confirmPassword.clear();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Password updated.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Password could not be updated. Check your current password and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool hidden,
    required VoidCallback toggle,
    required String? Function(String?) validator,
    required Iterable<String> autofillHints,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: controller,
      obscureText: hidden,
      autofillHints: autofillHints,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: hidden ? 'Show password' : 'Hide password',
          onPressed: toggle,
          icon: Icon(
            hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Panel(
    child: Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Change password',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            canChange
                ? 'Enter your current password, then choose a new one.'
                : 'Password changes are available after signing in to the connected console.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          _passwordField(
            controller: currentPassword,
            label: 'Current password',
            hint: 'Enter current password',
            hidden: currentHidden,
            toggle: () => setState(() => currentHidden = !currentHidden),
            validator: (value) => value == null || value.isEmpty
                ? 'Enter your current password.'
                : null,
            autofillHints: const [AutofillHints.password],
          ),
          _passwordField(
            controller: newPassword,
            label: 'New password',
            hint: 'At least 8 characters',
            hidden: newHidden,
            toggle: () => setState(() => newHidden = !newHidden),
            validator: (value) => value == null || value.length < 8
                ? 'Enter at least 8 characters.'
                : null,
            autofillHints: const [AutofillHints.newPassword],
          ),
          _passwordField(
            controller: confirmPassword,
            label: 'Confirm new password',
            hint: 'Re-enter new password',
            hidden: confirmHidden,
            toggle: () => setState(() => confirmHidden = !confirmHidden),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Confirm the new password.';
              }
              return value == newPassword.text
                  ? null
                  : 'Passwords do not match.';
            },
            autofillHints: const [AutofillHints.newPassword],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: saving ? null : _save,
            child: Text(saving ? 'Updating…' : 'Update password'),
          ),
        ],
      ),
    ),
  );
}

class _FeedbackIntervalSetting extends ConsumerStatefulWidget {
  const _FeedbackIntervalSetting({required this.session});

  final AdminSession session;

  @override
  ConsumerState<_FeedbackIntervalSetting> createState() =>
      _FeedbackIntervalSettingState();
}

class _FeedbackIntervalSettingState
    extends ConsumerState<_FeedbackIntervalSetting> {
  late final TextEditingController interval = TextEditingController(
    text: '${ref.read(adminProvider).feedbackInterval}',
  );
  bool saving = false;
  String? error;

  @override
  void dispose() {
    interval.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = int.tryParse(interval.text.trim());
    if (value == null || value < 1) {
      setState(() => error = 'Enter a whole number greater than zero.');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(adminProvider.notifier)
          .updateFeedbackSettings(
            session: widget.session,
            feedbackInterval: value,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Drivers will provide app feedback after every $value completed trip${value == 1 ? '' : 's'}.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'The global feedback setting could not be saved.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = widget.session.role == AdminRole.lgu;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: interval,
            enabled: canEdit && !saving,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Completed trips between required feedback',
              errorText: error,
              suffixText: 'trip(s)',
            ),
            onSubmitted: canEdit ? (_) => _save() : null,
          ),
        ),
        if (canEdit) ...[
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: FilledButton(
              onPressed: saving ? null : _save,
              child: Text(saving ? 'Saving…' : 'Save interval'),
            ),
          ),
        ],
      ],
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: context.adminColor(AdminColors.primaryTint),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: context.adminColor(AdminColors.primary)),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(detail),
            ],
          ),
        ),
      ],
    ),
  );
}
