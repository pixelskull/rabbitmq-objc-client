import XCTest

class IntegrationTests: XCTestCase {
    
    func testPop() {
        let transport = RMQTCPSocketTransport(host: "localhost", port: 5672)
        let frameMaxRequiringTwoFrames = 4096
        var messageContent = ""
        for _ in 1...(frameMaxRequiringTwoFrames - AMQEmptyFrameSize) {
            messageContent += "a"
        }
        messageContent += "bb"

        let conn = RMQConnection(
            transport: transport,
            user: "guest",
            password: "guest",
            vhost: "/",
            channelMax: 65535,
            frameMax: frameMaxRequiringTwoFrames,
            heartbeat: 0,
            syncTimeout: 10
        )
        conn.start()
        defer { conn.close() }

        let ch = conn.createChannel()
        let q = ch.queue(generatedQueueName(), autoDelete: true, exclusive: false)

        q.publish(messageContent)

        let message = q.pop() as! RMQContentMessage

        let expected = RMQContentMessage(consumerTag: "", deliveryTag: 1, content: messageContent)
        XCTAssertEqual(expected, message)
    }

    func testSubscribe() {
        let transport = RMQTCPSocketTransport(host: "localhost", port: 5672)
        let conn = RMQConnection(
            transport: transport,
            user: "guest",
            password: "guest",
            vhost: "/",
            channelMax: 65535,
            frameMax: 4096,
            heartbeat: 1,
            syncTimeout: 10
        )
        conn.start()
        defer { conn.close() }

        let ch = conn.createChannel()
        let q = ch.queue(generatedQueueName(), autoDelete: true, exclusive: false)

        var delivered = RMQContentMessage(consumerTag: "", deliveryTag: 0, content: "not delivered yet")
        q.subscribe { (message: RMQMessage) in
            delivered = message as! RMQContentMessage
        }

        q.publish("my message")

        XCTAssert(TestHelper.pollUntil { return delivered.content != "not delivered yet" })

        XCTAssertEqual(1, delivered.deliveryTag)
        XCTAssertEqual("my message", delivered.content)
    }

    func testMultipleConsumersOnSameChannel() {
        let transport = RMQTCPSocketTransport(host: "localhost", port: 5672)
        let conn = RMQConnection(
            transport: transport,
            user: "guest",
            password: "guest",
            vhost: "/",
            channelMax: 65535,
            frameMax: 4096,
            heartbeat: 0,
            syncTimeout: 10
        )
        conn.start()
        defer { conn.close() }

        var set1 = Set<NSNumber>()
        var set2 = Set<NSNumber>()
        var set3 = Set<NSNumber>()

        let consumingChannel = conn.createChannel()
        let queueName = generatedQueueName()
        let consumingQueue = consumingChannel.queue(queueName, autoDelete: false, exclusive: false)

        consumingQueue.subscribe { (message: RMQMessage) in
            set1.insert(message.deliveryTag)
        }

        consumingQueue.subscribe { (message: RMQMessage) in
            set2.insert(message.deliveryTag)
        }

        consumingQueue.subscribe { (message: RMQMessage) in
            set3.insert(message.deliveryTag)
        }

        let producingChannel = conn.createChannel()
        let producingQueue = producingChannel.queue(queueName, autoDelete: false, exclusive: false)

        for _ in 1...100 {
            producingQueue.publish("hello")
        }

        TestHelper.pollUntil { return set1.union(set2).union(set3).count == 100 }

        XCTAssertFalse(set1.isEmpty)
        XCTAssertFalse(set2.isEmpty)
        XCTAssertFalse(set3.isEmpty)

        let expected: Set<NSNumber> = Set<NSNumber>().union((1...100).map { NSNumber(integer: $0) })
        XCTAssertEqual(expected, set1.union(set2).union(set3))

//        XCTAssertEqual(0, producingQueue.messageCount)
    }

    func generatedQueueName() -> String {
        return "rmqclient.integration-tests.\(NSProcessInfo.processInfo().globallyUniqueString)"
    }
}
