import com.android.apksig.ApkVerifier;
import java.io.File;
import java.security.MessageDigest;
import java.security.cert.X509Certificate;
import java.util.HexFormat;
import java.util.List;

public class ConvoyApkCertificate {
  static String digest(X509Certificate c) throws Exception {
    return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(c.getEncoded()));
  }
  static void same(String expected, List<X509Certificate> certs, String scheme) throws Exception {
    if (certs.size() != 1 || !digest(certs.get(0)).equals(expected))
      throw new IllegalStateException("Wrong or ambiguous signer in " + scheme);
  }
  public static void main(String[] args) throws Exception {
    if (args.length != 2 || !args[1].matches("[0-9a-f]{64}"))
      throw new IllegalArgumentException("APK and expected SHA-256 required");
    var r = new ApkVerifier.Builder(new File(args[0])).build().verify();
    if (!r.isVerified() || !r.isVerifiedUsingV2Scheme())
      throw new IllegalStateException("APK or v2 signature not verified: " + r.getErrors());
    String expected = args[1];
    same(expected, r.getSignerCertificates(), "Android signer");
    same(expected, r.getV2SchemeSigners().stream().map(x -> x.getCertificate()).toList(), "v2");
    if (r.isVerifiedUsingV3Scheme())
      same(expected, r.getV3SchemeSigners().stream().map(x -> x.getCertificate()).toList(), "v3");
    if (r.isVerifiedUsingV31Scheme())
      same(expected, r.getV31SchemeSigners().stream().map(x -> x.getCertificate()).toList(), "v3.1");
    if (r.isVerifiedUsingV1Scheme())
      same(expected, r.getV1SchemeSigners().stream().map(x -> x.getCertificate()).toList(), "v1");
    System.out.println("Verified single APK signer across verified schemes: " + expected);
  }
}
