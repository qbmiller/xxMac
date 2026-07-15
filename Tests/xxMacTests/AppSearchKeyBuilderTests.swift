import XCTest
@testable import xxMac

final class AppSearchKeyBuilderTests: XCTestCase {
    func testChineseNameAddsPinyinAndInitialKeys() {
        let keys = AppSearchKeyBuilder.keys(for: ["微信"])

        XCTAssertTrue(keys.normalized.contains("微信"))
        XCTAssertTrue(keys.normalized.contains("wei xin"))
        XCTAssertTrue(keys.compact.contains("weixin"))
        XCTAssertTrue(keys.compact.contains("wx"))
    }

    func testEnglishNameAddsInitialKeys() {
        let keys = AppSearchKeyBuilder.keys(for: ["Visual Studio Code"])

        XCTAssertTrue(keys.normalized.contains("visual studio code"))
        XCTAssertTrue(keys.compact.contains("visualstudiocode"))
        XCTAssertTrue(keys.compact.contains("vsc"))
    }

    func testMixedChineseAndEnglishNameIsSearchable() {
        let keys = AppSearchKeyBuilder.keys(for: ["腾讯会议"])

        XCTAssertTrue(keys.normalized.contains("腾讯会议"))
        XCTAssertTrue(keys.normalized.contains("teng xun hui yi"))
        XCTAssertTrue(keys.compact.contains("tengxunhuiyi"))
        XCTAssertTrue(keys.compact.contains("txhy"))
    }

    func testMusicNameAddsYueInitialAlias() {
        let keys = AppSearchKeyBuilder.keys(for: ["音乐"])

        XCTAssertTrue(keys.normalized.contains("yin le"))
        XCTAssertTrue(keys.compact.contains("yl"))
        XCTAssertTrue(keys.normalized.contains("yinyue"))
        XCTAssertTrue(keys.compact.contains("yy"))
    }

    func testPhrasePinyinAliasIsSearchable() {
        let keys = AppSearchKeyBuilder.keys(for: ["汽水音乐"])

        XCTAssertTrue(keys.normalized.contains("yinyue"))
        XCTAssertTrue(keys.compact.contains("yinyue"))
        XCTAssertTrue(keys.compact.contains("yy"))
    }
}
