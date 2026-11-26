// Native port of Stanford PwdHash. Copyright 2005 Collin Jackson.
// Original BSD notice is bundled as ThirdPartyNotices.txt.
package app.nmic.pwdhash;

import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;
import java.util.Base64;
import java.util.HashSet;
import java.util.Set;

public final class LegacyPwdHash {
    private LegacyPwdHash() {}
    private static final Set<String> SUFFIXES = new HashSet<>(Arrays.asList("ab.ca|ac.ac|ac.at|ac.be|ac.cn|ac.il|ac.in|ac.jp|ac.kr|ac.nz|ac.th|ac.uk|ac.za|adm.br|adv.br|agro.pl|ah.cn|aid.pl|alt.za|am.br|arq.br|art.br|arts.ro|asn.au|asso.fr|asso.mc|atm.pl|auto.pl|bbs.tr|bc.ca|bio.br|biz.pl|bj.cn|br.com|cn.com|cng.br|cnt.br|co.ac|co.at|co.il|co.in|co.jp|co.kr|co.nz|co.th|co.uk|co.za|com.au|com.br|com.cn|com.ec|com.fr|com.hk|com.mm|com.mx|com.pl|com.ro|com.ru|com.sg|com.tr|com.tw|cq.cn|cri.nz|de.com|ecn.br|edu.au|edu.cn|edu.hk|edu.mm|edu.mx|edu.pl|edu.tr|edu.za|eng.br|ernet.in|esp.br|etc.br|eti.br|eu.com|eu.lv|fin.ec|firm.ro|fm.br|fot.br|fst.br|g12.br|gb.com|gb.net|gd.cn|gen.nz|gmina.pl|go.jp|go.kr|go.th|gob.mx|gov.br|gov.cn|gov.ec|gov.il|gov.in|gov.mm|gov.mx|gov.sg|gov.tr|gov.za|govt.nz|gs.cn|gsm.pl|gv.ac|gv.at|gx.cn|gz.cn|hb.cn|he.cn|hi.cn|hk.cn|hl.cn|hn.cn|hu.com|idv.tw|ind.br|inf.br|info.pl|info.ro|iwi.nz|jl.cn|jor.br|jpn.com|js.cn|k12.il|k12.tr|lel.br|ln.cn|ltd.uk|mail.pl|maori.nz|mb.ca|me.uk|med.br|med.ec|media.pl|mi.th|miasta.pl|mil.br|mil.ec|mil.nz|mil.pl|mil.tr|mil.za|mo.cn|muni.il|nb.ca|ne.jp|ne.kr|net.au|net.br|net.cn|net.ec|net.hk|net.il|net.in|net.mm|net.mx|net.nz|net.pl|net.ru|net.sg|net.th|net.tr|net.tw|net.za|nf.ca|ngo.za|nm.cn|nm.kr|no.com|nom.br|nom.pl|nom.ro|nom.za|ns.ca|nt.ca|nt.ro|ntr.br|nx.cn|odo.br|on.ca|or.ac|or.at|or.jp|or.kr|or.th|org.au|org.br|org.cn|org.ec|org.hk|org.il|org.mm|org.mx|org.nz|org.pl|org.ro|org.ru|org.sg|org.tr|org.tw|org.uk|org.za|pc.pl|pe.ca|plc.uk|ppg.br|presse.fr|priv.pl|pro.br|psc.br|psi.br|qc.ca|qc.com|qh.cn|re.kr|realestate.pl|rec.br|rec.ro|rel.pl|res.in|ru.com|sa.com|sc.cn|school.nz|school.za|se.com|se.net|sh.cn|shop.pl|sk.ca|sklep.pl|slg.br|sn.cn|sos.pl|store.ro|targi.pl|tj.cn|tm.fr|tm.mc|tm.pl|tm.ro|tm.za|tmp.br|tourism.pl|travel.pl|tur.br|turystyka.pl|tv.br|tw.cn|uk.co|uk.com|uk.net|us.com|uy.com|vet.br|web.za|web.com|www.ro|xj.cn|xz.cn|yk.ca|yn.cn|za.com".split("\\|")));

    private static String removeFirst(String text, String literal) {
        int index = text.indexOf(literal);
        return index < 0 ? text : text.substring(0, index) + text.substring(index + literal.length());
    }

