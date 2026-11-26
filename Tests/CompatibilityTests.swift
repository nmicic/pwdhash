import Foundation

struct Vector: Decodable {
    let address: String
    let password: String
    let domain: String?
    let result: String?
}

@main
struct CompatibilityTests {
    static func main() throws {
        let path = CommandLine.arguments[1]
        let vectors = try JSONDecoder().decode([Vector].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        for (index, vector) in vectors.enumerated() {
            do {
                let domain = try LegacyPwdHash.domain(for: vector.address)
                precondition(domain == vector.domain, "Domain mismatch in synthetic case \(index)")
                let result = LegacyPwdHash.derive(realm: domain, password: vector.password)
                precondition(result == vector.result, "Password mismatch in synthetic case \(index)")
            } catch {
                precondition(vector.domain == nil, "Unexpected failure in synthetic case \(index)")
            }
        }
        let now = ContinuousClock.now
        var lease = IdleDeadline()
        precondition(!lease.isExpired(at: now))
        lease.touch(at: now)
        precondition(!lease.isExpired(at: now.advanced(by: .seconds(299))))
        precondition(lease.isExpired(at: now.advanced(by: .seconds(300))))
        precondition(lease.isExpired(at: now.advanced(by: .seconds(3600))))
        lease.touch(at: now.advanced(by: .seconds(299)))
        precondition(!lease.isExpired(at: now.advanced(by: .seconds(598))))
        precondition(lease.isExpired(at: now.advanced(by: .seconds(599))))
        lease.reset()
        precondition(!lease.isExpired(at: now.advanced(by: .seconds(3600))))
        do {
            _ = try LegacyPwdHash.generate(address: "example.com", password: "")
            preconditionFailure("An empty password must not generate in the form")
        } catch PwdHashError.missingPassword {}
        print("PASS: \(vectors.count) original-website compatibility cases and idle deadline boundaries")
    }
}
