import AppKit
import Foundation
import UniformTypeIdentifiers

extension UTType {
    fileprivate static let teleportGPX = UTType(filenameExtension: "gpx") ?? .xml
}

extension AppViewModel {
    func saveCurrentRouteToApp() {
        guard let loadedRoute else {
            return
        }

        upsertSavedRoute(loadedRoute)
        persistSavedRoutes()
        statusMessage = .localized(TeleportStrings.savedRouteInApp(loadedRoute.name))
    }

    func updateCurrentSavedRouteInApp() {
        guard let loadedRoute, let existingIndex = loadedSavedRouteIndex else {
            return
        }

        savedRoutes[existingIndex] = loadedRoute
        persistSavedRoutes()
        statusMessage = .localized(TeleportStrings.updatedSavedRouteInApp(loadedRoute.name))
    }

    func saveCurrentRouteToAppAsNew() {
        guard let loadedRoute else {
            return
        }

        let defaultName = suggestedDuplicateRouteName(for: loadedRoute.name)
        guard
            let routeName = promptForRouteName(
                title: TeleportStrings.saveRoutePromptTitle,
                message: TeleportStrings.saveRoutePromptMessage,
                defaultName: defaultName,
                actionTitle: TeleportStrings.routeSaveAsNew
            )
        else {
            return
        }

        let savedRoute = SimulatedRoute(
            name: routeName,
            source: loadedRoute.source,
            waypoints: loadedRoute.waypoints
        )

        self.loadedRoute = savedRoute
        upsertSavedRoute(savedRoute)
        persistSavedRoutes()
        statusMessage = .localized(TeleportStrings.savedRouteAsNewCopy(savedRoute.name))
    }

    func loadSavedRoute(_ route: SimulatedRoute) {
        stopRoutePlayback(resetToReadyState: false)
        isRouteBuilderActive = false
        draftRouteWaypoints = []
        loadedRoute = route
        routePlaybackState = .ready

        if let startCoordinate = loadedRouteStartDisplayCoordinate {
            suppressPickedLocationPin = false
            latitudeText = String(format: "%.6f", startCoordinate.latitude)
            longitudeText = String(format: "%.6f", startCoordinate.longitude)
        }

        statusMessage = .localized(TeleportStrings.loadedSavedRoute(route.name))
    }

    func deleteSavedRoute(_ route: SimulatedRoute) {
        savedRoutes.removeAll { $0.id == route.id }
        persistSavedRoutes()
        statusMessage = .localized(TeleportStrings.deletedSavedRoute(route.name))
    }

    func renameSavedRoute(_ route: SimulatedRoute) {
        guard
            let routeName = promptForRouteName(
                title: TeleportStrings.renameRoutePromptTitle,
                message: TeleportStrings.renameRoutePromptMessage,
                defaultName: route.name,
                actionTitle: TeleportStrings.savedRouteRename
            )
        else {
            return
        }

        guard let existingIndex = savedRoutes.firstIndex(where: { $0.id == route.id }) else {
            return
        }

        savedRoutes[existingIndex].name = routeName

        if loadedRoute?.id == route.id {
            loadedRoute?.name = routeName
        }

        persistSavedRoutes()
        statusMessage = .localized(TeleportStrings.renamedSavedRoute(routeName))
    }

    func exportCurrentRouteAsGPX() {
        guard let loadedRoute, currentRouteCanBeExportedAsGPX else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.teleportGPX]
        panel.nameFieldStringValue = suggestedGPXFileName(for: loadedRoute)
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data = GPXRouteExporter().export(route: loadedRoute)
            try data.write(to: url, options: .atomic)
            statusMessage = .localized(TeleportStrings.exportedRouteAsGPX(loadedRoute.name))
        } catch {
            let message = UserFacingText.localized(
                TeleportStrings.failedToExportGPX(error.localizedDescription)
            )
            statusMessage = message
        }
    }

    private func suggestedGPXFileName(for route: SimulatedRoute) -> String {
        let trimmedName = route.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.isEmpty ? "route" : trimmedName
        let sanitized = baseName.replacingOccurrences(of: "/", with: "-")
        return sanitized + ".gpx"
    }

    private func suggestedDuplicateRouteName(for name: String) -> String {
        let trimmedName = normalizedRouteName(from: name, fallback: "Route")
        return trimmedName + " Copy"
    }

    private func promptForRouteName(
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        defaultName: String,
        actionTitle: LocalizedStringResource
    ) -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: title)
        alert.informativeText = String(localized: message)

        let textField = NSTextField(string: defaultName)
        textField.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = textField
        alert.addButton(withTitle: String(localized: actionTitle))
        alert.addButton(withTitle: String(localized: TeleportStrings.cancel))

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return nil
        }

        return normalizedRouteName(from: textField.stringValue, fallback: defaultName)
    }

    private func normalizedRouteName(from value: String, fallback: String) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedValue.isEmpty {
            return trimmedValue
        }

        let trimmedFallback = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedFallback.isEmpty ? "Route" : trimmedFallback
    }

    private func upsertSavedRoute(_ route: SimulatedRoute) {
        if let existingIndex = savedRoutes.firstIndex(where: { $0.id == route.id }) {
            savedRoutes[existingIndex] = route
        } else {
            savedRoutes.insert(route, at: 0)
        }
    }
}
