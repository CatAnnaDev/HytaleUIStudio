import XCTest
@testable import HytaleUICore

final class HytaleUICoreTests: XCTestCase {
    private func roundTrips(_ source: String, file: StaticString = #filePath, line: UInt = #line) {
        let first = Parser.parse(source)
        XCTAssertFalse(first.hasErrors, "unexpected parse errors: \(first.diagnostics)", file: file, line: line)
        let text = Serializer().serialize(first.document)
        let second = Parser.parse(text)
        XCTAssertEqual(first.document, second.document, "round-trip changed the AST", file: file, line: line)
    }

    func testColorForms() {
        roundTrips("@a = #fff; @b = #1b2a3a; @c = #1b2a3a60; @d = #000000(0.82);")
    }

    func testArithmeticExpression() {
        roundTrips("@w = @Base + (@Side * 2) - 5; @h = 100 + (@Shadow * 2);")
    }

    func testBindingAndList() {
        roundTrips("""
        Label { Text: %client.feedback.title; }
        @music = [ (SoundPath: "a.ogg", Volume: -12), (SoundPath: "b.ogg", Volume: -12) ];
        """)
    }

    func testSlotAndComponentInstantiation() {
        roundTrips("""
        $C = "Common.ui";
        $C.@Container {
          #Title { $C.@Title { @Text = "Hi"; } }
          #Content { LayoutMode: Top; Label #Name { FlexWeight: 1; } }
        }
        """)
    }

    func testHexAmbiguousIdentifier() {
        let result = Parser.parse("Group { Button #Add { Background: (Color: #Add); } }")
        XCTAssertFalse(result.hasErrors)
        let button = result.document.statements.first.flatMap { statement -> UIElement? in
            if case .element(let element) = statement { return element.children.first }
            return nil
        }
        XCTAssertEqual(button?.id, "Add")
    }

    func testResolverExpandsComponentAndArithmetic() {
        let commonSource = """
        @ButtonHeight = 44;
        @PrimaryButton = TextButton {
          @Text = "";
          Anchor: (Height: @ButtonHeight, Width: 120);
          Text: @Text;
        };
        """
        let mainSource = """
        $C = "Common.ui";
        Group #Root {
          Anchor: (Width: 300, Height: 200);
          $C.@PrimaryButton #Go { @Text = "Play"; }
        }
        """
        let loader = ModuleLoader { url in
            url.lastPathComponent == "Common.ui" ? commonSource : nil
        }
        let resolver = Resolver(loader: loader)
        let document = Parser.parse(mainSource).document
        let baseURL = URL(fileURLWithPath: "/virtual/Main.ui")
        let roots = resolver.resolveRoots(document: document, baseURL: baseURL)
        XCTAssertEqual(roots.count, 1)
        let root = roots[0]
        let button = root.children.first
        XCTAssertEqual(button?.typeName, "TextButton")
        XCTAssertEqual(button?.componentName, "$C.@PrimaryButton")
        if case .string(let text)? = button?.property("Text") {
            XCTAssertEqual(text, "Play")
        } else {
            XCTFail("expected overridden Text parameter to resolve to Play")
        }
        if case .record(let anchor)? = button?.property("Anchor"), case .number(let height, _)? = anchor.value("Height") {
            XCTAssertEqual(height, 44)
        } else {
            XCTFail("expected Anchor.Height to resolve to 44 via @ButtonHeight")
        }
    }

    private func completion(_ marked: String) -> CompletionResult {
        let cursor = marked.distance(from: marked.startIndex, to: marked.firstIndex(of: "|")!)
        let source = marked.replacingOccurrences(of: "|", with: "")
        return SourceAssist.complete(source: source, cursor: cursor)
    }

    func testCompletionMemberPositionOffersWidgetsAndProperties() {
        let result = completion("Group {\n  |\n}")
        let inserts = result.items.map(\.insertText)
        XCTAssertTrue(inserts.contains("Label"))
        XCTAssertTrue(inserts.contains("Anchor: "))
    }

    func testCompletionEnumValuePosition() {
        let result = completion("Group {\n  LayoutMode: |\n}")
        let inserts = result.items.map(\.insertText)
        XCTAssertTrue(inserts.contains("Top"))
        XCTAssertTrue(inserts.contains("Left"))
        XCTAssertFalse(inserts.contains("Label"))
    }

