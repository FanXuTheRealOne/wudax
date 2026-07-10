import Foundation

enum GPXParseError: LocalizedError {
    case invalidXML(String)
    case noTrackPoints

    var errorDescription: String? {
        switch self {
        case .invalidXML(let detail): "GPX 文件无法解析：\(detail)"
        case .noTrackPoints: "GPX 文件中没有有效轨迹点"
        }
    }
}

struct GPXParser {
    func parse(data: Data) throws -> GPXDocument {
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw GPXParseError.invalidXML(parser.parserError?.localizedDescription ?? "未知格式错误")
        }
        guard !delegate.segments.flatMap(\.points).isEmpty else {
            throw GPXParseError.noTrackPoints
        }

        let containsRecordedFields = delegate.segments
            .flatMap(\.points)
            .contains { $0.time != nil || $0.speedMetersPerSecond != nil }
        return GPXDocument(
            name: delegate.trackName ?? delegate.metadataName ?? "未命名路线",
            creator: delegate.creator,
            segments: delegate.segments,
            waypoints: delegate.waypoints,
            purpose: containsRecordedFields ? .recordedActivity : .plannedRoute
        )
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    var creator: String?
    var metadataName: String?
    var trackName: String?
    var segments: [GPXTrackSegment] = []
    var waypoints: [GPXWaypoint] = []

    private var path: [String] = []
    private var text = ""
    private var currentPoints: [GPXTrackPoint]?
    private var currentPoint: GPXTrackPoint?
    private var currentWaypoint: GPXWaypoint?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let element = localName(qName ?? elementName)
        path.append(element)
        text = ""

        switch element {
        case "gpx": creator = attributeDict["creator"]
        case "trkseg": currentPoints = []
        case "trkpt":
            if let latitude = Double(attributeDict["lat"] ?? ""),
               let longitude = Double(attributeDict["lon"] ?? "") {
                currentPoint = GPXTrackPoint(
                    latitude: latitude,
                    longitude: longitude,
                    elevationMeters: nil,
                    time: nil,
                    speedMetersPerSecond: nil
                )
            }
        case "wpt":
            if let latitude = Double(attributeDict["lat"] ?? ""),
               let longitude = Double(attributeDict["lon"] ?? "") {
                currentWaypoint = GPXWaypoint(
                    latitude: latitude,
                    longitude: longitude,
                    elevationMeters: nil,
                    name: nil
                )
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let element = localName(qName ?? elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch element {
        case "ele":
            if let elevation = Double(value) {
                if currentPoint != nil { currentPoint?.elevationMeters = elevation }
                else if currentWaypoint != nil { currentWaypoint?.elevationMeters = elevation }
            }
        case "time":
            if currentPoint != nil { currentPoint?.time = Self.parseDate(value) }
        case "speed":
            if currentPoint != nil { currentPoint?.speedMetersPerSecond = Double(value) }
        case "name":
            if currentWaypoint != nil {
                currentWaypoint?.name = value.nilIfEmpty
            } else if path.contains("trk") {
                trackName = value.nilIfEmpty
            } else if path.contains("metadata") {
                metadataName = value.nilIfEmpty
            }
        case "trkpt":
            if let currentPoint { currentPoints?.append(currentPoint) }
            currentPoint = nil
        case "trkseg":
            if let currentPoints, !currentPoints.isEmpty {
                segments.append(GPXTrackSegment(points: currentPoints))
            }
            currentPoints = nil
        case "wpt":
            if let currentWaypoint { waypoints.append(currentWaypoint) }
            currentWaypoint = nil
        default: break
        }

        if !path.isEmpty { path.removeLast() }
        text = ""
    }

    private func localName(_ name: String) -> String {
        String(name.split(separator: ":").last ?? Substring(name)).lowercased()
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

