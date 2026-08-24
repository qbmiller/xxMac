import XCTest
@testable import xxMac

final class ClipboardTextFormatDetectorTests: XCTestCase {
    func testDetectsStrictStructuredFormats() {
        XCTAssertEqual(detect(#"{"name":"xxMac","enabled":true}"#), "json")
        XCTAssertEqual(detect("<root><item id=\"1\"/></root>"), "xml")
        XCTAssertEqual(detect(Self.plistXML), "plist")
    }

    func testDetectsYAMLWithMultipleStructuralSignals() {
        let yaml = """
        services:
          api:
            image: xxmac:1
            ports:
              - 8080
        """

        XCTAssertEqual(detect(yaml), "yml")
    }

    func testDetectsTOMLWithTableAndTypedValues() {
        let toml = """
        [server]
        host = "localhost"
        port = 8080
        enabled = true
        """

        XCTAssertEqual(detect(toml), "toml")
    }

    func testDetectsINIWithSectionAndPlainValues() {
        let ini = """
        [server]
        host=localhost
        port=8080
        """

        XCTAssertEqual(detect(ini), "ini")
    }

    func testDetectsEnvironmentAssignments() {
        let environment = """
        API_URL=https://example.com
        DEBUG=true
        EMPTY=
        """

        XCTAssertEqual(detect(environment), "env")
    }

    func testDoesNotForceAmbiguousTextIntoAFormat() {
        XCTAssertNil(detect("今天配置 xxMac"))
        XCTAssertNil(detect("title: hello"))
        XCTAssertNil(detect("answer=42"))
        XCTAssertNil(detect("a normal sentence\nwith two lines"))
        XCTAssertNil(detect(""))
    }

    func testMalformedStrictFormatsAreNotAccepted() {
        XCTAssertNil(detect(#"{"name":}"#))
        XCTAssertNil(detect("<root><item></root>"))
    }

    private func detect(_ text: String) -> String? {
        ClipboardTextFormatDetector.fileExtension(for: text)
    }

    private static let plistXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Name</key>
        <string>xxMac</string>
    </dict>
    </plist>
    """
}
