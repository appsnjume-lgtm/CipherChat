import 'dart:io';

import 'package:metadata_fetch/metadata_fetch.dart';

import '../../features/chat/application/models/resolved_chat_message.dart';

class LinkPreviewService {
  static final RegExp _urlRegExp = RegExp(
    r'(?:(?:https?):\/\/)?[\w/\-?=%.]+\.[\w/\-?=%.]+',
    caseSensitive: false,
  );

  Future<LinkPreviewData?> fetchPreview(String text) async {
    try {
      final match = _urlRegExp.firstMatch(text);
      if (match == null) return null;

      final url = match.group(0);
      if (url == null) return null;

      final normalizedUrl = url.startsWith('http') ? url : 'https://$url';
      final uri = Uri.tryParse(normalizedUrl);
      if (uri == null ||
          (uri.scheme != 'http' && uri.scheme != 'https') ||
          _isPrivateOrLocalHost(uri.host)) {
        return null;
      }

      final data = await MetadataFetch.extract(uri.toString());
      if (data == null) return null;

      return LinkPreviewData(
        url: uri.toString(),
        title: data.title,
        description: data.description,
        imageUrl: data.image,
      );
    } catch (_) {
      return null;
    }
  }

  bool _isPrivateOrLocalHost(String host) {
    final normalizedHost = host.trim().toLowerCase();
    if (normalizedHost.isEmpty) {
      return true;
    }

    if (normalizedHost == 'localhost' ||
        normalizedHost.endsWith('.local') ||
        normalizedHost.endsWith('.internal')) {
      return true;
    }

    final address = InternetAddress.tryParse(normalizedHost);
    if (address == null) {
      return false;
    }

    if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
      return true;
    }

    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      final first = bytes[0];
      final second = bytes[1];
      return first == 10 ||
          first == 127 ||
          (first == 169 && second == 254) ||
          (first == 172 && second >= 16 && second <= 31) ||
          (first == 192 && second == 168);
    }

    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
      return (bytes[0] & 0xfe) == 0xfc ||
          (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80);
    }

    return false;
  }
}
