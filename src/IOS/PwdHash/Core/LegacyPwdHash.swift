// Native port of Stanford PwdHash's website algorithm.
// Copyright 2005 Collin Jackson. BSD-3-Clause; see ThirdPartyNotices.txt.
import CryptoKit
import Foundation

enum PwdHashError: Error, LocalizedError {
    case missingAddress
    case missingPassword

    var errorDescription: String? {
        switch self {
        case .missingAddress: return "Enter a site address."
        case .missingPassword: return "Enter your site password."
        }
    }
}

struct LegacyPwdHash {
    /// Deliberately preserves the original extractor, including case, ports,
    /// and its historical suffix list. URL/modern public-suffix normalization
    /// would change existing passwords.
    static func domain(for address: String) throws -> String {
        var host = address
        for prefix in ["http://", "https://"] {
            if let range = host.range(of: prefix, options: .literal) { host.removeSubrange(range) }
        }
        guard let first = host.components(separatedBy: "/").first(where: { !$0.isEmpty }) else {
            throw PwdHashError.missingAddress
        }
        let parts = String(first).components(separatedBy: ".")
        guard parts.count >= 3 else { return parts.joined(separator: ".") }
        let suffix = parts.suffix(2).joined(separator: ".")
        return suffixes.contains(suffix) ? parts.suffix(3).joined(separator: ".") : suffix
    }

    static func generate(address: String, password: String) throws -> String {
        let realm = try domain(for: address)
        guard !password.isEmpty else { throw PwdHashError.missingPassword }
        return derive(realm: realm, password: password)
    }

    /// Exact website behavior, including stripping one leading @@, UTF-16
    /// length, low-byte character encoding, and the original output constraints.
    /// Kept separate from form validation for differential compatibility tests.
    static func derive(realm: String, password: String) -> String {
        var source = Array(password.utf16)
        if source.starts(with: [64, 64]) { source.removeFirst(2) }
        var key = Data(source.map { UInt8(truncatingIfNeeded: $0) })
        var message = Data(realm.utf16.map { UInt8(truncatingIfNeeded: $0) })
        defer {
            key.resetBytes(in: 0..<key.count)
            message.resetBytes(in: 0..<message.count)
            _ = source.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
        }
        let digest = HMAC<Insecure.MD5>.authenticationCode(for: message, using: SymmetricKey(data: key))
        let hash = Array(Data(digest).base64EncodedString().utf8.filter { $0 != 61 })
        let start = min(max(source.count - 2, 0), hash.count)
        var result = Array(hash.prefix(start))
        var extraIndex = start
        func nextExtra() -> UInt8 {
            guard extraIndex < hash.count else { return 0 }
            defer { extraIndex += 1 }
            return hash[extraIndex]
        }
        let wantsSymbol = source.contains { !isWord($0) }
        result.append(result.contains { (65...90).contains($0) } ? nextExtra() : 65 + nextExtra() % 26)
        result.append(result.contains { (97...122).contains($0) } ? nextExtra() : 97 + nextExtra() % 26)
        result.append(result.contains { (48...57).contains($0) } ? nextExtra() : 48 + nextExtra() % 10)
        result.append(result.contains { !isWord(UInt16($0)) } && wantsSymbol ? nextExtra() : 43)
        if !wantsSymbol {
            while let index = result.firstIndex(where: { !isWord(UInt16($0)) }) {
                result[index] = 65 + nextExtra() % 26
            }
        }
        let rotation = Int(nextExtra()) % result.count
        return String(decoding: result.dropFirst(rotation) + result.prefix(rotation), as: UTF8.self)
    }

    private static func isWord(_ value: UInt16) -> Bool {
        (65...90).contains(value) || (97...122).contains(value) || (48...57).contains(value) || value == 95
    }

    private static let suffixes = Set("ab.ca|ac.ac|ac.at|ac.be|ac.cn|ac.il|ac.in|ac.jp|ac.kr|ac.nz|ac.th|ac.uk|ac.za|adm.br|adv.br|agro.pl|ah.cn|aid.pl|alt.za|am.br|arq.br|art.br|arts.ro|asn.au|asso.fr|asso.mc|atm.pl|auto.pl|bbs.tr|bc.ca|bio.br|biz.pl|bj.cn|br.com|cn.com|cng.br|cnt.br|co.ac|co.at|co.il|co.in|co.jp|co.kr|co.nz|co.th|co.uk|co.za|com.au|com.br|com.cn|com.ec|com.fr|com.hk|com.mm|com.mx|com.pl|com.ro|com.ru|com.sg|com.tr|com.tw|cq.cn|cri.nz|de.com|ecn.br|edu.au|edu.cn|edu.hk|edu.mm|edu.mx|edu.pl|edu.tr|edu.za|eng.br|ernet.in|esp.br|etc.br|eti.br|eu.com|eu.lv|fin.ec|firm.ro|fm.br|fot.br|fst.br|g12.br|gb.com|gb.net|gd.cn|gen.nz|gmina.pl|go.jp|go.kr|go.th|gob.mx|gov.br|gov.cn|gov.ec|gov.il|gov.in|gov.mm|gov.mx|gov.sg|gov.tr|gov.za|govt.nz|gs.cn|gsm.pl|gv.ac|gv.at|gx.cn|gz.cn|hb.cn|he.cn|hi.cn|hk.cn|hl.cn|hn.cn|hu.com|idv.tw|ind.br|inf.br|info.pl|info.ro|iwi.nz|jl.cn|jor.br|jpn.com|js.cn|k12.il|k12.tr|lel.br|ln.cn|ltd.uk|mail.pl|maori.nz|mb.ca|me.uk|med.br|med.ec|media.pl|mi.th|miasta.pl|mil.br|mil.ec|mil.nz|mil.pl|mil.tr|mil.za|mo.cn|muni.il|nb.ca|ne.jp|ne.kr|net.au|net.br|net.cn|net.ec|net.hk|net.il|net.in|net.mm|net.mx|net.nz|net.pl|net.ru|net.sg|net.th|net.tr|net.tw|net.za|nf.ca|ngo.za|nm.cn|nm.kr|no.com|nom.br|nom.pl|nom.ro|nom.za|ns.ca|nt.ca|nt.ro|ntr.br|nx.cn|odo.br|on.ca|or.ac|or.at|or.jp|or.kr|or.th|org.au|org.br|org.cn|org.ec|org.hk|org.il|org.mm|org.mx|org.nz|org.pl|org.ro|org.ru|org.sg|org.tr|org.tw|org.uk|org.za|pc.pl|pe.ca|plc.uk|ppg.br|presse.fr|priv.pl|pro.br|psc.br|psi.br|qc.ca|qc.com|qh.cn|re.kr|realestate.pl|rec.br|rec.ro|rel.pl|res.in|ru.com|sa.com|sc.cn|school.nz|school.za|se.com|se.net|sh.cn|shop.pl|sk.ca|sklep.pl|slg.br|sn.cn|sos.pl|store.ro|targi.pl|tj.cn|tm.fr|tm.mc|tm.pl|tm.ro|tm.za|tmp.br|tourism.pl|travel.pl|tur.br|turystyka.pl|tv.br|tw.cn|uk.co|uk.com|uk.net|us.com|uy.com|vet.br|web.za|web.com|www.ro|xj.cn|xz.cn|yk.ca|yn.cn|za.com".components(separatedBy: "|"))
}
