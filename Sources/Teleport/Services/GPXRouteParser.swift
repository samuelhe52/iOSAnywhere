import Foundation

struct GPXRouteParser {
    func parse(data: Data, fallbackName: String) throws -> SimulatedRoute {
        let delegate = GPXDocumentParser(fallbackName: fallbackName)
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw delegate.error ?? parser.parserError ?? GPXRouteParserError.invalidDocument
        }

        return try delegate.makeRoute()
    }
}

enum GPXRouteParserError: LocalizedError {
    case invalidDocument
    case noUsablePoints

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "The GPX file could not be parsed."
        case .noUsablePoints:
            return "The GPX file does not contain enough route points to preview."
        }
    }
}

private final class GPXDocumentParser: NSObject, XMLParserDelegate {
    struct RouteCandidate {
        var name: String?
        var points: [ParsedPoint]
    }

    struct ParsedPoint {
        var coordinate: LocationCoordinate
        var timestamp: Date?
    }

    enum PointKind {
        case track
        case route
        case waypoint
    }

    private let fallbackName: String
    private let dateFormatter = ISO8601DateFormatter()
    private let fractionalDateFormatter = ISO8601DateFormatter()

    private var elementStack: [String] = []
    private var currentText = ""
    private var currentPointKind: PointKind?
    private var currentPoint: ParsedPoint?

    private var metadataName: String?
    private var currentTrackName: String?
    private var currentRouteName: String?
    private var currentTrackPoints: [ParsedPoint] = []
    private var currentRoutePoints: [ParsedPoint] = []

    private var trackCandidates: [RouteCandidate] = []
    private var routeCandidates: [RouteCandidate] = []
    private var waypointPoints: [ParsedPoint] = []

    var error: Error?

    init(fallbackName: String) {
        self.fallbackName = fallbackName
        super.init()
        dateFormatter.formatOptions = [.withInternetDateTime]
        fractionalDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func makeRoute() throws -> SimulatedRoute {
        let selectedCandidate: RouteCandidate?

        if let trackCandidate = trackCandidates.first(where: { $0.points.count > 1 }) {
            selectedCandidate = trackCandidate
        } else if let routeCandidate = routeCandidates.first(where: { $0.points.count > 1 }) {
            selectedCandidate = routeCandidate
        } else if waypointPoints.count > 1 {
            selectedCandidate = RouteCandidate(name: nil, points: waypointPoints)
        } else {
            throw GPXRouteParserError.noUsablePoints
        }

        let routeName = selectedCandidate?.name ?? preferredName
        let waypoints = (selectedCandidate?.points ?? []).map {
            RouteWaypoint(coordinate: $0.coordinate, timestamp: $0.timestamp)
        }

        return SimulatedRoute(name: routeName, source: .gpx, waypoints: waypoints)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementStack.append(elementName)
        currentText = ""

        switch elementName {
        case "trk":
            currentTrackName = nil
            currentTrackPoints = []
        case "rte":
            currentRouteName = nil
            currentRoutePoints = []
        case "trkpt":
            currentPointKind = .track
            currentPoint = parsedPoint(from: attributeDict)
        case "rtept":
            currentPointKind = .route
            currentPoint = parsedPoint(from: attributeDict)
        case "wpt":
            currentPointKind = .waypoint
            currentPoint = parsedPoint(from: attributeDict)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parentElement = elementStack.dropLast().last

        if elementName == "name", !trimmedText.isEmpty {
            switch parentElement {
            case "trk" where currentTrackName == nil:
                currentTrackName = trimmedText
            case "rte" where currentRouteName == nil:
                currentRouteName = trimmedText
            case "metadata" where metadataName == nil:
                metadataName = trimmedText
            default:
                break
            }
        }

        if elementName == "time", let timestamp = parseTimestamp(trimmedText) {
            currentPoint?.timestamp = timestamp
        }

        switch elementName {
        case "trk":
            if currentTrackPoints.count > 1 {
                trackCandidates.append(RouteCandidate(name: currentTrackName, points: currentTrackPoints))
            }
            currentTrackName = nil
            currentTrackPoints = []
        case "rte":
            if currentRoutePoints.count > 1 {
                routeCandidates.append(RouteCandidate(name: currentRouteName, points: currentRoutePoints))
            }
            currentRouteName = nil
            currentRoutePoints = []
        case "trkpt":
            if let currentPoint {
                currentTrackPoints.append(currentPoint)
            }
            currentPoint = nil
            currentPointKind = nil
        case "rtept":
            if let currentPoint {
                currentRoutePoints.append(currentPoint)
            }
            currentPoint = nil
            currentPointKind = nil
        case "wpt":
            if let currentPoint {
                waypointPoints.append(currentPoint)
            }
            currentPoint = nil
            currentPointKind = nil
        default:
            break
        }

        currentText = ""
        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = parseError
    }

    private var preferredName: String {
        trackCandidates.first?.name
            ?? routeCandidates.first?.name
            ?? metadataName
            ?? fallbackName
    }

    private func parsedPoint(from attributes: [String: String]) -> ParsedPoint? {
        guard
            let latitudeText = attributes["lat"],
            let longitudeText = attributes["lon"],
            let latitude = Double(latitudeText),
            let longitude = Double(longitudeText)
        else {
            return nil
        }

        return ParsedPoint(coordinate: LocationCoordinate(latitude: latitude, longitude: longitude))
    }

    private func parseTimestamp(_ value: String) -> Date? {
        guard !value.isEmpty else {
            return nil
        }

        return fractionalDateFormatter.date(from: value) ?? dateFormatter.date(from: value)
    }
}