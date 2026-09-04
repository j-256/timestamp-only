import AppKit
import Foundation

enum FolderAccessError: Error, LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "macOS did not grant access to the selected folder. Choose the folder again."
        }
    }
}

struct RestoredFolderAccess {
    let url: URL
    let refreshedBookmark: Data?
}

final class FolderAccessController {
    private(set) var url: URL?
    private var isAccessing = false

    deinit {
        stop()
    }

    func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Screenshot Folder"
        panel.message =
            "Choose the folder selected in the macOS Screenshot toolbar under Options. Most Macs use Desktop."
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.resolvesAliases = true
        panel.directoryURL =
            url
            ?? FileManager.default.urls(
                for: .desktopDirectory,
                in: .userDomainMask
            ).first

        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }

    func activateSelectedFolder(_ selectedURL: URL) throws -> RestoredFolderAccess {
        let bookmark = try selectedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let restored = try activate(bookmark: bookmark)
        return RestoredFolderAccess(
            url: restored.url,
            refreshedBookmark: bookmark
        )
    }

    func restore(bookmark: Data) throws -> RestoredFolderAccess {
        try activate(bookmark: bookmark)
    }

    func stop() {
        if isAccessing, let url {
            url.stopAccessingSecurityScopedResource()
        }
        isAccessing = false
        url = nil
    }

    private func activate(bookmark: Data) throws -> RestoredFolderAccess {
        var isStale = false
        let restoredURL = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        let didStartAccess = restoredURL.startAccessingSecurityScopedResource()
        guard didStartAccess else {
            throw FolderAccessError.accessDenied
        }

        stop()
        url = restoredURL
        isAccessing = true

        do {
            let refreshedBookmark: Data?
            if isStale {
                refreshedBookmark = try restoredURL.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
            } else {
                refreshedBookmark = nil
            }

            return RestoredFolderAccess(
                url: restoredURL,
                refreshedBookmark: refreshedBookmark
            )
        } catch {
            stop()
            throw error
        }
    }
}
