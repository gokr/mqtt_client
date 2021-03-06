import 'dart:io';
import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:path/path.dart' as path;
import 'package:typed_data/typed_data.dart' as typed;

typedef void MessageHandlerFunction(typed.Uint8Buffer message);

/// Helper methods for test message serialization and deserialization
class MessageSerializationHelper {
  /// Invokes the serialization of a message to get an array of bytes that represent the message.
  static typed.Uint8Buffer getMessageBytes(MqttMessage msg) {
    final typed.Uint8Buffer buff = typed.Uint8Buffer();
    final MqttByteBuffer ms = MqttByteBuffer(buff);
    msg.writeTo(ms);
    ms.seek(0);
    final typed.Uint8Buffer msgBytes = ms.read(ms.length);
    return msgBytes;
  }
}

/// Mocks a broker, such as the RSMB, so that we can test the MqttConnection class, and some bits of the
/// connection handlers that are difficult to test otherwise. standard TCP connection.
class MockBroker {
  int brokerPort = 1883;
  ServerSocket listener;
  MessageHandlerFunction handler;
  Socket client = null;
  MqttByteBuffer networkstream;
  typed.Uint8Buffer headerBytes = typed.Uint8Buffer(1);

  MockBroker();

  Future start() {
    final Completer completer = Completer();
    ServerSocket.bind("localhost", brokerPort).then((ServerSocket server) {
      listener = server;
      listener.listen(_connectAccept);
      print("MockBroker::we are bound");
      return completer.complete();
    });
    return completer.future;
  }

  void _connectAccept(Socket clientSocket) {
    print("MockBroker::connectAccept");
    client = clientSocket;
    client.listen(_dataArrivedOnConnection);
  }

  void _dataArrivedOnConnection(List<int> data) {
    print("MockBroker::data arrived ${data.toString()}");
    final typed.Uint8Buffer dataBytesBuff = typed.Uint8Buffer();
    dataBytesBuff.addAll(data);
    if (networkstream == null) {
      networkstream = MqttByteBuffer(dataBytesBuff);
    } else {
      networkstream.write(dataBytesBuff);
    }
    networkstream.seek(0);
    // Assume will have all the data for localhost testing purposes
    final MqttMessage msg = MqttMessage.createFrom(networkstream);
    print(msg.toString());
    handler(networkstream.buffer);
    networkstream = null;
  }

  /// Sets a function that will be passed the next message received by the faked out broker.
  void setMessageHandler(MessageHandlerFunction messageHandler) {
    handler = messageHandler;
  }

  /// Sends the message to the client connected to the broker.
  void sendMessage(MqttMessage msg) {
    print("MockBroker::sending message ${msg.toString()}");
    final typed.Uint8Buffer messBuff =
    MessageSerializationHelper.getMessageBytes(msg);
    print("MockBroker::sending message bytes ${messBuff.toString()}");
    client.add(messBuff.toList());
  }

  /// Close the broker socket
  void close() {}
}

/// Mocks a broker, such as the RSMB, so that we can test the MqttConnection class, and some bits of the
/// connection handlers that are difficult to test otherwise. websocket connection.
class MockBrokerWs {
  int port = 8080;
  MessageHandlerFunction handler;
  MqttByteBuffer networkstream;
  typed.Uint8Buffer headerBytes = typed.Uint8Buffer(1);
  WebSocket _webSocket;

  MockBrokerWs();

  void _handleMessage(dynamic data) {
    // Listen for incoming data.
    print("MockBrokerWs::data arrived ${data.toString()}");
    final typed.Uint8Buffer dataBytesBuff = typed.Uint8Buffer();
    dataBytesBuff.addAll(data);
    if (networkstream == null) {
      networkstream = MqttByteBuffer(dataBytesBuff);
    } else {
      networkstream.write(dataBytesBuff);
    }
    networkstream.seek(0);
    // Assume will have all the data for localhost testing purposes
    final MqttMessage msg = MqttMessage.createFrom(networkstream);
    print(msg.toString());
    handler(networkstream.buffer);
    networkstream = null;
  }

