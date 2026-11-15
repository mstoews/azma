import Foundation

struct EmployerOverview: Codable, Sendable {
    var profile: EmployerProfile
    var jobs: [Job]
}

struct EmployerProfile: Codable, Sendable, Equatable {
    var company: String = ""
    var contactName: String = ""
    var contactRole: String = ""
    var phone: String = ""
    var website: String = ""
    var location: String = ""
    var about: String = ""

    var problem: String? {
        if company.trimmed.isEmpty { return "Your company name is required." }
        if contactName.trimmed.isEmpty { return "A contact name is required." }
        return nil
    }
}
