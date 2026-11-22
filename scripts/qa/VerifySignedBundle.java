import java.io.InputStream;
import java.nio.file.Path;
import java.security.CodeSigner;
import java.security.MessageDigest;
import java.security.cert.X509Certificate;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;

// Pin the approved upload certificate, independently of the builder's keystore.
// JarFile verifies content as each entry is read; unsigned payloads are refused.
// This does not establish Play approval, provider behavior or device acceptance.
class VerifySignedBundle {
    public static void main(String[] args) {
        try {
            if (args.length != 2 || !args[1].matches("[A-F0-9]{64}")) throw new Exception();
            long total = 0;
            int verified = 0;
            boolean manifest = false;
            HashSet<String> names = new HashSet<>();
            try (JarFile jar = new JarFile(Path.of(args[0]).toFile(), true)) {
                var entries = jar.entries();
                byte[] buffer = new byte[65536];
                while (entries.hasMoreElements()) {
                    JarEntry entry = entries.nextElement();
                    String name = entry.getName();
                    if (!names.add(name) || names.size() > 100000 || name.startsWith("/")
                            || name.contains("\\") || java.util.Arrays.asList(name.split("/")).contains("..")) throw new Exception();
                    if (entry.isDirectory()) continue;
                    try (InputStream input = jar.getInputStream(entry)) {
                        int count;
                        while ((count = input.read(buffer)) != -1) {
                            total += count;
                            if (total > 4L * 1024 * 1024 * 1024) throw new Exception();
                        }
                    }
                    if (name.equals("base/manifest/AndroidManifest.xml")) manifest = true;
                    String upper = name.toUpperCase(java.util.Locale.ROOT);
                    if (upper.equals("META-INF/MANIFEST.MF")
                            || upper.matches("META-INF/[^/]+\\.(SF|RSA|DSA|EC)")) continue;
                    CodeSigner[] signers = entry.getCodeSigners();
                    if (signers == null || signers.length != 1) throw new Exception();
                    X509Certificate certificate = (X509Certificate) signers[0].getSignerCertPath().getCertificates().get(0);
                    certificate.checkValidity();
                    String fingerprint = HexFormat.of().withUpperCase().formatHex(MessageDigest.getInstance("SHA-256").digest(certificate.getEncoded()));
                    if (!fingerprint.equals(args[1])) throw new Exception();
                    verified++;
                }
            }
            if (!manifest || verified == 0) throw new Exception();
            System.out.println("{\"status\":\"pass\",\"signer_sha256\":\"" + args[1]
                    + "\",\"verified_payload_entries\":" + verified
                    + ",\"verification\":\"JarFile content verification plus approved upload certificate pin\"}");
        } catch (Exception error) {
            System.err.println("Signed AAB verification failed.");
            System.exit(1);
        }
    }
}
