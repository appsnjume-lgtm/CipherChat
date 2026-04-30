import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'cipher_envelope.dart';
import 'identity_key_service.dart';

class WrappedPayloadKeys {
  const WrappedPayloadKeys({
    required this.senderPublicKeyBase64,
    required this.keyEnvelopes,
    required this.payloadKey,
  });

  final String senderPublicKeyBase64;
  final Map<String, CipherEnvelope> keyEnvelopes;
  final SecretKey payloadKey;

  Map<String, dynamic> toMap() {
    return {
      for (final entry in keyEnvelopes.entries) entry.key: entry.value.toMap(),
    };
  }
}

class SecureMessageCrypto {
  SecureMessageCrypto(this._identityKeyService);

  static const _payloadKeyLength = 32;
  static const _nonceLength = 12;

  final IdentityKeyService _identityKeyService;
  final AesGcm _aesGcm = AesGcm.with256bits();
  final X25519 _x25519 = X25519();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: _payloadKeyLength);
  final Random _random = Random.secure();

  Future<WrappedPayloadKeys> createPayloadKeyBundle({
    required String currentUserId,
    required String chatId,
    required Map<String, String> participantPublicKeys,
  }) async {
    final identity = await _identityKeyService.ensureIdentity(currentUserId);
    final payloadKey = SecretKey(_randomBytes(_payloadKeyLength));

    final envelopes = <String, CipherEnvelope>{};
    for (final entry in participantPublicKeys.entries) {
      final wrapKey = await _deriveWrapKey(
        chatId: chatId,
        privateKey: identity.privateKey,
        localPublicKeyBase64: identity.publicKeyBase64,
        remotePublicKeyBase64: entry.value,
      );
      envelopes[entry.key] = await encryptSecretKey(payloadKey, wrapKey);
    }

    return WrappedPayloadKeys(
      senderPublicKeyBase64: identity.publicKeyBase64,
      keyEnvelopes: envelopes,
      payloadKey: payloadKey,
    );
  }

  Future<CipherEnvelope> encryptJson({
    required Map<String, dynamic> payload,
    required SecretKey secretKey,
    required String aad,
  }) {
    return encryptBytes(
      utf8.encode(jsonEncode(payload)),
      secretKey: secretKey,
      aad: aad,
    );
  }

  Future<Map<String, dynamic>> decryptJson({
    required CipherEnvelope envelope,
    required SecretKey secretKey,
    required String aad,
  }) async {
    final bytes = await decryptBytes(envelope, secretKey: secretKey, aad: aad);
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<CipherEnvelope> encryptText({
    required String plaintext,
    required SecretKey secretKey,
    required String aad,
  }) {
    return encryptJson(
      payload: {'text': plaintext},
      secretKey: secretKey,
      aad: aad,
    );
  }

  Future<String> decryptText({
    required CipherEnvelope envelope,
    required SecretKey secretKey,
    required String aad,
  }) async {
    final payload = await decryptJson(
      envelope: envelope,
      secretKey: secretKey,
      aad: aad,
    );
    return payload['text'] as String? ?? '';
  }

  Future<CipherEnvelope> encryptBytes(
    List<int> bytes, {
    required SecretKey secretKey,
    required String aad,
  }) async {
    final box = await _aesGcm.encrypt(
      Uint8List.fromList(bytes),
      secretKey: secretKey,
      nonce: _randomBytes(_nonceLength),
      aad: utf8.encode(aad),
    );
    return CipherEnvelope.fromSecretBox(box);
  }

  Future<Uint8List> decryptBytes(
    CipherEnvelope envelope, {
    required SecretKey secretKey,
    required String aad,
  }) async {
    final plain = await _aesGcm.decrypt(
      envelope.toSecretBox(),
      secretKey: secretKey,
      aad: utf8.encode(aad),
    );
    return Uint8List.fromList(plain);
  }

  Future<CipherEnvelope> encryptSecretKey(
    SecretKey payloadKey,
    SecretKey wrapKey,
  ) async {
    final payloadKeyBytes = await payloadKey.extractBytes();
    return encryptBytes(payloadKeyBytes, secretKey: wrapKey, aad: 'key-wrap');
  }

  Future<SecretKey> unwrapPayloadKey({
    required String currentUserId,
    required String chatId,
    required String senderPublicKeyBase64,
    required CipherEnvelope wrappedKey,
  }) async {
    final privateKey = await _identityKeyService.privateKeyFor(currentUserId);
    final localPublicKeyBase64 = await _identityKeyService.publicKeyFor(
      currentUserId,
    );
    final wrapKey = await _deriveWrapKey(
      chatId: chatId,
      privateKey: privateKey,
      localPublicKeyBase64: localPublicKeyBase64,
      remotePublicKeyBase64: senderPublicKeyBase64,
    );
    final plainKey = await decryptBytes(
      wrappedKey,
      secretKey: wrapKey,
      aad: 'key-wrap',
    );
    return SecretKey(plainKey);
  }

  Future<SecretKey> _deriveWrapKey({
    required String chatId,
    required SimpleKeyPair privateKey,
    required String localPublicKeyBase64,
    required String remotePublicKeyBase64,
  }) async {
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: privateKey,
      remotePublicKey: _identityKeyService.publicKeyFromBase64(
        remotePublicKeyBase64,
      ),
    );

    final ordered = [localPublicKeyBase64, remotePublicKeyBase64]..sort();
    return _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('cipherchat-wrap-salt:$chatId'),
      info: utf8.encode('cipherchat-wrap-info:${ordered.join(':')}'),
    );
  }

  List<int> _randomBytes(int length) {
    return List<int>.generate(
      length,
      (_) => _random.nextInt(256),
      growable: false,
    );
  }
}
