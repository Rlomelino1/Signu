import Foundation

enum BankLabel {

    static let proxyConnectorIds: Set<String> = ["200"]

    static func institution(from accountName: String) -> String? {
        var name = accountName.replacingOccurrences(
            of: "[ \t]+$", with: "", options: .regularExpression
        )

        if name.hasSuffix(")"), let open = name.lastIndex(of: "(") {
            name = String(name[name.startIndex..<open])
        }
        if let separator = name.range(of: " - ") {
            name = String(name[name.startIndex..<separator.lowerBound])
        }
        name = name.trimmingCharacters(in: .whitespaces)

        return name.count >= 3 ? name : nil
    }

    static func resolve(
        institutionId: String,
        institutionName: String,
        proxiedAccountNames: [String]
    ) -> String {
        guard proxyConnectorIds.contains(institutionId) else { return institutionName }
        for candidate in proxiedAccountNames {
            if let derived = institution(from: candidate) { return derived }
        }
        return institutionName
    }
}

extension SignuPayloadSource {

    func bankLabel(_ connection: Connection) -> String {
        BankLabel.resolve(
            institutionId: connection.institutionId,
            institutionName: connection.institutionName,
            proxiedAccountNames: accountList
                .filter { $0.connectionId == connection.id && $0.type != .creditCard }
                .map(\.officialName)
                .sorted()
        )
    }
}
