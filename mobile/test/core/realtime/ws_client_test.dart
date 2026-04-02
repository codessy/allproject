import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:walkietalkie_mobile/src/core/realtime/ws_client.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  group('WsClient', () {
    test('decodes incoming JSON messages', () async {
      final fakeChannel = _FakeWebSocketChannel();
      final client = WsClient(connector: (_) => fakeChannel);

      client.connect('ws://localhost:8080/v1/ws');
      final nextMessage = client.messages.first;
      fakeChannel.emit('{"type":"presence.pong","ok":true}');

      final message = await nextMessage;
      expect(message['type'], 'presence.pong');
      expect(message['ok'], true);
    });

    test('encodes outgoing messages as JSON', () {
      final fakeChannel = _FakeWebSocketChannel();
      final client = WsClient(connector: (_) => fakeChannel);

      client.connect('ws://localhost:8080/v1/ws');
      client.send(<String, dynamic>{'type': 'speaker.request', 'channelId': 'alpha'});

      expect(fakeChannel.sentMessages, hasLength(1));
      expect(
        jsonDecode(fakeChannel.sentMessages.single) as Map<String, dynamic>,
        <String, dynamic>{'type': 'speaker.request', 'channelId': 'alpha'},
      );
    });

    test('returns empty stream before connect', () async {
      final client = WsClient();
      expect(await client.messages.isEmpty, true);
    });

    test('non-string incoming payload maps to empty object', () async {
      final fakeChannel = _FakeWebSocketChannel();
      final client = WsClient(connector: (_) => fakeChannel);

      client.connect('ws://localhost:8080/v1/ws');
      final nextMessage = client.messages.first;
      fakeChannel.emit(<int>[1, 2, 3]);

      final message = await nextMessage;
      expect(message, <String, dynamic>{});
    });

    test('invalid JSON incoming payload maps to empty object', () async {
      final fakeChannel = _FakeWebSocketChannel();
      final client = WsClient(connector: (_) => fakeChannel);

      client.connect('ws://localhost:8080/v1/ws');
      final nextMessage = client.messages.first;
      fakeChannel.emit('{invalid');

      final message = await nextMessage;
      expect(message, <String, dynamic>{});
    });

    test('send before connect is a safe no-op', () {
      final client = WsClient();
      expect(
        () => client.send(<String, dynamic>{'type': 'noop'}),
        returnsNormally,
      );
    });

    test('dispose closes active socket sink', () async {
      final fakeChannel = _FakeWebSocketChannel();
      final client = WsClient(connector: (_) => fakeChannel);

      client.connect('ws://localhost:8080/v1/ws');
      await client.dispose();

      expect(fakeChannel.sinkCloseCalls, 1);
    });

    test('connect closes previous socket before replacing channel', () {
      final first = _FakeWebSocketChannel();
      final second = _FakeWebSocketChannel();
      var connectCalls = 0;
      final client = WsClient(
        connector: (_) {
          connectCalls += 1;
          return connectCalls == 1 ? first : second;
        },
      );

      client.connect('ws://localhost:8080/v1/ws?session=one');
      client.connect('ws://localhost:8080/v1/ws?session=two');

      expect(first.sinkCloseCalls, 1);
      expect(second.sinkCloseCalls, 0);
    });

    test('send after reconnect uses latest channel only', () {
      final first = _FakeWebSocketChannel();
      final second = _FakeWebSocketChannel();
      var connectCalls = 0;
      final client = WsClient(
        connector: (_) {
          connectCalls += 1;
          return connectCalls == 1 ? first : second;
        },
      );

      client.connect('ws://localhost:8080/v1/ws?session=one');
      client.connect('ws://localhost:8080/v1/ws?session=two');
      client.send(<String, dynamic>{'type': 'ping'});

      expect(first.sentMessages, isEmpty);
      expect(second.sentMessages, hasLength(1));
    });
  });
}

class _FakeWebSocketChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final StreamController<dynamic> _streamController =
      StreamController<dynamic>.broadcast();
  final List<String> sentMessages = <String>[];
  final _FakeWebSocketSink _sink = _FakeWebSocketSink();
  int sinkCloseCalls = 0;

  _FakeWebSocketChannel() {
    _sink.onAdd = (dynamic data) {
      sentMessages.add(data as String);
    };
    _sink.onClose = () {
      sinkCloseCalls += 1;
    };
  }

  void emit(dynamic event) {
    _streamController.add(event);
  }

  @override
  Stream<dynamic> get stream => _streamController.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future get ready => Future<void>.value();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;
}

class _FakeWebSocketSink implements WebSocketSink {
  void Function(dynamic data)? onAdd;
  void Function()? onClose;

  @override
  void add(dynamic data) {
    onAdd?.call(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    onClose?.call();
  }

  @override
  Future get done => Future<void>.value();

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) async {}
}
