import Async
import Dispatch
import HTTP
import Routing
import Service
import Foundation

public final class Request: ParameterContainer {
    /// Underlying HTTP request.
    public var http: HTTPRequest

    /// This request's parent container.
    public let superContainer: Container

    /// This request's private container.
    public let privateContainer: SubContainer

    /// Holds parameters for routing
    public var parameters: Parameters
    
    /// True if this request has active connections
    internal var hasActiveConnections: Bool

    /// Create a new Request
    public init(http: HTTPRequest = .init(), using container: Container) {
        self.http = http
        self.superContainer = container
        self.privateContainer = container.subContainer(on: container)
        self.parameters = []
        hasActiveConnections = false
    }

    /// Called when the request deinitializes
    deinit {
        if hasActiveConnections {
            try! releaseCachedConnections()
        }
    }
}

extension Request: CustomStringConvertible {
    /// See `CustomStringConvertible.description
    public var description: String {
        return http.description
    }
}

extension Request: CustomDebugStringConvertible {
    /// See `CustomDebugStringConvertible.debugDescription`
    public var debugDescription: String {
        return http.debugDescription
    }
}

/// Conform to container by pointing to super container.
extension Request: SubContainer { }

extension Request {
    /// Container for parsing/serializing URI query strings
    public var query: QueryContainer {
        return QueryContainer(query: http.url.query ?? "", container: self)
    }

    /// Container for parsing/serializing content
    public var content: ContentContainer {
        return ContentContainer(container: self, body: http.body, mediaType: http.mediaType) { body, mediaType in
            self.http.body = body
            self.http.mediaType = mediaType
        }
    }
}

extension Request: DatabaseConnectable {
    /// See DatabaseConnectable.connect
    public func connect<D>(to database: DatabaseIdentifier<D>?) -> Future<D.Connection> {
        guard let database = database else {
            let error = VaporError(
                identifier: "defaultDB",
                reason: "Model.defaultDatabase required to use request as worker.",
                suggestedFixes: [
                    "Ensure you are using the 'model' label when registering this model to your migration config (if it is a migration): migrations.add(model: ..., database: ...).",
                    "If the model you are using is not a migration, set the static defaultDatabase property manually in your app's configuration section.",
                    "Use req.withPooledConnection(to: ...) { ... } instead."
                ],
                source: .capture()
            )
            return Future.map(on: self) { throw error }
        }
        hasActiveConnections = true
        return requestCachedConnection(to: database)
    }
}