    public static String domain(String address) {
        String host = removeFirst(removeFirst(address, "http://"), "https://");
        int begin = 0;
        while (begin < host.length() && host.charAt(begin) == '/') begin++;
        int end = host.indexOf('/', begin);
        if (end < 0) end = host.length();
        if (begin == end) throw new IllegalArgumentException("Enter a site address.");
        String[] parts = host.substring(begin, end).split("\\.", -1);
        if (parts.length < 3) return String.join(".", parts);
        String suffix = parts[parts.length - 2] + "." + parts[parts.length - 1];
        return SUFFIXES.contains(suffix) ? parts[parts.length - 3] + "." + suffix : suffix;
    }

    public static String generate(String address, char[] password) {
        String realm = domain(address);
        if (password.length == 0) throw new IllegalArgumentException("Enter your site password.");
        return derive(realm, password);
    }

    /** Exact JS UTF-16 length, low bytes, @@ prefix, and historical constraints. */
    public static String derive(String realm, char[] password) {
        int offset = password.length >= 2 && password[0] == '@' && password[1] == '@' ? 2 : 0;
        byte[] key = new byte[password.length - offset];
        byte[] data = new byte[realm.length()];
        byte[] pad = new byte[64], inner = null, digest = null;
        boolean symbols = false;
        for (int i = offset; i < password.length; i++) {
            key[i - offset] = (byte)password[i];
            if (!word(password[i])) symbols = true;
        }
        for (int i = 0; i < realm.length(); i++) data[i] = (byte)realm.charAt(i);
        try {
            MessageDigest md5 = MessageDigest.getInstance("MD5");
            if (key.length > 64) {
                byte[] original = key;
                key = md5.digest(key);
                Arrays.fill(original, (byte)0);
            }
            for (int i = 0; i < 64; i++) pad[i] = (byte)((i < key.length ? key[i] : 0) ^ 0x36);
            md5.update(pad);
            inner = md5.digest(data);
            for (int i = 0; i < 64; i++) pad[i] = (byte)((i < key.length ? key[i] : 0) ^ 0x5c);
            md5.update(pad);
            digest = md5.digest(inner);
            String hash = Base64.getEncoder().withoutPadding().encodeToString(digest);
            return constrain(hash, password.length - offset, symbols);
        } catch (NoSuchAlgorithmException error) {
            throw new IllegalStateException("The original PwdHash MD5 algorithm is unavailable.", error);
        } finally {
            Arrays.fill(key, (byte)0); Arrays.fill(data, (byte)0); Arrays.fill(pad, (byte)0);
            if (inner != null) Arrays.fill(inner, (byte)0);
            if (digest != null) Arrays.fill(digest, (byte)0);
        }
    }

    private static boolean word(char value) {
        return value >= 'A' && value <= 'Z' || value >= 'a' && value <= 'z' || value >= '0' && value <= '9' || value == '_';
    }

    private static int extra(String hash, int[] position) {
        return position[0] < hash.length() ? hash.charAt(position[0]++) : 0;
    }

    private static boolean contains(char[] result, int length, char lower, char upper) {
        for (int i = 0; i < length; i++) if (result[i] >= lower && result[i] <= upper) return true;
        return false;
    }

    private static String constrain(String hash, int passwordLength, boolean symbols) {
        int n = Math.min(Math.max(passwordLength - 2, 0), hash.length());
        char[] result = new char[n + 4], rotated = new char[n + 4];
        int[] position = {n};
        hash.getChars(0, n, result, 0);
        result[n] = (char)(contains(result, n, 'A', 'Z') ? extra(hash, position) : 'A' + extra(hash, position) % 26); n++;
        result[n] = (char)(contains(result, n, 'a', 'z') ? extra(hash, position) : 'a' + extra(hash, position) % 26); n++;
        result[n] = (char)(contains(result, n, '0', '9') ? extra(hash, position) : '0' + extra(hash, position) % 10); n++;
        boolean hasSymbol = false;
        for (int i = 0; i < n; i++) if (!word(result[i])) hasSymbol = true;
        result[n++] = (char)(hasSymbol && symbols ? extra(hash, position) : '+');
        if (!symbols) for (int i = 0; i < n; i++) if (!word(result[i])) result[i] = (char)('A' + extra(hash, position) % 26);
        int rotation = extra(hash, position) % n;
        for (int i = 0; i < n; i++) rotated[i] = result[(i + rotation) % n];
        String answer = new String(rotated);
        Arrays.fill(result, '\0'); Arrays.fill(rotated, '\0');
        return answer;
    }
}
