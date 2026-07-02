import Foundation

public enum PropertyKind: Sendable, Equatable {
    case color
    case number
    case string
    case boolean
    case enumeration(String)
    case anchor
    case padding
    case style(String)
    case reference
    case binding
    case texturePath
    case record
    case list
    case unknown
}

public struct WidgetDefinition: Sendable {
    public var name: String
    public var category: String
    public var isContainer: Bool
    public var summary: String
    public var defaultSize: UISize
    public var defaultMembers: [UIMember]

    public init(name: String, category: String, isContainer: Bool, summary: String, defaultSize: UISize, defaultMembers: [UIMember] = []) {
        self.name = name
        self.category = category
        self.isContainer = isContainer
        self.summary = summary
        self.defaultSize = defaultSize
        self.defaultMembers = defaultMembers
    }
}

public enum SemanticCatalog {
    public static let enumValues: [String: [String]] = [
        "LayoutMode": ["None", "Top", "Left", "Right", "Middle", "Center", "Full", "CenterMiddle", "MiddleCenter", "TopScrolling", "BottomScrolling", "LeftScrolling", "LeftCenterWrap"],
        "HorizontalAlignment": ["Start", "Center", "End"],
        "VerticalAlignment": ["Start", "Center", "End"],
        "Alignment": ["Center", "Horizontal", "Vertical", "Right", "TopLeft"],
        "Direction": ["Start", "End"],
        "PanelAlign": ["Bottom", "Right", "Left", "Top"],
        "Side": ["Left", "Right", "Top", "Bottom"],
        "MouseWheelScrollBehaviour": ["HorizontalOnly", "VerticalOnly"],
        "ResizeAt": ["Start", "End"],
        "InfoDisplay": ["None"]
    ]

    public static let propertyKinds: [String: PropertyKind] = [
        "Anchor": .anchor,
        "Padding": .padding,
        "Background": .record,
        "Style": .record,
        "LayoutMode": .enumeration("LayoutMode"),
        "HorizontalAlignment": .enumeration("HorizontalAlignment"),
        "VerticalAlignment": .enumeration("VerticalAlignment"),
        "Alignment": .enumeration("Alignment"),
        "Direction": .enumeration("Direction"),
        "PanelAlign": .enumeration("PanelAlign"),
        "Side": .enumeration("Side"),
        "Text": .string,
        "TooltipText": .string,
        "PlaceholderText": .string,
        "PanelTitleText": .string,
        "NoItemsText": .string,
        "Format": .string,
        "PasswordChar": .string,
        "FontName": .string,
        "TexturePath": .texturePath,
        "BarTexturePath": .texturePath,
        "MaskTexturePath": .texturePath,
        "LabelMaskTexturePath": .texturePath,
        "IconTexturePath": .texturePath,
        "EffectTexturePath": .texturePath,
        "FallbackTexturePath": .texturePath,
        "ContentMaskTexturePath": .texturePath,
        "DefaultArrowTexturePath": .texturePath,
        "HoveredArrowTexturePath": .texturePath,
        "PressedArrowTexturePath": .texturePath,
        "TextColor": .color,
        "Color": .color,
        "OutlineColor": .color,
        "FocusOutlineColor": .color,
        "HoveredIconColor": .color,
        "DurabilityBarColorStart": .color,
        "DurabilityBarColorEnd": .color,
        "FontSize": .number,
        "Width": .number,
        "Height": .number,
        "MinWidth": .number,
        "MaxWidth": .number,
        "Top": .number,
        "Left": .number,
        "Right": .number,
        "Bottom": .number,
        "Horizontal": .number,
        "Vertical": .number,
        "Full": .number,
        "FlexWeight": .number,
        "Border": .number,
        "HorizontalBorder": .number,
        "VerticalBorder": .number,
        "Volume": .number,
        "LetterSpacing": .number,
        "Spacing": .number,
        "Size": .number,
        "Min": .number,
        "Max": .number,
        "Step": .number,
        "MinValue": .number,
        "MaxValue": .number,
        "MaxLength": .number,
        "Opacity": .number,
        "IconOpacity": .number,
        "Visible": .boolean,
        "Wrap": .boolean,
        "RenderBold": .boolean,
        "RenderItalics": .boolean,
        "RenderUppercase": .boolean,
        "ShrinkTextToFit": .boolean,
        "HitTestVisible": .boolean,
        "AutoFocus": .boolean,
        "IsReadOnly": .boolean,
        "AutoScrollDown": .boolean,
        "ShowScrollbar": .boolean,
        "ShowLabel": .boolean,
        "ShowSearchInput": .boolean,
        "Value": .boolean,
        "ScrollbarStyle": .reference,
        "LabelStyle": .style("LabelStyle"),
        "PlaceholderStyle": .style("InputFieldStyle"),
        "NumberFieldStyle": .style("NumberFieldStyle"),
        "SliderStyle": .style("SliderStyle"),
        "TextTooltipStyle": .style("TextTooltipStyle"),
        "ItemGridStyle": .style("ItemGridStyle")
    ]

