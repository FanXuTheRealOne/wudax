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

        let points = delegate.segments.flatMap(\.points)
        guard !points.isEmpty else { throw GPXParseError.noTrackPoints }

        let containsRecordedFields = points.contains {
            $0.time != nil || $0.speedMetersPerSecond != nil ||
            $0.heartRateBPM != nil || $0.cadenceRPM != nil
        }

        return GPXDocument(
            name: delegate.trackName ?? delegate.routeName ?? delegate.metadataName ?? "未命名路线",
            creator: delegate.creator,
            segments: delegate.segments,
            waypoints: delegate.waypoints,
            purpose: containsRecordedFields ? .recordedActivity : .plannedRoute,
            ignoredPointCount: delegate.ignoredPointCount,
            ignoredWaypointCount: delegate.ignoredWaypointCount
        )
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    var creator: String?
    var metadataName: String?
    var trackName: String?
    var routeName: String?
    var segments: [GPXTrackSegment] = []
    var waypoints: [GPXWaypoint] = []
    var ignoredPointCount = 0
    var ignoredWaypointCount = 0

    private var path: [String] = []
    private var text = ""
    private var currentPoint: GPXTrackPoint?
    private var currentWaypoint: GPXWaypoint?
    private var activeTrackSegment: [GPXTrackPoint]?
    private var activeRoutePoints: [GPXTrackPoint]?
    private var currentPointHasInvalidCoordinate = false
    private var currentWaypointHasInvalidCoordinate = false

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
        case "gpx":
            creator = attributeDict["creator"]?.trimmedNilIfEmpty
        case "trkseg":
            flushActiveTrackSegment()
            activeTrackSegment = []
        case "trkpt":
            if activeTrackSegment == nil { activeTrackSegment = [] }
            currentPoint = makePoint(attributes: attributeDict)
            currentPointHasInvalidCoordinate = currentPoint == nil
        case "rte":
            activeRoutePoints = []
        case "rtept":
            if activeRoutePoints == nil { activeRoutePoints = [] }
            currentPoint = makePoint(attributes: attributeDict)
            currentPointHasInvalidCoordinate = currentPoint == nil
        case "wpt":
            currentWaypoint = makeWaypoint(attributes: attributeDict)
            currentWaypointHasInvalidCoordinate = currentWaypoint == nil
        default:
            break
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
            if let number = Self.parseNumber(value) {
                if currentPoint != nil { currentPoint?.elevationMeters = number }
                else if currentWaypoint != nil { currentWaypoint?.elevationMeters = number }
            }
        case "time":
            if currentPoint != nil { currentPoint?.time = Self.parseDate(value) }
        case "speed":
            if currentPoint != nil { currentPoint?.speedMetersPerSecond = Self.parseNumber(value) }
        case "hr", "heartrate", "heart_rate", "heart-rate":
            if currentPoint != nil { currentPoint?.heartRateBPM = Self.parseNumber(value) }
        case "cad", "cadence":
            if currentPoint != nil { currentPoint?.cadenceRPM = Self.parseNumber(value) }
        case "name":
            assignName(value)
        case "trkpt":
            if let currentPoint { activeTrackSegment?.append(currentPoint) }
            else if currentPointHasInvalidCoordinate { ignoredPointCount += 1 }
            currentPoint = nil
            currentPointHasInvalidCoordinate = false
        case "rtept":
            if let currentPoint { activeRoutePoints?.append(currentPoint) }
            else if currentPointHasInvalidCoordinate { ignoredPointCount += 1 }
            currentPoint = nil
            currentPointHasInvalidCoordinate = false
        case "trkseg":
            flushActiveTrackSegment()
        case "trk":
            // A few exporters omit <trkseg>. Treat the track's direct points
            // as one implicit segment instead of silently dropping them.
            flushActiveTrackSegment()
        case "rte":
            if let activeRoutePoints, !activeRoutePoints.isEmpty {
                segments.append(GPXTrackSegment(points: activeRoutePoints))
            }
            activeRoutePoints = nil
        case "wpt":
            if let currentWaypoint { waypoints.append(currentWaypoint) }
            else if currentWaypointHasInvalidCoordinate { ignoredWaypointCount += 1 }
            currentWaypoint = nil
            currentWaypointHasInvalidCoordinate = false
        default:
            break
        }

        if !path.isEmpty { path.removeLast() }
        text = ""
    }

    private func assignName(_ value: String) {
        guard let name = value.trimmedNilIfEmpty else { return }
        if currentWaypoint != nil {
            currentWaypoint?.name = name
        } else if path.contains("trk") {
            trackName = name
        } else if path.contains("rte") {
            routeName = name
        } else if path.contains("metadata") {
            metadataName = name
        }
    }

    private func makePoint(attributes: [String: String]) -> GPXTrackPoint? {
        guard let latitude = Self.parseNumber(attributes["lat"]),
              let longitude = Self.parseNumber(attributes["lon"]),
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            return nil
        }
        return GPXTrackPoint(
            latitude: latitude,
            longitude: longitude,
            elevationMeters: nil,
            time: nil,
            speedMetersPerSecond: nil,
            heartRateBPM: nil,
            cadenceRPM: nil
        )
    }

    private func makeWaypoint(attributes: [String: String]) -> GPXWaypoint? {
        guard let latitude = Self.parseNumber(attributes["lat"]),
              let longitude = Self.parseNumber(attributes["lon"]),
              latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            return nil
        }
        return GPXWaypoint(latitude: latitude, longitude: longitude, elevationMeters: nil, name: nil)
    }

    private func flushActiveTrackSegment() {
        guard let activeTrackSegment, !activeTrackSegment.isEmpty else {
            activeTrackSegment = nil
            return
        }
        segments.append(GPXTrackSegment(points: activeTrackSegment))
        self.activeTrackSegment = nil
    }

    private func localName(_ name: String) -> String {
        String(name.split(separator: ":").last ?? Substring(name)).lowercased()
    }

    private static func parseNumber(_ value: String?) -> Double? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let number = Double(trimmed), number.isFinite { return number }
        let commaDecimal = trimmed.replacingOccurrences(of: ",", with: ".")
        guard let number = Double(commaDecimal), number.isFinite else { return nil }
        return number
    }

    private static func parseDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
