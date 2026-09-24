import '../../domain/models/demo_user.dart';

/// Reviewed, offline instructions for implemented app flows, not AI replies.
class SupportTopic {
  const SupportTopic({
    required this.id,
    required this.title,
    required this.answer,
    required this.keywords,
    this.role,
    this.route,
    this.actionLabel,
  });

  final String id;
  final String title;
  final String answer;
  final String keywords;
  final DemoRole? role;
  final String? route;
  final String? actionLabel;
}

const supportTopics = [
  SupportTopic(
    id: 'booking',
    title: 'How do I book a ride?',
    answer:
        'Choose your destination from Home, check the pickup location, '
        'then follow the ride options and booking review. '
        'If your location is inaccurate, tap Try again to refresh your GPS.',
    keywords: 'book booking ride pickup destination location gps map',
    role: DemoRole.commuter,
    route: '/home/search',
    actionLabel: 'Choose a destination',
  ),
  SupportTopic(
    id: 'saved-places',
    title: 'How do saved places work?',
    answer:
        'Open Saved Places and select Add a Saved Place. Choose a location '
        'to save it. Saved locations also appear in destination '
        'search. They are stored on this device for your account; '
        'the remove button deletes a saved location.',
    keywords: 'save saved places address favorite favourite remove delete',
    role: DemoRole.commuter,
    route: '/profile/saved-places',
    actionLabel: 'Open Saved Places',
  ),
  SupportTopic(
    id: 'driver-documents',
    title: 'Where are my franchise and driver documents?',
    answer:
        'Open Franchise & documents to view your registration details, '
        'uploaded images, and review notes. Tap an uploaded document to zoom in. '
        'Use Refresh records after an update. Your LGU/TODA office manages '
        'corrections, replacements, and approval. Demo accounts have no '
        'uploaded documents.',
    keywords:
        'driver document documents franchise mtop license licence plate '
        'body toda registration review rejected approved verification',
    role: DemoRole.driver,
    route: '/profile/driver-documents',
    actionLabel: 'Open Franchise & documents',
  ),
  SupportTopic(
    id: 'driver-online',
    title: 'How do I receive ride requests?',
    answer:
        'Use Go online on the driver dashboard. If going online is blocked, '
        'follow the message shown there. Your LGU/TODA office manages driver '
        'registration and approval.',
    keywords: 'driver online offline request requests rides dispatch queue',
    role: DemoRole.driver,
    route: '/driver',
    actionLabel: 'Open driver dashboard',
  ),
  SupportTopic(
    id: 'notifications',
    title: 'How do I change notification settings?',
    answer:
        'Open Settings, then Notification settings. On Android, this opens '
        'your phone’s controls for ArangCada alerts and sounds. The app '
        'refreshes the permission status when you return. Individual alert '
        'categories may still be muted even when app notifications are allowed.',
    keywords:
        'notification notifications alert alerts sound mute muted permission',
    route: '/profile/app-settings',
    actionLabel: 'Open Settings',
  ),
  SupportTopic(
    id: 'password',
    title: 'How do I change my password?',
    answer:
        'Open Settings, then Password. Enter your current password and '
        'confirm a new password with at least 8 characters. If you forgot '
        'your password, use Forgot password on the sign-in screen. '
        'Password changes are unavailable for demo accounts.',
    keywords:
        'password passwords forgot forgotten reset login sign in account security',
    route: '/profile/app-settings',
    actionLabel: 'Open Settings',
  ),
  SupportTopic(
    id: 'safety',
    title: 'What does SOS do?',
    answer:
        'During an active ride, press and hold SOS and choose what happened. '
        'A connected account sends a report to ArangCada LGU/TODA administrators. '
        'A demo account only records it locally. This help guide does not send '
        'reports, and SOS does not contact police or emergency services.',
    keywords:
        'sos safety unsafe danger emergency police report accident harassment',
  ),
];

/// Return selectable topics; a keyword match does not resolve an account issue.
List<SupportTopic> findSupportTopics(String query, DemoRole? role) {
  const ignored = {
    'a',
    'an',
    'the',
    'i',
    'my',
    'me',
    'do',
    'does',
    'how',
    'what',
    'where',
    'why',
    'can',
    'is',
    'are',
    'to',
    'in',
    'on',
    'for',
    'with',
    'please',
    'help',
  };
  final words = query
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((word) => word.isNotEmpty && !ignored.contains(word))
      .toSet();
  return supportTopics.where((topic) {
    if (topic.role != null && topic.role != role) return false;
    if (words.isEmpty) return true;
    final terms = '${topic.title} ${topic.keywords}'
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .toSet();
    return words.any(terms.contains);
  }).toList();
}
