/*
 * Package : mqtt_client
 * Author : S. Hamblett <steve.hamblett@linux.com>
 * Date   : 30/06/2017
 * Copyright :  S.Hamblett
 */

part of mqtt_client;

/// A class that can manage the topic subscription process.
class SubscriptionsManager {
  /// Dispenser used for keeping track of subscription ids
  MessageIdentifierDispenser messageIdentifierDispenser =
      MessageIdentifierDispenser();

  /// List of confirmed subscriptions, keyed on the topic name.
  Map<String, Subscription> subscriptions = Map<String, Subscription>();

  /// A list of subscriptions that are pending acknowledgement, keyed on the message identifier.
  Map<int, Subscription> pendingSubscriptions = Map<int, Subscription>();

  /// The connection handler that we use to subscribe to subscription acknowledgements.
  IMqttConnectionHandler connectionHandler;

  /// Publishing manager used for passing on published messages to subscribers.
  PublishingManager publishingManager;

  ///  Creates a new instance of a SubscriptionsManager that uses the specified connection to manage subscriptions.
  SubscriptionsManager(IMqttConnectionHandler connectionHandler,
      IPublishingManager publishingManager) {
    this.connectionHandler = connectionHandler;
    this.publishingManager = publishingManager;
    this
        .connectionHandler
        .registerForMessage(MqttMessageType.subscribeAck, confirmSubscription);
    this
        .connectionHandler
        .registerForMessage(MqttMessageType.unsubscribeAck, confirmUnsubscribe);
    // Start listening for published messages
    clientEventBus.on<MessageReceived>().listen(publishMessageReceived);
  }

  /// Observable change notifier for all subscribed topics
  final observe.ChangeNotifier<MqttReceivedMessage> _subscriptionNotifier =
      observe.ChangeNotifier<MqttReceivedMessage>();

  observe.ChangeNotifier<MqttReceivedMessage> get subscriptionNotifier =>
      _subscriptionNotifier;

  /// Registers a new subscription with the subscription manager.
  Subscription registerSubscription(String topic, MqttQos qos) {
    var cn = tryGetExistingSubscription(topic);
    if (cn == null) {
      cn = createNewSubscription(topic, qos);
    }
    return cn;
  }

  /// Gets a view on the existing observable, if the subscription already exists.
  Subscription tryGetExistingSubscription(String topic) {
    final Subscription retSub = subscriptions[topic];
    if (retSub == null) {
      // Search the pending subscriptions
      for (Subscription sub in pendingSubscriptions.values) {
        if (sub.topic.rawTopic == topic) {
          return sub;
        }
      }
    }
    return retSub;
  }

  /// Creates a new subscription for the specified topic.
  Subscription createNewSubscription(String topic, MqttQos qos) {
    try {
      final SubscriptionTopic subscriptionTopic = SubscriptionTopic(topic);
      // Get an ID that represents the subscription. We will use this same ID for unsubscribe as well.
      final int msgId =
          messageIdentifierDispenser.getNextMessageIdentifier("subscriptions");
      final Subscription sub = Subscription();
      sub.topic = subscriptionTopic;
      sub.qos = qos;
      sub.messageIdentifier = msgId;
      sub.createdTime = DateTime.now();
      pendingSubscriptions[sub.messageIdentifier] = sub;
      // Build a subscribe message for the caller and send it off to the broker.
      final MqttSubscribeMessage msg = MqttSubscribeMessage()
          .withMessageIdentifier(sub.messageIdentifier)
          .toTopic(sub.topic.rawTopic)
          .atQos(sub.qos);
      connectionHandler.sendMessage(msg);
      return sub;
    } catch (Exception) {
      throw InvalidTopicException(
          "from SubscriptionManager::createNewSubscription", topic);
    }
  }

  /// Publish message received
  void publishMessageReceived(MessageReceived event) {
    final topic = event.topic;
    final msg = MqttReceivedMessage<MqttMessage>(topic.rawTopic, event.message);
    subscriptionNotifier.notifyChange(msg);
  }

  /// Unsubscribe from a topic
  void unsubscribe(String topic) {
    final MqttUnsubscribeMessage unsubscribeMsg = MqttUnsubscribeMessage()
        .withMessageIdentifier(messageIdentifierDispenser
            .getNextMessageIdentifier("unsubscriptions"))
        .fromTopic(topic);
    connectionHandler.sendMessage(unsubscribeMsg);
  }

  /// Confirms a subscription has been made with the broker. Marks the sub as confirmed in the subs storage.
  /// Returns true, always.
  bool confirmSubscription(MqttMessage msg) {
    final MqttSubscribeAckMessage subAck = msg as MqttSubscribeAckMessage;
    if (pendingSubscriptions
        .containsKey(subAck.variableHeader.messageIdentifier)) {
      final String topic =
          pendingSubscriptions[subAck.variableHeader.messageIdentifier]
              .topic
              .rawTopic;
      subscriptions[topic] =
          pendingSubscriptions[subAck.variableHeader.messageIdentifier];
      pendingSubscriptions.remove(subAck.variableHeader.messageIdentifier);
    }
    return true;
  }

  /// Cleans up after an unsubscribe message is received from the broker.
  /// returns true, always
  bool confirmUnsubscribe(MqttMessage msg) {
    final MqttUnsubscribeAckMessage unSubAck = msg as MqttUnsubscribeAckMessage;
    String subKey;
    Subscription sub;
    subscriptions.forEach((String key, Subscription value) {
      if (value.messageIdentifier ==
          unSubAck.variableHeader.messageIdentifier) {
        sub = value;
        subKey = key;
      }
    });
    // If we have the subscription remove it
    if (sub != null) {
      subscriptions.remove(subKey);
    }

    return true;
  }

  /// Gets the current status of a subscription.
  SubscriptionStatus getSubscriptionsStatus(String topic) {
    SubscriptionStatus status = SubscriptionStatus.doesNotExist;
    if (subscriptions.containsKey(topic)) {
      status = SubscriptionStatus.active;
    }
    pendingSubscriptions.forEach((int key, Subscription value) {
      if (value.topic.rawTopic == topic) {
        status = SubscriptionStatus.pending;
      }
    });
    return status;
  }
}
