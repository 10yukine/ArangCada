/// Email confirmation by a link the account holder opens in a browser.
///
/// Separate from the phone code: the code proves the number, this proves the
/// mailbox. Nothing in the app is withheld from an unconfirmed email; the
/// Profile screen shows a prompt until it is done.
abstract class EmailConfirmationRepository {
  /// Mails the link to the address on the signed-in account.
  ///
  /// Throws `DemoAuthException` with a sentence for the user when the server
  /// will not send one (asked a moment ago, too many today) or it cannot be
  /// sent.
  Future<void> send();

  /// Picks up a confirmation made in the browser and updates the signed-in
  /// user. Quiet when it cannot be read: the prompt simply stays.
  Future<void> refresh();
}
