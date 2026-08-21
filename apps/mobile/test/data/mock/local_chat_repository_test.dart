import 'package:arangcada/data/mock/local_chat_repository.dart';
import 'package:arangcada/domain/models/chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('active ride chat supports both roles then becomes read-only', () async {
    final repository = LocalChatRepository();
    addTearDown(repository.dispose);

    final thread = repository.ensureActiveTripThread(
      commuterName: 'Joshua Ramos',
      driverName: 'Marco Dela Cruz',
      bodyNumber: '024',
      todaName: 'Calamba TODA',
    );

    expect(thread.isActiveTrip, isTrue);
    expect(thread.commuterName, 'Joshua Ramos');

    await repository.sendMessage(
      threadId: thread.id,
      body: 'Nandito na po ako',
      author: ChatMessageAuthor.driver,
    );
    await repository.sendMessage(
      threadId: thread.id,
      body: 'Papunta na po',
      author: ChatMessageAuthor.commuter,
    );

    final messages = repository.threadById(thread.id)!.messages;
    expect(messages[messages.length - 2].author, ChatMessageAuthor.driver);
    expect(messages.last.author, ChatMessageAuthor.commuter);

    repository.closeActiveTripThread();
    expect(repository.threadById(thread.id)!.isReadOnly, isTrue);
    expect(
      () => repository.sendMessage(
        threadId: thread.id,
        body: 'Late message',
        author: ChatMessageAuthor.commuter,
      ),
      throwsA(isA<StateError>()),
    );

    repository.clearSession();
    expect(repository.threads, isEmpty);
  });
}
