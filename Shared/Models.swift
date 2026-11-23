import Foundation

struct Member: Codable, Equatable, Identifiable, Hashable {
    let id: String
    var name: String
    let role: String
}

/// Answer of `POST /pair/create` (has a code for the partner) and `POST /pair/join` (no code).
struct PairResult: Codable, Equatable {
    let deviceKey: String
    let me: Member
    let partner: Member?
    let pairCode: String?
    let pairCodeExpiresAt: Date?
}

struct MeResult: Codable, Equatable {
    let me: Member
    let partner: Member?
    let coupleId: String
}

struct PairCode: Codable, Equatable {
    let pairCode: String
    let pairCodeExpiresAt: Date
}

struct LookupMember: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let role: String
    let connected: Bool
}

struct LookupResult: Codable, Equatable {
    let members: [LookupMember]
    let suggested: String?
}

struct CodeResult: Codable, Equatable { let pairCode: String }

struct Empty: Codable {}

/// Marker type: perform() returns the bytes as they came.
struct RawBody: Decodable {
    let data: Data
    init(data: Data) { self.data = data }
    init(from decoder: Decoder) throws { data = Data() }
}
