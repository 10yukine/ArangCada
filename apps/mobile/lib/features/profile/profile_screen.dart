import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/app_row_icon.dart';
import '../../core/widgets/arang_dialog.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/widgets/dashboard_back_button.dart';
import '../../data/providers/repository_providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/email_confirmation_repository.dart';
import '../../domain/models/demo_user.dart';

/// The address whose confirm-email prompt was closed. Kept until the app
/// restarts, so the prompt comes back next time rather than never.
final _confirmEmailHiddenFor = Provider<ValueNotifier<String?>>((ref) {
  final hidden = ValueNotifier<String?>(null);
  ref.onDispose(hidden.dispose);
  return hidden;
});

/// One profile screen for both roles.
///
/// Commuter and driver deliberately share this widget rather than each
/// owning a copy: the two screens are supposed to look and behave the same,
/// and two copies drift the moment one is edited. The driver's only
/// difference is an extra LGU-governed section, expressed as a flag rather
/// than a second screen.
///
/// Editing lives on the pencil in the header, not on a "Personal
/// Information" row. Notifications are reached from the dashboard bell, and
/// notification *settings* live in Settings, so there is no
/// notifications row here.
///
/// Rows sit flat on the page background, separated by hairline dividers,
/// rather than grouped inside bordered cards -- matching the reference
/// prototype's flatter list style. A card would only be justified here if it
/// communicated hierarchy; a single settings list does not need one.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ArangDialog(
        title: 'Log out?',
        content: const Text('You can sign back in with your account.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(authRepositoryProvider).signOut();
    ref.read(chatRepositoryProvider).clearSession();
    if (context.mounted) context.go('/login');
  }

  /// Take a photo or choose one, crop it to a square, upload it, and point
  /// profiles.avatar_path at it.
  /// the real implementation the "Change photo" button used to fake with
  /// `'Photo change is a demo-only action.'`.
  ///
  /// The crop step doubles as the confirm step: image_cropper's own screen
  /// has Cancel and Done actions, and cancelling returns null here, so
  /// nothing uploads until the user has actually confirmed a crop. A picked
  /// photo is never live on the account before that confirmation.
  Future<void> _changePhoto(BuildContext context, WidgetRef ref) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
    if (source == null || !context.mounted) return;

    XFile? file;
    try {
      // No maxWidth/imageQuality here -- image_cropper's own maxWidth/
      // maxHeight/compressQuality below are what actually produce the
      // uploaded file; this pick is generously capped only to keep a huge
      // camera-native file from being loaded into the cropper's memory.
      file = await ImagePicker().pickImage(source: source, maxWidth: 2000);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the camera or gallery.')),
      );
      return;
    }
    if (file == null || !context.mounted) return;

    CroppedFile? cropped;
    try {
      cropped = await ImageCropper().cropImage(
        sourcePath: file.path,
        maxWidth: 1200,
        maxHeight: 1200,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 85,
        // Locked to a square, matching the circular avatar it becomes --
        // this is not a general-purpose crop tool, so there is no ratio
        // picker to leave enabled.
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop photo',
            toolbarColor: AppColors.primary,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: AppColors.primary,
            cropStyle: CropStyle.circle,
            lockAspectRatio: true,
          ),
        ],
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not crop that photo.')),
      );
      return;
    }
    // Null means the user tapped Cancel on the crop screen -- nothing
    // uploads, exactly like tapping Cancel anywhere else in this flow.
    if (cropped == null || !context.mounted) return;

    final bytes = await cropped.readAsBytes();
    if (!context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final auth = ref.read(authRepositoryProvider);
    try {
      final dotIndex = cropped.path.lastIndexOf('.');
      final extension = dotIndex == -1
          ? 'jpg'
          : cropped.path.substring(dotIndex + 1).toLowerCase();
      final path = await auth.uploadProfilePhoto(
        bytes: bytes,
        fileExtension: extension,
      );
      await auth.updateAvatarPath(path);
      if (!context.mounted) return;
      _dismissLoadingDialog(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Profile photo updated.')));
    } on DemoAuthException catch (error) {
      if (!context.mounted) return;
      _dismissLoadingDialog(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      // Both repository calls above already wrap their expected failure
      // types (StorageException, PostgrestException) into
      // DemoAuthException -- this is a defense-in-depth fallback for
      // anything unexpected (e.g. a network-layer exception raised before
      // reaching that wrapping), so the loading dialog can never get stuck
      // open with no feedback. Independent review finding (Copilot, PR #17
      // council-review snapshot, 6 Sep 2026).
      if (!context.mounted) return;
      _dismissLoadingDialog(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update your photo. Try again.'),
        ),
      );
    }
  }

  /// `showDialog` defaults to `useRootNavigator: true`, pushing onto the
  /// outermost Navigator rather than go_router's own page-stack Navigator.
  /// `Navigator.pop(context)` resolves to the *nearest* Navigator from
  /// [context] instead -- on a physical device, that turned out to be
  /// go_router's, so it popped this whole screen's route off the stack
  /// instead of dismissing the dialog, crashing with "You have popped the
  /// last page off of the stack". `rootNavigator: true` here targets the
  /// same Navigator the dialog actually opened on. Found on a physical
  /// device, 6 Sep 2026 -- the bare `MaterialApp(home: ...)` test harness
  /// has only one Navigator, so this could not have been caught there.
  void _dismissLoadingDialog(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    final promptHiddenFor = ref.watch(_confirmEmailHiddenFor);
    final isDriver = state.currentUser?.role == DemoRole.driver;

    return Scaffold(
      appBar: AppBar(
        leading: DashboardBackButton(isDriver: isDriver),
        title: const Text('Profile'),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([state, promptHiddenFor]),
          builder: (context, _) {
            final user = state.currentUser;

            return ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  child: _ProfileHeader(
                    name:
                        user?.displayName ?? (isDriver ? 'Driver' : 'Commuter'),
                    subtitle: user?.email ?? '',
                    isDriver: isDriver,
                    imageUrl: user?.avatarUrl,
                    onChangePhoto: () => _changePhoto(context, ref),
                  ),
                ),
                if (user != null &&
                    !user.emailConfirmed &&
                    promptHiddenFor.value != user.email &&
                    ref.watch(emailConfirmationRepositoryProvider) != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: _ConfirmEmailPrompt(
                      email: user.email,
                      isDriver: isDriver,
                    ),
                  ),
                ],
                if (isDriver) ...[
                  const SizedBox(height: AppSpacing.md),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    child: _SectionLabel('LGU & TODA records'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _ProfileRow(
                    icon: Icons.description_outlined,
                    label: 'Franchise & documents',
                    onTap: () => context.push('/profile/driver-documents'),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: _SectionLabel('Account'),
                ),
                const SizedBox(height: AppSpacing.xs),
                // A driver's places and fare-discount status are the
                // rider's concerns, not theirs -- they run under a fixed
                // TODA fare, not a discount card they carry.
                if (!isDriver) ...[
                  _ProfileRow(
                    icon: Icons.bookmark_border,
                    label: 'Saved places',
                    onTap: () => context.push('/profile/saved-places'),
                  ),
                  const Divider(height: 1),
                ],
                // Drivers only. A commuter already has a "View fare matrix"
                // card on their home screen, so a second entry point here was
                // pure duplication -- and it was the row that pushed this list
                // past one screen, forcing a scroll to reach Sign out.
                //
                // A driver has no such card, so removing it for them would
                // take away their only route to the LGU rates.
                if (isDriver) ...[
                  _ProfileRow(
                    icon: Icons.discount_outlined,
                    label: 'Fare matrix',
                    onTap: () => context.push('/fare-matrix'),
                  ),
                  const Divider(height: 1),
                ],
                if (!isDriver) ...[
                  _ProfileRow(
                    icon: Icons.verified_user_outlined,
                    label: 'Discount eligibility',
                    onTap: () => context.push('/profile/discount-eligibility'),
                  ),
                  const Divider(height: 1),
                ],
                _ProfileRow(
                  icon: Icons.support_agent_outlined,
                  label: 'Support',
                  onTap: () => context.push('/profile/support'),
                ),
                const Divider(height: 1),
                _ProfileRow(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                  onTap: () => context.push('/profile/app-settings'),
                ),
                const Divider(height: 1),
                _ProfileRow(
                  icon: Icons.info_outline,
                  label: 'About ArangCada',
                  onTap: () => context.push('/profile/about'),
                ),
                const Divider(height: 1),
                // Same flat row as everything above it -- only the red icon
                // and label mark it as destructive. No separate pill/card
                // button, no chevron (it's a terminal action, not a drill
                // down).
                _ProfileRow(
                  icon: Icons.logout,
                  label: 'Sign out',
                  danger: true,
                  showChevron: false,
                  onTap: () => _logout(context, ref),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.subtitle,
    required this.isDriver,
    required this.onChangePhoto,
    this.imageUrl,
  });

  final String name;
  final String subtitle;
  final bool isDriver;
  final String? imageUrl;
  final VoidCallback onChangePhoto;

  /// The pencil replaces the old "Personal Information" row on both sides.
  /// For a driver most fields are LGU-issued and read-only, so the sheet
  /// says so rather than offering inputs that would not be honoured.
  void _edit(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Edit profile', style: AppTypography.displaySm),
              const SizedBox(height: AppSpacing.xs),
              Text(
                isDriver
                    ? 'Your name, body number, plate, TODA, and franchise are '
                          'issued by the LGU/TODA office and cannot be changed '
                          'here. Only your photo can be updated.'
                    : 'Update the details shown on your ArangCada account.',
                style: AppTypography.bodySm.copyWith(height: 1.45),
              ),
              const SizedBox(height: AppSpacing.lg),
              ArangButton(
                label: 'Change photo',
                icon: Icons.photo_camera_outlined,
                variant: ArangButtonVariant.ghost,
                onPressed: () {
                  Navigator.pop(sheetContext);
                  onChangePhoto();
                },
              ),
              const SizedBox(height: AppSpacing.xs),
              ArangButton(
                label: isDriver ? 'Close' : 'Edit account details',
                onPressed: () {
                  Navigator.pop(sheetContext);
                  if (isDriver) return;
                  context.push('/profile/edit');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ArangAvatar(
          name: name,
          size: 52,
          background: isDriver ? AppColors.primary : AppColors.primaryFill,
          foreground: isDriver ? Colors.white : AppColors.primaryText,
          imageUrl: imageUrl,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
        ArangIconButton(
          icon: Icons.edit_outlined,
          tooltip: 'Edit profile',
          onPressed: () => _edit(context),
        ),
      ],
    );
  }
}

/// Asks the account holder to confirm their email: sends the link, and looks
/// again when they come back from the browser where the link opens. A prompt
/// only -- nothing is withheld from an unconfirmed email.
class _ConfirmEmailPrompt extends ConsumerStatefulWidget {
  const _ConfirmEmailPrompt({required this.email, required this.isDriver});

  final String email;
  final bool isDriver;

  @override
  ConsumerState<_ConfirmEmailPrompt> createState() =>
      _ConfirmEmailPromptState();
}

class _ConfirmEmailPromptState extends ConsumerState<_ConfirmEmailPrompt> {
  late final AppLifecycleListener _lifecycle;
  Timer? _ticker;
  bool _sending = false;
  bool _sent = false;

  /// Seconds until another link may be asked for. The server sends one a
  /// minute.
  int _wait = 0;

  /// The server's own words when it will not send a link yet.
  String? _notice;
  String? _error;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _refresh() =>
      unawaited(ref.read(emailConfirmationRepositoryProvider)?.refresh());

  void _startWait() {
    _wait = 60;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _wait--);
      if (_wait <= 0) timer.cancel();
    });
  }

  Future<void> _send() async {
    final repository = ref.read(emailConfirmationRepositoryProvider);
    if (repository == null || _sending) return;
    setState(() {
      _sending = true;
      _notice = null;
      _error = null;
    });
    try {
      await repository.send();
      if (mounted) {
        setState(() {
          _sent = true;
          _startWait();
        });
      }
    } on EmailConfirmationWait catch (wait) {
      if (mounted) setState(() => _notice = wait.message);
      // One reason to be refused is that it is already confirmed.
      _refresh();
    } on DemoAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = AppTypography.bodySm.copyWith(
      color: AppColors.textSecondary,
      height: 1.4,
    );
    final address = TextSpan(
      text: widget.email,
      style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600),
    );
    final waiting = _wait > 0;
    final note = waiting
        ? 'Wait ${_wait}s before requesting another link'
        : _notice;

    return ArangCard(
      color: AppColors.primaryFill,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ArangRowIcon(
                Icons.mail_outline_rounded,
                background: AppColors.surface,
                foreground: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              const Expanded(
                child: Text('Confirm your email', style: AppTypography.h2),
              ),
              IconButton(
                tooltip: 'Hide for now',
                onPressed: () =>
                    ref.read(_confirmEmailHiddenFor).value = widget.email,
                icon: const Icon(
                  Icons.close,
                  size: 18,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.xxs,
              right: AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: body,
                    children: [
                      TextSpan(
                        text: _sent ? 'Link sent to ' : "We'll send a link to ",
                      ),
                      address,
                      const TextSpan(
                        text: '. Open it from your inbox to confirm.',
                      ),
                    ],
                  ),
                ),
                if (widget.isDriver) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Not your email? Ask your LGU/TODA office to correct it.',
                    style: body,
                  ),
                ],
                if (note != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.schedule,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          note,
                          style: body.copyWith(color: AppColors.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _error!,
                    style: body.copyWith(
                      color: AppColors.dangerDeep,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                const Divider(height: 1, color: AppColors.borderStrong),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.xs,
                    children: [
                      if (!widget.isDriver)
                        TextButton(
                          onPressed: () => context.push('/profile/edit'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textRow,
                          ),
                          child: const Text('Change email'),
                        ),
                      ArangButton(
                        label: _sending
                            ? 'Sending…'
                            : _sent
                            ? 'Send again'
                            : 'Send link',
                        expand: false,
                        onPressed: _sending || waiting ? null : _send,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.label.copyWith(color: AppColors.textSecondary),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.showChevron = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: AppRowIcon(Icon(icon), danger: danger),
      title: Text(
        label,
        style: danger ? const TextStyle(color: AppColors.danger) : null,
      ),
      trailing: showChevron ? const Icon(Icons.chevron_right) : null,
      onTap: onTap,
    );
  }
}
