import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

typedef WsChannelConnector = WebSocketChannel Function(Uri uri);

class WsClient {
  WsClient({WsChannelConnector? connector})
      : _connector = connector ?? WebSocketChannel.connect;

  WebSocketChannel? _channel;
  final WsChannelConnector _connector;

  void connect(String url) {
    _channel?.sink.close();
    _channel = _connector(Uri.parse(url));
  }

  Stream<Map<String, dynamic>> get messages {
    final channel = _channel;
    if (channel == null) {
      return const Stream.empty();
    }
    return channel.stream.map((event) {
      if (event is String) {
        try {
          final decoded = jsonDecode(event);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
          return <String, dynamic>{};
        } catch (_) {
          return <String, dynamic>{};
        }
      }
      return <String, dynamic>{};
    });
  }

  void send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  Future<void> dispose() async {
    await _channel?.sink.close();
  }
}
