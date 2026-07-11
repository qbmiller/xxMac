import Foundation

final class SpotlightApplicationFinder {
    enum FinderError: Error {
        case queryDidNotStart
        case timedOut
    }

    private struct ActiveQuery {
        let query: NSMetadataQuery
        let observer: NSObjectProtocol
        let timeout: DispatchWorkItem
    }

    private var activeQueries: [ObjectIdentifier: ActiveQuery] = [:]

    func findApplicationPaths(
        in searchPaths: [String],
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        let roots = searchPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        guard !roots.isEmpty else {
            completion(.success([]))
            return
        }

        DispatchQueue.main.async {
            let query = NSMetadataQuery()
            query.predicate = NSPredicate(
                format: "%K == %@",
                NSMetadataItemContentTypeTreeKey,
                "com.apple.application-bundle"
            )
            query.searchScopes = roots

            let identifier = ObjectIdentifier(query)
            let observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: query,
                queue: .main
            ) { [weak self, weak query] _ in
                guard let self, let query else { return }
                let paths = (query.results as? [NSMetadataItem] ?? []).compactMap {
                    $0.value(forAttribute: NSMetadataItemPathKey) as? String
                }
                self.finish(
                    identifier: identifier,
                    result: .success(Self.filteredApplicationPaths(paths, within: roots)),
                    completion: completion
                )
            }

            let timeout = DispatchWorkItem { [weak self] in
                self?.finish(identifier: identifier, result: .failure(FinderError.timedOut), completion: completion)
            }
            self.activeQueries[identifier] = ActiveQuery(query: query, observer: observer, timeout: timeout)

            guard query.start() else {
                self.finish(identifier: identifier, result: .failure(FinderError.queryDidNotStart), completion: completion)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
        }
    }

    static func filteredApplicationPaths(_ paths: [String], within searchPaths: [String]) -> [String] {
        let roots = searchPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        return Set(paths.compactMap { path -> String? in
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            guard normalizedPath.hasSuffix(".app"),
                  roots.contains(where: { isPath(normalizedPath, inside: $0) }),
                  !containsNestedApplication(normalizedPath, relativeTo: roots) else {
                return nil
            }
            return normalizedPath
        }).sorted()
    }

    private static func isPath(_ path: String, inside root: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
    }

    private static func containsNestedApplication(_ path: String, relativeTo roots: [String]) -> Bool {
        guard let root = roots.filter({ isPath(path, inside: $0) }).max(by: { $0.count < $1.count }) else {
            return true
        }
        let relativePath = String(path.dropFirst(root.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relativePath.split(separator: "/").dropLast().contains { $0.lowercased().hasSuffix(".app") }
    }

    private func finish(
        identifier: ObjectIdentifier,
        result: Result<[String], Error>,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        guard let activeQuery = activeQueries.removeValue(forKey: identifier) else { return }
        activeQuery.timeout.cancel()
        activeQuery.query.stop()
        NotificationCenter.default.removeObserver(activeQuery.observer)
        completion(result)
    }
}
