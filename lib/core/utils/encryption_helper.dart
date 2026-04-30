@Deprecated('Use SecureMessageCrypto through providers instead.')
class EncryptionHelper {
  EncryptionHelper._();

  static Never encryptMessage(String text) {
    throw UnsupportedError(
      'The legacy static encryption helper has been retired. '
      'Use SecureMessageCrypto with per-user keys instead.',
    );
  }

  static Never decryptMessage(String encryptedText) {
    throw UnsupportedError(
      'The legacy static encryption helper has been retired. '
      'Use SecureMessageCrypto with per-user keys instead.',
    );
  }
}
