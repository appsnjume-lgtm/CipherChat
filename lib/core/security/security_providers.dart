import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase_service.dart';
import 'identity_key_service.dart';
import 'secure_message_crypto.dart';
import 'secure_storage_service.dart';

final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final identityKeyServiceProvider = Provider<IdentityKeyService>((ref) {
  final storage = ref.watch(secureStorageServiceProvider);
  final client = ref.watch(supabaseServiceProvider).client;
  return IdentityKeyService(storage: storage, client: client);
});

final secureMessageCryptoProvider = Provider<SecureMessageCrypto>((ref) {
  final identity = ref.watch(identityKeyServiceProvider);
  return SecureMessageCrypto(identity);
});
