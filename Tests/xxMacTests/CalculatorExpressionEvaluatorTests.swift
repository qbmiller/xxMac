import XCTest
@testable import xxMac

final class CalculatorExpressionEvaluatorTests: XCTestCase {
    func testAddsTwoNumbers() {
        XCTAssertEqual(CalculatorExpressionEvaluator.evaluate("4+8")?.value, "12")
    }

    func testRespectsParenthesesAndPrecedence() {
        XCTAssertEqual(CalculatorExpressionEvaluator.evaluate("(4+8)*2")?.value, "24")
        XCTAssertEqual(CalculatorExpressionEvaluator.evaluate("2+3*4")?.value, "14")
    }

    func testSupportsNegativeNumbersAndDecimals() {
        XCTAssertEqual(CalculatorExpressionEvaluator.evaluate("-3.5/2")?.value, "-1.75")
        XCTAssertEqual(CalculatorExpressionEvaluator.evaluate("4--2")?.value, "6")
    }

    func testSupportsFullWidthParenthesesAndCommonOperatorSymbols() {
        XCTAssertEqual(CalculatorExpressionEvaluator.evaluate("（4＋8）")?.value, "12")
        XCTAssertEqual(CalculatorExpressionEvaluator.evaluate("（4+8）×2")?.value, "24")
        XCTAssertEqual(CalculatorExpressionEvaluator.evaluate("8÷4")?.value, "2")
    }

    func testIgnoresPlainSearchTermsAndPlainNumbers() {
        XCTAssertNil(CalculatorExpressionEvaluator.evaluate("Safari"))
        XCTAssertNil(CalculatorExpressionEvaluator.evaluate("123"))
        XCTAssertNil(CalculatorExpressionEvaluator.evaluate("1Password"))
    }

    func testRejectsIncompleteOrInvalidExpressions() {
        XCTAssertNil(CalculatorExpressionEvaluator.evaluate("4+"))
        XCTAssertNil(CalculatorExpressionEvaluator.evaluate("(4+8"))
        XCTAssertNil(CalculatorExpressionEvaluator.evaluate("1/0"))
    }
}
