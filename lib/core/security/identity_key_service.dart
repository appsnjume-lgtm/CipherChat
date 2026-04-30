import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'secure_storage_service.dart';

class IdentityKeys {
  const IdentityKeys({
    required this.privateKey,
    required this.publicKey,
    required this.publicKeyBase64,
  });

  final SimpleKeyPair privateKey;
  final SimplePublicKey publicKey;
  final String publicKeyBase64;
}

class IdentityKeyService {
  IdentityKeyService({
    required SecureStorageService storage,
    required SupabaseClient client,
  }) : _storage = storage,
       _client = client;

  static const _privateKeyPrefix = 'cipherchat.identity.private';
  static const _publicKeyPrefix = 'cipherchat.identity.public';

  final SecureStorageService _storage;
  final SupabaseClient _client;
  final X25519 _algorithm = X25519();

  Future<IdentityKeys> ensureIdentity(String userId) async {
    final privateKeyValue = await _storage.read(_privateKeyKey(userId));
    final publicKeyValue = await _storage.read(_publicKeyKey(userId));

    if (privateKeyValue != null && publicKeyValue != null) {
      return _keysFromBase64(
        privateKeyBase64: privateKeyValue,
        publicKeyBase64: publicKeyValue,
      );
    }

    final keyPair = await _algorithm.newKeyPair();
    final data = await keyPair.extract();
    final privateKeyBase64 = base64Encode(data.bytes);
    final publicKeyBase64 = base64Encode(data.publicKey.bytes);

    await _storage.write(_privateKeyKey(userId), privateKeyBase64);
    await _storage.write(_publicKeyKey(userId), publicKeyBase64);

    return _keysFromBase64(
      privateKeyBase64: privateKeyBase64,
      publicKeyBase64: publicKeyBase64,
    );
  }

  Future<String> ensurePublishedIdentity(String userId) async {
    final identity = await ensureIdentity(userId);
    final profile = await _client
        .from('profiles')
        .select('e2ee_public_key')
        .eq('id', userId)
        .maybeSingle();

    final existing = profile?['e2ee_public_key'] as String?;
    if (existing != identity.publicKeyBase64) {
      await _client
          .from('profiles')
          .update({'e2ee_public_key': identity.publicKeyBase64})
          .eq('id', userId);
    }

    return identity.publicKeyBase64;
  }

  Future<SimpleKeyPair> privateKeyFor(String userId) async {
    return (await ensureIdentity(userId)).privateKey;
  }

  Future<String> publicKeyFor(String userId) async {
    return (await ensureIdentity(userId)).publicKeyBase64;
  }

  SimplePublicKey publicKeyFromBase64(String value) {
    return SimplePublicKey(base64Decode(value), type: KeyPairType.x25519);
  }

  IdentityKeys _keysFromBase64({
    required String privateKeyBase64,
    required String publicKeyBase64,
  }) {
    final publicKey = publicKeyFromBase64(publicKeyBase64);
    return IdentityKeys(
      privateKey: SimpleKeyPairData(
        base64Decode(privateKeyBase64),
        publicKey: publicKey,
        type: KeyPairType.x25519,
      ),
      publicKey: publicKey,
      publicKeyBase64: publicKeyBase64,
    );
  }

  String _privateKeyKey(String userId) => '$_privateKeyPrefix.$userId';

  String _publicKeyKey(String userId) => '$_publicKeyPrefix.$userId';
}