    func testCompletionBooleanAndReferences() {
        XCTAssertTrue(completion("Group {\n  Visible: |\n}").items.map(\.insertText).contains("true"))
        let refs = completion("@Brand = #fff;\nGroup {\n  Style: @|\n}").items.map(\.insertText)
        XCTAssertTrue(refs.contains("@Brand"))
    }

    func testCompletionInsideAnchorRecord() {
        let inserts = completion("Group {\n  Anchor: (|)\n}").items.map(\.insertText)
        XCTAssertTrue(inserts.contains("Width: "))
        XCTAssertTrue(inserts.contains("Left: "))
        XCTAssertTrue(inserts.contains("Height: "))
    }

    func testCompletionInsideStyleRecordAndConstructors() {
        let fieldInserts = completion("Label {\n  Style: (|)\n}").items.map(\.insertText)
        XCTAssertTrue(fieldInserts.contains("FontSize: "))
        XCTAssertTrue(fieldInserts.contains("TextColor: "))
        let valueInserts = completion("Button {\n  Style: |\n}").items.map(\.insertText)
        XCTAssertTrue(valueInserts.contains { $0.hasSuffix("Style(") })
    }

    func testCompletionPerWidgetProperties() {
        let inserts = completion("Label {\n  |\n}").items.map(\.insertText)
        XCTAssertTrue(inserts.contains("Text: "))
        XCTAssertTrue(inserts.contains("Style: "))
        XCTAssertFalse(inserts.contains("Group"), "Label is not a container: should not offer child widgets")
        let containerInserts = completion("Group {\n  |\n}").items.map(\.insertText)
        XCTAssertTrue(containerInserts.contains("Label"), "Group is a container: should offer child widgets")
        XCTAssertTrue(CorpusCatalog.widgets.count >= 30)
        XCTAssertTrue(CorpusCatalog.propertyKind.count >= 100)
        XCTAssertTrue(CorpusCatalog.recordFields.count >= 100)
    }

    func testRequirementWarningsForMissingParameter() {
        let common = """
        @Btn = TextButton {
          @Anchor = Anchor();
          Anchor: @Anchor;
          Text: @Text;
        };
        """
        let loader = ModuleLoader { $0.lastPathComponent == "Common.ui" ? common : nil }
        let base = URL(fileURLWithPath: "/virtual/Main.ui")

        let missing = Parser.parse("$C = \"Common.ui\";\nGroup { $C.@Btn #A {} }").document
        let warnMissing = Resolver(loader: loader).analyzeRequirements(document: missing, baseURL: base)
        XCTAssertTrue(warnMissing.contains { $0.message.contains("@Text") })

        let provided = Parser.parse("$C = \"Common.ui\";\nGroup { $C.@Btn #A { @Text = \"Hi\"; } }").document
        let warnProvided = Resolver(loader: loader).analyzeRequirements(document: provided, baseURL: base)
        XCTAssertFalse(warnProvided.contains { $0.message.contains("@Text") })
    }

    func testRequirementWarningLabelWithoutText() {
        let document = Parser.parse("Group { Label #Empty {} }").document
        let warnings = Resolver().analyzeRequirements(document: document, baseURL: nil)
        XCTAssertTrue(warnings.contains { $0.message.contains("Label") })
    }

    func testLayoutVerticalStackFlex() {
        let source = """
        Group #Root {
          Anchor: (Width: 200, Height: 300);
          LayoutMode: Top;
          Label #A { Anchor: (Height: 40); }
          Group #B { FlexWeight: 1; }
          Label #C { Anchor: (Height: 60); }
        }
        """
        let document = Parser.parse(source).document
        let roots = Resolver().resolveRoots(document: document, baseURL: nil)
        let laid = LayoutEngine().layout(root: roots[0], in: UIRect(x: 0, y: 0, width: 200, height: 300))
        XCTAssertEqual(laid.children.count, 3)
        XCTAssertEqual(laid.children[0].frame.height, 40, accuracy: 0.5)
        XCTAssertEqual(laid.children[1].frame.height, 200, accuracy: 0.5)
        XCTAssertEqual(laid.children[2].frame.height, 60, accuracy: 0.5)
        XCTAssertEqual(laid.children[2].frame.minY, 240, accuracy: 0.5)
    }
}
