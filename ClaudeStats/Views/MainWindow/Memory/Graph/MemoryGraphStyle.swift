import SwiftUI

enum MemoryGraphStyle {
    static func color(for kind: String) -> Color {
        switch kind {
        case "project":
            Color.stxAccent
        case "module", "scope":
            Color(red: 0.22, green: 0.58, blue: 0.9)
        case "memory":
            Color(red: 0.42, green: 0.72, blue: 0.35)
        case "event":
            Color(red: 0.9, green: 0.56, blue: 0.22)
        case "change_event":
            Color(red: 0.95, green: 0.38, blue: 0.28)
        case "source", "episode":
            Color(red: 0.76, green: 0.48, blue: 0.86)
        case "group":
            Color(red: 0.36, green: 0.54, blue: 0.9)
        default:
            isGraphitiKind(kind) ? Color(red: 0.94, green: 0.37, blue: 0.46) : Color.stxMuted
        }
    }

    static func eventColor(for eventType: String) -> Color {
        let lower = eventType.lowercased()
        if lower.contains("source") || lower.contains("observed") {
            return Color(red: 0.76, green: 0.48, blue: 0.86)
        }
        if lower.contains("created") || lower.contains("accepted") {
            return Color(red: 0.42, green: 0.72, blue: 0.35)
        }
        if lower.contains("updated") || lower.contains("superseded") {
            return Color(red: 0.22, green: 0.58, blue: 0.9)
        }
        if lower.contains("deprecated") || lower.contains("retracted") || lower.contains("conflict") {
            return Color(red: 0.9, green: 0.26, blue: 0.22)
        }
        if lower.contains("proposed") {
            return Color(red: 0.92, green: 0.58, blue: 0.16)
        }
        return color(for: "change_event")
    }

    static func symbol(for kind: String) -> String {
        switch kind {
        case "project":
            "folder"
        case "module", "scope":
            "shippingbox"
        case "memory":
            "text.badge.checkmark"
        case "event", "change_event":
            "arrow.triangle.2.circlepath"
        case "source":
            "doc.text"
        case "episode":
            "doc.text.magnifyingglass"
        case "group":
            "rectangle.stack"
        default:
            isGraphitiKind(kind) ? "point.3.connected.trianglepath.dotted" : "circle.hexagongrid"
        }
    }

    static func color(for node: MemoryGraphPresentation.Node) -> Color {
        switch node.kind {
        case "event":
            eventColor(for: node.eventType ?? "")
        default:
            color(for: node.kind)
        }
    }

    static func edgeColor(for kind: String) -> Color {
        switch kind {
        case "NEXT_EVENT":
            Color.stxMuted
        case "AFFECTS":
            color(for: "memory")
        case "FROM_SOURCE":
            color(for: "episode")
        case "GROUP_CONTAINS":
            color(for: "group")
        default:
            Color.stxStroke
        }
    }

    static func edgeLabel(for kind: String) -> String {
        switch kind {
        case "NEXT_EVENT":
            "next"
        case "AFFECTS":
            "affects"
        case "FROM_SOURCE":
            "from source"
        case "GROUP_CONTAINS":
            "contains"
        default:
            kind.lowercased()
        }
    }

    static func edgeStrokeStyle(for kind: String, isSelected: Bool) -> StrokeStyle {
        switch kind {
        case "FROM_SOURCE":
            StrokeStyle(lineWidth: isSelected ? 2 : 1.2, lineCap: .round, dash: [5, 4])
        case "NEXT_EVENT":
            StrokeStyle(lineWidth: isSelected ? 1.8 : 0.9, lineCap: .round, dash: [2, 5])
        default:
            StrokeStyle(lineWidth: isSelected ? 2.2 : 1.2, lineCap: .round)
        }
    }

    static func isGraphitiKind(_ kind: String) -> Bool {
        let lower = kind.lowercased()
        return lower.contains("graphiti") || lower == "entity" || lower == "relationship"
    }
}
