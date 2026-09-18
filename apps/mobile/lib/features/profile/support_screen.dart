import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/empty_state_card.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import 'support_topics.dart';

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({super.key});

  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _query.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            final topics = findSupportTopics(
              _query.text,
              state.currentUser?.role,
            );
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                const Text('Help guide', style: AppTypography.h2),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Search the guides below or tap a topic. These answers work '
                  'offline. No message is sent to a support agent.',
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _query,
                  maxLength: 160,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    labelText: 'Search help',
                    hintText: 'Try “notifications” or “password”',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close),
                            onPressed: _clearSearch,
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (topics.isEmpty)
                  EmptyStateCard(
                    icon: Icons.search_off,
                    title: 'No matching help topics',
                    message: 'Try another word, or browse all topics below.',
                    actionLabel: 'Show all topics',
                    onAction: _clearSearch,
                  )
                else ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      '${topics.length} ${topics.length == 1 ? 'topic' : 'topics'}',
                      style: AppTypography.caption,
                    ),
                  ),
                  for (final topic in topics)
                    ExpansionTile(
                      key: ValueKey(topic.id),
                      tilePadding: EdgeInsets.zero,
                      title: Text(topic.title),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      childrenPadding: const EdgeInsets.only(
                        bottom: AppSpacing.sm,
                      ),
                      children: [
                        Text(topic.answer),
                        if (topic.route != null) ...[
                          const SizedBox(height: AppSpacing.xs),
                          TextButton.icon(
                            onPressed: () {
                              FocusScope.of(context).unfocus();
                              context.push(topic.route!);
                            },
                            icon: const Icon(Icons.arrow_forward),
                            label: Text(topic.actionLabel!),
                          ),
                        ],
                      ],
                    ),
                ],
                const SizedBox(height: AppSpacing.lg),
                const SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Need account-specific help?',
                        style: AppTypography.h2,
                      ),
                      SizedBox(height: AppSpacing.xs),
                      Text(
                        'Contact your LGU/TODA office for registration or '
                        'document corrections. A staffed in-app support desk '
                        'is not configured in this build.',
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
