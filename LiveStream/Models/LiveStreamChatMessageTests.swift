// swiftlint:disable function_body_length
import XCTest
import Argo
@testable import LiveStream

final class LiveStreamChatMessageTests: XCTestCase {
  func testParseJson() {
    let json: [String:Any] = [
      "id": "KDeCy9vvd7ZCRwHc8Ca",
      "message": "Test chat message",
      "name": "Test Name",
      "profilePic": "http://www.kickstarter.com/picture.jpg",
      "timestamp": 1234234123,
      "userId": "id_1312341234321"
    ]

    let chatMessage = LiveStreamChatMessage.decodeJSONDictionary(json)

    XCTAssertNil(chatMessage.error)
    XCTAssertEqual("KDeCy9vvd7ZCRwHc8Ca", chatMessage.value?.id)
    XCTAssertEqual("Test chat message", chatMessage.value?.message)
    XCTAssertEqual("Test Name", chatMessage.value?.name)
    XCTAssertEqual("http://www.kickstarter.com/picture.jpg", chatMessage.value?.profilePictureUrl)
    XCTAssertEqual(1234234123, chatMessage.value?.date)
    XCTAssertEqual(1312341234321, chatMessage.value?.userId)
  }
}