  Future start() {
    final Completer completer = Completer();
    HttpServer.bind(InternetAddress.loopbackIPv4, port).then((server) {
      print("Mockbroker WS server is running on "
          "'http://${server.address.address}:$port/'");
      server.listen((HttpRequest request) {
        if (request.uri.path == '/ws') {
          WebSocketTransformer.upgrade(request).then((WebSocket websocket) {
            _webSocket = websocket;
            websocket.listen((message) => _handleMessage(message));
          });
        }
      });
      return completer.complete();
    });
    return completer.future;
  }

  /// Sets a function that will be passed the next message received by the faked out broker.
  void setMessageHandler(MessageHandlerFunction messageHandler) {
    handler = messageHandler;
  }

  /// Sends the message to the client connected to the broker.
  void sendMessage(MqttMessage msg) {
    print("MockBrokerWs::sending message ${msg.toString()}");
    final typed.Uint8Buffer messBuff =
    MessageSerializationHelper.getMessageBytes(msg);
    print("MockBrokerWS::sending message bytes ${messBuff.toString()}");
    _webSocket.add(messBuff.toList());
  }

  /// Close the broker socket
  void close() {
    _webSocket.close();
  }
}

/// Mocks a broker, such as the RSMB, so that we can test the MqttConnection class, and some bits of the
/// connection handlers that are difficult to test otherwise. standard TCP connection.
class MockBrokerSecure {
  int brokerPort = 8883;
  SecureServerSocket listener;
  MessageHandlerFunction handler;
  SecureSocket client = null;
  MqttByteBuffer networkstream;
  typed.Uint8Buffer headerBytes = typed.Uint8Buffer(1);

  MockBrokerSecure();

  Future start() {
    final Completer completer = Completer();
    final SecurityContext context = SecurityContext.defaultContext;
    final String currDir = path.current + path.separator;
    context.useCertificateChain(
        currDir + path.join("test", "pem", "localhost.cert"));
    context.usePrivateKey(currDir + path.join("test", "pem", "localhost.key"));
    SecureServerSocket.bind("localhost", brokerPort, context)
        .then((SecureServerSocket server) {
      listener = server;
      listener.listen(_connectAccept);
      print("MockBrokerSecure::we are bound");
      return completer.complete();
    });
    return completer.future;
  }

  void _connectAccept(SecureSocket clientSocket) {
    print("MockBrokerSecure::connectAccept");
    client = clientSocket;
    client.listen(_dataArrivedOnConnection);
  }

  void _dataArrivedOnConnection(List<int> data) {
    print("MockBrokerSecure::data arrived ${data.toString()}");
    final typed.Uint8Buffer dataBytesBuff = typed.Uint8Buffer();
    dataBytesBuff.addAll(data);
    if (networkstream == null) {
      networkstream = MqttByteBuffer(dataBytesBuff);
    } else {
      networkstream.write(dataBytesBuff);
    }
    networkstream.seek(0);
    // Assume will have all the data for localhost testing purposes
    final MqttMessage msg = MqttMessage.createFrom(networkstream);
    print(msg.toString());
    handler(networkstream.buffer);
    networkstream = null;
  }

  /// Sets a function that will be passed the next message received by the faked out broker.
  void setMessageHandler(MessageHandlerFunction messageHandler) {
    handler = messageHandler;
  }

  /// Sends the message to the client connected to the broker.
  void sendMessage(MqttMessage msg) {
    print("MockBrokerSecure::sending message ${msg.toString()}");
    final typed.Uint8Buffer messBuff =
    MessageSerializationHelper.getMessageBytes(msg);
    print("MockBrokerSecure::sending message bytes ${messBuff.toString()}");
    client.add(messBuff.toList());
  }

  /// Close the broker socket
  void close() {}
}
