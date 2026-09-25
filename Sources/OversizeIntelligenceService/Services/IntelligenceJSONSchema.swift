//
// Copyright © 2026 Alexander Romanov
// IntelligenceJSONSchema.swift, created on 25.09.2026
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// A plain JSON Schema for structured output, as OpenAI's strict mode accepts it: objects with
/// `properties`, `required` and `additionalProperties: false`, arrays, enums, strings, numbers
/// and booleans. A nullable property is written as `"type": ["string", "null"]`.
public struct IntelligenceJSONSchema: Sendable, Equatable {
    public let name: String
    public let json: Data

    public init(name: String, json: Data) {
        self.name = name
        self.json = json
    }

    public init(name: String, schema: [String: Any]) throws {
        self.name = name
        json = try JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])
    }
}

#if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    public extension IntelligenceJSONSchema {
        /// Foundation Models decodes a schema only when every object names its property order
        /// (`x-order`) and carries a `title`, which becomes its `$defs` key; both are filled in
        /// here so callers keep writing ordinary JSON Schema.
        func generationSchema() throws -> GenerationSchema {
            let object = try JSONSerialization.jsonObject(with: json)
            let prepared = Self.prepared(object, path: [name])
            let data = try JSONSerialization.data(withJSONObject: prepared)
            return try JSONDecoder().decode(GenerationSchema.self, from: data)
        }

        private static func prepared(_ node: Any, path: [String]) -> Any {
            if let array = node as? [Any] {
                return array.map { prepared($0, path: path) }
            }
            guard var dictionary = node as? [String: Any] else { return node }
            if let types = dictionary["type"] as? [String] {
                dictionary["type"] = types.first { $0 != "null" } ?? "string"
            }
            let nullable = Set(((dictionary["properties"] as? [String: Any]) ?? [:]).compactMap { name, schema in
                ((schema as? [String: Any])?["type"] as? [String])?.contains("null") == true ? name : nil
            })
            for (key, value) in dictionary {
                let childPath = key == "properties" || key == "items" ? path : path + [key]
                if key == "properties", let properties = value as? [String: Any] {
                    var preparedProperties: [String: Any] = [:]
                    for (propertyName, propertySchema) in properties {
                        preparedProperties[propertyName] = prepared(propertySchema, path: path + [propertyName])
                    }
                    dictionary[key] = preparedProperties
                } else {
                    dictionary[key] = prepared(value, path: childPath)
                }
            }
            guard dictionary["type"] as? String == "object" else { return dictionary }
            let properties = (dictionary["properties"] as? [String: Any]) ?? [:]
            if !nullable.isEmpty, let required = dictionary["required"] as? [String] {
                dictionary["required"] = required.filter { !nullable.contains($0) }
            }
            if dictionary["x-order"] == nil {
                let required = (dictionary["required"] as? [String]) ?? []
                let remaining = properties.keys.filter { !required.contains($0) }.sorted()
                dictionary["x-order"] = required + remaining
            }
            if dictionary["title"] == nil {
                dictionary["title"] = path.map(Self.capitalized).joined()
            }
            return dictionary
        }

        private static func capitalized(_ component: String) -> String {
            component.prefix(1).uppercased() + component.dropFirst()
        }
    }
#endif
