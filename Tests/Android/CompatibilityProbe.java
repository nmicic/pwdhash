package app.nmic.pwdhash;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Base64;

/** Test-only stdin protocol; inputs are the synthetic original-JS corpus. */
public final class CompatibilityProbe {
    public static void main(String[] args) throws Exception {
        IdleDeadline idle = new IdleDeadline();
        if (idle.isExpired(1)) throw new AssertionError();
        idle.touch(1000);
        if (idle.isExpired(300999) || !idle.isExpired(301000)) throw new AssertionError();
        idle.touch(300999);
        if (idle.isExpired(600998) || !idle.isExpired(600999)) throw new AssertionError();
        idle.reset();
        if (idle.isExpired(9999999)) throw new AssertionError();
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        String line;
        while ((line = input.readLine()) != null) {
            String[] parts = line.split("\\t", -1);
            String address = new String(Base64.getDecoder().decode(parts[0]), StandardCharsets.UTF_8);
            char[] password = new String(Base64.getDecoder().decode(parts[1]), StandardCharsets.UTF_8).toCharArray();
            try {
                String domain = LegacyPwdHash.domain(address);
                String result = LegacyPwdHash.derive(domain, password);
                System.out.println(Base64.getEncoder().encodeToString(domain.getBytes(StandardCharsets.UTF_8)) + "\t" + Base64.getEncoder().encodeToString(result.getBytes(StandardCharsets.UTF_8)));
            } catch (IllegalArgumentException error) {
                System.out.println("ERROR");
            } finally { Arrays.fill(password, '\0'); }
        }
    }
}
