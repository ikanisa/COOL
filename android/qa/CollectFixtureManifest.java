import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.transform.OutputKeys;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;
import org.w3c.dom.Element;
import org.w3c.dom.Node;

/** Source-manifest boundary for the isolated debug media fixture only. */
public final class CollectFixtureManifest {
    private static final String ANDROID = "http://schemas.android.com/apk/res/android";
    private static final String FIXTURE = "app.cool.mobile.mediafixture";
    private static final String INTERNET = "android.permission.INTERNET";
    private static final List<String> STORAGE = List.of(
        "android.permission.READ_EXTERNAL_STORAGE", "android.permission.WRITE_EXTERNAL_STORAGE");

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalArgumentException(message);
    }

    public static void main(String[] args) throws Exception {
        require(args.length == 2, "Expected input and output merged manifest paths");
        Path input = Path.of(args[0]).toAbsolutePath().normalize();
        Path output = Path.of(args[1]).toAbsolutePath().normalize();
        require(Files.isRegularFile(input) && !Files.isSymbolicLink(input), "Physical input manifest required");
        require(!Files.isSymbolicLink(output) && !input.equals(output)
            && (!Files.exists(output) || !Files.isSameFile(input, output)), "Distinct output artifact required");
        var factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(true);
        factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
        factory.setFeature("http://xml.org/sax/features/external-general-entities", false);
        factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
        factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "");
        factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "");
        factory.setXIncludeAware(false);
        factory.setExpandEntityReferences(false);
        var document = factory.newDocumentBuilder().parse(input.toFile());
        Element root = document.getDocumentElement();
        require(root.getTagName().equals("manifest") && root.getAttribute("package").equals(FIXTURE),
            "Only the isolated Collect fixture manifest is admitted");
        Element application = null;
        List<Node> remove = new ArrayList<>();
        int internet = 0;
        for (Node node = root.getFirstChild(); node != null; node = node.getNextSibling()) {
            if (!(node instanceof Element element)) continue;
            if (element.getTagName().equals("application")) {
                require(application == null, "One application element required");
                application = element;
            }
            if (!element.getTagName().equals("uses-permission")
                && !element.getTagName().equals("uses-permission-sdk-23")) continue;
            String name = element.getAttributeNS(ANDROID, "name");
            if (STORAGE.contains(name)) remove.add(element);
            else if (name.equals(INTERNET)) internet++;
            else throw new IllegalArgumentException("Unexpected fixture permission: " + name);
        }
        require(application != null && application.getAttributeNS(ANDROID, "debuggable").equals("true")
            && application.getAttributeNS(ANDROID, "allowBackup").equals("false"),
            "Only a debug fixture without backup is admitted");
        require(internet == 1, "Exactly one existing INTERNET declaration required");
        for (Node node : remove) root.removeChild(node);
        // No unrelated manifest node or attribute is rewritten. The existing
        // decoded/merged APK guard remains the final component/permission gate.
        var transformers = TransformerFactory.newInstance();
        transformers.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
        transformers.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "");
        transformers.setAttribute(XMLConstants.ACCESS_EXTERNAL_STYLESHEET, "");
        var transformer = transformers.newTransformer();
        transformer.setOutputProperty(OutputKeys.ENCODING, "UTF-8");
        Files.createDirectories(output.getParent());
        transformer.transform(new DOMSource(document), new StreamResult(output.toFile()));
    }
}