    public static func kind(for property: String) -> PropertyKind {
        if let curated = propertyKinds[property] { return curated }
        if let values = CorpusCatalog.enumValues[property], !values.isEmpty { return .enumeration(property) }
        if let mined = CorpusCatalog.propertyKind[property] { return kind(fromMined: mined) }
        return .unknown
    }

    private static func kind(fromMined mined: String) -> PropertyKind {
        switch mined {
        case "color": return .color
        case "number": return .number
        case "bool": return .boolean
        case "string": return .string
        case "reference": return .reference
        case "binding": return .binding
        case "list": return .list
        case "record", "constructor", "expr": return .record
        default: return .unknown
        }
    }

    public static func enumOptions(_ name: String) -> [String] {
        var seen: [String] = []
        for value in (enumValues[name] ?? []) + (CorpusCatalog.enumValues[name] ?? []) where !seen.contains(value) {
            seen.append(value)
        }
        return seen
    }

    public static let widgets: [WidgetDefinition] = [
        WidgetDefinition(name: "Group", category: "Layout", isContainer: true, summary: "Generic container / panel", defaultSize: UISize(width: 200, height: 120), defaultMembers: [
            .property(UIProperty(name: "LayoutMode", value: .identifier("Top"))),
            .property(UIProperty(name: "Anchor", value: .record(UIRecord(entries: [
                UIRecordEntry(kind: .field(name: "Width"), value: .number(200, isInteger: true)),
                UIRecordEntry(kind: .field(name: "Height"), value: .number(120, isInteger: true))
            ]))))
        ]),
        WidgetDefinition(name: "Panel", category: "Layout", isContainer: true, summary: "Panel container", defaultSize: UISize(width: 200, height: 120)),
        WidgetDefinition(name: "Label", category: "Text", isContainer: false, summary: "Text label", defaultSize: UISize(width: 120, height: 20), defaultMembers: [
            .property(UIProperty(name: "Text", value: .string("Label"))),
            .property(UIProperty(name: "Style", value: .record(UIRecord(entries: [
                UIRecordEntry(kind: .field(name: "FontSize"), value: .number(15, isInteger: true)),
                UIRecordEntry(kind: .field(name: "TextColor"), value: .color(UIColor(hex: "ffffff")))
            ]))))
        ]),
        WidgetDefinition(name: "Button", category: "Controls", isContainer: true, summary: "Clickable button", defaultSize: UISize(width: 44, height: 44)),
        WidgetDefinition(name: "TextButton", category: "Controls", isContainer: false, summary: "Button with a text label", defaultSize: UISize(width: 172, height: 44), defaultMembers: [
            .property(UIProperty(name: "Text", value: .string("Button")))
        ]),
        WidgetDefinition(name: "ActionButton", category: "Controls", isContainer: false, summary: "Action button", defaultSize: UISize(width: 172, height: 44)),
        WidgetDefinition(name: "ToggleButton", category: "Controls", isContainer: false, summary: "Toggle button", defaultSize: UISize(width: 44, height: 44)),
        WidgetDefinition(name: "CheckBox", category: "Controls", isContainer: false, summary: "Checkbox", defaultSize: UISize(width: 20, height: 20), defaultMembers: [
            .property(UIProperty(name: "Value", value: .boolean(false)))
        ]),
        WidgetDefinition(name: "LabeledCheckBox", category: "Controls", isContainer: false, summary: "Checkbox with label", defaultSize: UISize(width: 160, height: 20)),
        WidgetDefinition(name: "CheckBoxContainer", category: "Controls", isContainer: true, summary: "Checkbox group", defaultSize: UISize(width: 160, height: 60)),
        WidgetDefinition(name: "TextField", category: "Input", isContainer: false, summary: "Single-line text input", defaultSize: UISize(width: 172, height: 32)),
        WidgetDefinition(name: "CompactTextField", category: "Input", isContainer: false, summary: "Compact text input", defaultSize: UISize(width: 120, height: 24)),
        WidgetDefinition(name: "MultilineTextField", category: "Input", isContainer: false, summary: "Multi-line text input", defaultSize: UISize(width: 240, height: 96)),
        WidgetDefinition(name: "NumberField", category: "Input", isContainer: false, summary: "Numeric input", defaultSize: UISize(width: 90, height: 28)),
        WidgetDefinition(name: "SliderNumberField", category: "Input", isContainer: false, summary: "Slider with number", defaultSize: UISize(width: 200, height: 28)),
        WidgetDefinition(name: "FloatSliderNumberField", category: "Input", isContainer: false, summary: "Float slider with number", defaultSize: UISize(width: 200, height: 28)),
        WidgetDefinition(name: "Slider", category: "Input", isContainer: false, summary: "Slider", defaultSize: UISize(width: 200, height: 16)),
        WidgetDefinition(name: "DropdownBox", category: "Input", isContainer: false, summary: "Dropdown selector", defaultSize: UISize(width: 172, height: 32)),
        WidgetDefinition(name: "DropdownEntry", category: "Input", isContainer: false, summary: "Dropdown entry", defaultSize: UISize(width: 172, height: 31)),
        WidgetDefinition(name: "CodeEditor", category: "Input", isContainer: false, summary: "Code editor", defaultSize: UISize(width: 400, height: 300)),
        WidgetDefinition(name: "ProgressBar", category: "Display", isContainer: false, summary: "Progress bar", defaultSize: UISize(width: 200, height: 12)),
        WidgetDefinition(name: "CircularProgressBar", category: "Display", isContainer: false, summary: "Circular progress", defaultSize: UISize(width: 48, height: 48)),
        WidgetDefinition(name: "Sprite", category: "Display", isContainer: false, summary: "Animated sprite", defaultSize: UISize(width: 32, height: 32)),
        WidgetDefinition(name: "AssetImage", category: "Display", isContainer: false, summary: "Asset image", defaultSize: UISize(width: 64, height: 64)),
        WidgetDefinition(name: "SceneBlur", category: "Display", isContainer: false, summary: "Scene blur overlay", defaultSize: UISize(width: 200, height: 200)),
        WidgetDefinition(name: "ItemGrid", category: "Inventory", isContainer: false, summary: "Item slot grid", defaultSize: UISize(width: 180, height: 180)),
        WidgetDefinition(name: "ItemPreviewComponent", category: "Inventory", isContainer: false, summary: "Item preview", defaultSize: UISize(width: 64, height: 64)),
        WidgetDefinition(name: "PlayerPreviewComponent", category: "Preview", isContainer: false, summary: "Player model preview", defaultSize: UISize(width: 160, height: 240)),
        WidgetDefinition(name: "CharacterPreviewComponent", category: "Preview", isContainer: false, summary: "Character model preview", defaultSize: UISize(width: 160, height: 240)),
        WidgetDefinition(name: "BlockSelector", category: "Inventory", isContainer: false, summary: "Block selector", defaultSize: UISize(width: 200, height: 200)),
        WidgetDefinition(name: "TabNavigation", category: "Navigation", isContainer: true, summary: "Tab bar", defaultSize: UISize(width: 300, height: 40)),
        WidgetDefinition(name: "TabButton", category: "Navigation", isContainer: false, summary: "Tab button", defaultSize: UISize(width: 100, height: 32)),
        WidgetDefinition(name: "MenuItem", category: "Navigation", isContainer: false, summary: "Menu item", defaultSize: UISize(width: 160, height: 25)),
        WidgetDefinition(name: "DynamicPane", category: "Layout", isContainer: true, summary: "Dynamic dockable pane", defaultSize: UISize(width: 240, height: 200)),
        WidgetDefinition(name: "DynamicPaneContainer", category: "Layout", isContainer: true, summary: "Dynamic pane container", defaultSize: UISize(width: 400, height: 300)),
        WidgetDefinition(name: "ReorderableListGrip", category: "Layout", isContainer: false, summary: "Drag handle", defaultSize: UISize(width: 20, height: 20)),
        WidgetDefinition(name: "BackButton", category: "Navigation", isContainer: false, summary: "Back button", defaultSize: UISize(width: 110, height: 27))
    ]

    public static func widget(named name: String) -> WidgetDefinition? {
        widgets.first { $0.name == name }
    }

    public static func definition(for name: String) -> WidgetDefinition {
        if let curated = widget(named: name) { return curated }
        return WidgetDefinition(name: name, category: "Other", isContainer: true, summary: "widget (\(CorpusCatalog.widgetProperties[name]?.count ?? 0) properties)", defaultSize: UISize(width: 120, height: 40))
    }

    public static func allWidgetNames() -> [String] {
        var names = widgets.map(\.name)
        for name in CorpusCatalog.widgets where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    public static func propertyNames(for widget: String) -> [String] {
        if let known = CorpusCatalog.widgetProperties[widget], !known.isEmpty {
            return known
        }
        var all = Set<String>()
        for properties in CorpusCatalog.widgetProperties.values { all.formUnion(properties) }
        return all.sorted()
    }

    public static func isContainer(_ name: String) -> Bool {
        widget(named: name)?.isContainer ?? true
    }

    public static var categories: [String] {
        var seen: [String] = []
        for name in allWidgetNames() {
            let category = definition(for: name).category
            if !seen.contains(category) { seen.append(category) }
        }
        return seen
    }
}
