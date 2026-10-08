import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:pinenacl/ed25519.dart' as nacl;

class GeneratedKey {
  GeneratedKey(this.privatePem, this.publicLine);
  final String privatePem;
  final String publicLine;
}

/// Fresh ed25519 key pair in OpenSSH format (same as `ssh-keygen -t ed25519`).
GeneratedKey generateEd25519({String comment = 'satsh@android', String? passphrase}) {
  final sk = nacl.SigningKey.generate();
  final pub = Uint8List.fromList(sk.verifyKey.asTypedList);
  final priv = Uint8List.fromList(sk.asTypedList); // 64 bytes: seed + public
  final pair = OpenSSHEd25519KeyPair(pub, priv, comment);
  final pubLine = 'ssh-ed25519 ${base64.encode(pair.toPublicKey().encode())} $comment';
  return GeneratedKey(pair.toPem(passphrase: passphrase), pubLine);
}

/// Public key line from a private key PEM (for showing / installing it).
String publicLineFromPem(String pem, {String? passphrase}) {
  final k = SSHKeyPair.fromPem(pem, passphrase).first;
  final pub = k.toPublicKey();
  final type = k.type;
  return '$type ${base64.encode(pub.encode())} satsh@android';
}
