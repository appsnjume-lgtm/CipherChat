import 'dart:convert';

import 'package:cryptography/cryptography.dart';

class CipherEnvelope {
  const CipherEnvelope({
    required this.nonceBase64,
    required this.cipherTextBase64,
    required this.macBase64,
  });

  final String nonceBase64;
  final String cipherTextBase64;
  final String macBase64;

  List<int> get nonceBytes => base64Decode(nonceBase64);
  List<int> get cipherTextBytes => base64Decode(cipherTextBase64);
  List<int> get macBytes => base64Decode(macBase64);

  SecretBox toSecretBox() {
    return SecretBox(cipherTextBytes, nonce: nonceBytes, mac: Mac(macBytes));
  }

  Map<String, dynamic> toMap() {
    return {
      'nonce': nonceBase64,
      'cipher_text': cipherTextBase64,
      'mac': macBase64,
    };
  }

  factory CipherEnvelope.fromSecretBox(SecretBox secretBox) {
    return CipherEnvelope(
      nonceBase64: base64Encode(secretBox.nonce),
      cipherTextBase64: base64Encode(secretBox.cipherText),
      macBase64: base64Encode(secretBox.mac.bytes),
    );
  }

  factory CipherEnvelope.fromMap(Map<String, dynamic> map) {
    return CipherEnvelope(
      nonceBase64: map['nonce'] as String,
      cipherTextBase64: map['cipher_text'] as String,
      macBase64: map['mac'] as String,
    );
  }
}
