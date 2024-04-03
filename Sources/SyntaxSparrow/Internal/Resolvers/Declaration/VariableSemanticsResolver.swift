//
//  FunctionSemanticsResolver.swift
//
//
//  Copyright (c) CheekyGhost Labs 2023. All Rights Reserved.
//

import Foundation
import SwiftSyntax

/// `DeclarationSemanticsResolving` conforming struct that is responsible for exploring, retrieving properties, and collecting children of a
/// `PatternBindingSyntax` node.
/// It exposes the expected properties of a `Function` as `lazy` properties. This will allow the initial lazy evaluation to not be repeated when
/// accessed repeatedly.
struct VariableSemanticsResolver: SemanticsResolving {
    // MARK: - Properties: SemanticsResolving

    typealias Node = PatternBindingSyntax

    let node: Node

    // MARK: - Lifecycle

    init(node: PatternBindingSyntax) {
        self.node = node
    }

    // MARK: - Resolvers

    func resolveAccessors() -> [Accessor] {
        guard let accessor = node.accessorBlock else { return [] }
        switch accessor.accessors {
        case .accessors(let accessorList):
            return accessorList.map(Accessor.init)
        default:
            return []
        }
    }

    func resolveType() -> EntityType {
        guard let typeAnnotation = node.typeAnnotation?.type else {
            guard
                let parent = node.parent?.as(PatternBindingListSyntax.self),
                let matchingType = parent.first(where: { $0.typeAnnotation != nil })?.typeAnnotation
            else {
                return .empty
            }
            return EntityType(matchingType.type)
        }
        return EntityType(typeAnnotation)
    }

    func resolveName() -> String {
        node.pattern.description.trimmed
    }

    func resolveAttributes() -> [Attribute] {
        guard let parent = node.context?.as(VariableDeclSyntax.self) else { return [] }
        return Attribute.fromAttributeList(parent.attributes)
    }

    func resolveKeyword() -> String {
        guard let parent = node.context?.as(VariableDeclSyntax.self) else { return "" }
        return parent.bindingSpecifier.text.trimmed
    }

    func resolveModifiers() -> [Modifier] {
        guard let parent = node.context?.as(VariableDeclSyntax.self) else { return [] }
        return parent.modifiers.map { Modifier(node: $0) }
    }

    func resolveInitializedValue() -> String? {
        node.initializer?.value.description.trimmed
    }

    func resolveIsOptional() -> Bool {
        guard let typeNode = node.typeAnnotation else { return false }
        return typeNode.type.resolveIsSyntaxOptional()
    }

    func resolveHasSetter() -> Bool {
        // Resolver accessors for assessment
        let accessors = resolveAccessors()
        let accessorKinds = accessors.compactMap(\.kind)
        let hasSetterAccessor = accessorKinds.contains(where: { [.set, .willSet, .didSet].contains($0) })
        let hasEffectGetter = accessors.contains(where: {
            let hasSpecifier = ($0.effectSpecifiers?.throwsSpecifier != nil || $0.effectSpecifiers?.asyncSpecifier != nil)
            return $0.kind == .get && hasSpecifier
        })
        // Check if has throwing or async getter (no setter allowed)
        guard !hasEffectGetter else { return false }
        // If setter exists in accessors can return true
        if hasSetterAccessor { return true }
        // Otherwise if the keyword is not `let` (immutable)
        guard resolveKeyword() != "let" else { return false }
        // Check if modifiers contain a private setter
        guard !resolveModifiers().contains(where: { $0.name == "private" && $0.detail == "set" }) else { return false }
        // Finally if the root context is not a protocol, and the keyword is var, it could have a setter
        let isPotential = node.firstParent(returning: { $0.as(ProtocolDeclSyntax.self )}) == nil && resolveKeyword() == "var"
        if accessors.isEmpty {
            return isPotential
        }
        return isPotential
    }
}
