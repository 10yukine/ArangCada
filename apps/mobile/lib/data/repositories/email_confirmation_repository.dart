import 'auth_repository.dart';

/// Email confirmation by a link the account holder opens in a browser.
///
/// Separate from the phone code: the code proves the number, this proves the
/// mailbox. Nothing in the app is withheld from an unconfirmed email; the
/// Profile screen shows a prompt until it is done.
abstract class EmailConfirmationRepository {
  /// Mails the link to the address on the signed-in account.
  ///
  /// Throws [EmailConfirmationWait] with the server's sentence when it will
  /// not send one yet (asked a moment ago, too many today), and a plain
  /// `DemoAuthException` when the link could not be sent.
  Future<void> send();

  /// Picks up a confirmation made in the browser and updates the signed-in
  /// user. Quiet when it cannot be read: the prompt simply stays.
  Future<void> refresh();
}

/// The server will not send a link yet. A wait for the user, not a failure,
/// so the prompt shows it without alarm.
class EmailConfirmationWait extends DemoAuthException {
  const EmailConfirmationWait(super.message);
}
