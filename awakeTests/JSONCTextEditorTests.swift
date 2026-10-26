import XCTest
@testable import awake

final class JSONCTextEditorTests: XCTestCase {
    func testReplacingKeepsCommentsAndFormatting() throws {
        let text = """
        {
          // Theme chosen by hand.
          "theme": "dark", /* keep */
          "plugin": ["other"],
        }
        """
        let edited = try XCTUnwrap(JSONCTextEditor.applying(
            [("plugin", ["other", "file:///Users/me/awake/"])], to: text
        ))
        XCTAssertEqual(edited, """
        {
          // Theme chosen by hand.
          "theme": "dark", /* keep */
          "plugin": ["other","file:///Users/me/awake/"],
        }
        """)
    }

    func testInsertingIntoObjectWithComments() throws {
        let text = "{\n  // note\n  \"theme\": \"dark\"\n}\n"
        let edited = try XCTUnwrap(JSONCTextEditor.applying([("plugin", ["a"])], to: text))
        XCTAssertEqual(edited, "{\n  \"plugin\": [\"a\"],\n  // note\n  \"theme\": \"dark\"\n}\n")

        let empty = try XCTUnwrap(JSONCTextEditor.applying([("plugin", ["a"])], to: "{}"))
        XCTAssertEqual(empty, "{\n  \"plugin\": [\"a\"]}")
    }

    func testRemovingMembers() throws {
        let text = "{\n  \"a\": 1, // first\n  \"plugin\": [\"x\"]\n}"
        XCTAssertEqual(
            JSONCTextEditor.applying([("plugin", nil)], to: text),
            "{\n  \"a\": 1\n}"
        )
        XCTAssertEqual(
            JSONCTextEditor.applying([("a", nil)], to: text),
            "{\n   // first\n  \"plugin\": [\"x\"]\n}"
        )
        XCTAssertEqual(JSONCTextEditor.applying([("missing", nil)], to: text), text)
    }

    func testNestedKeysAndStringsAreNotMatched() throws {
        let text = "{\"nested\": {\"plugin\": [1]}, \"s\": \"{\\\"plugin\\\": //\"}"
        let edited = try XCTUnwrap(JSONCTextEditor.applying([("plugin", [2])], to: text))
        XCTAssertEqual(edited, "{\n  \"plugin\": [2],\"nested\": {\"plugin\": [1]}, \"s\": \"{\\\"plugin\\\": //\"}")
    }

    func testRejectsNonObjects() {
        XCTAssertNil(JSONCTextEditor.applying([("plugin", ["a"])], to: "[1, 2]"))
        XCTAssertNil(JSONCTextEditor.applying([("plugin", ["a"])], to: "{\"a\": "))
    }
}
