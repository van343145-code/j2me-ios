/*
 * MIDletRunner — Java-based MIDlet launcher for iOS/miniJVM.
 *
 * Replaces J2ME-Loader's MicroLoader + MidletThread + MicroActivity.
 * Reads the MIDlet JAR manifest, loads the MIDlet class via reflection,
 * and manages the MIDlet lifecycle (startApp/pauseApp/destroyApp).
 */
package javax.microedition.shell;

import javax.microedition.midlet.MIDlet;
import javax.microedition.midlet.MIDletStateChangeException;
import javax.microedition.lcdui.Canvas;
import javax.microedition.lcdui.Display;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.Map;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

public class MIDletRunner {

    /**
     * Entry point. Args:
     *   args[0] = path to MIDlet JAR file
     *   args[1] = (optional) MIDlet class name override
     */
    public static void main(String[] args) {
        if (args == null || args.length < 1) {
            System.out.println("[MIDletRunner] ERROR: Usage: MIDletRunner <midlet.jar> [ClassName]");
            return;
        }

        String jarPath = args[0];
        String classNameOverride = (args.length > 1) ? args[1] : null;

        System.out.println("[MIDletRunner] Loading MIDlet JAR: " + jarPath);

        try {
            // 1. Read manifest
            Map<String, String> manifestAttrs = readManifest(jarPath);

            String midletName = manifestAttrs.get("MIDlet-Name");
            String midletVersion = manifestAttrs.get("MIDlet-Version");
            System.out.println("[MIDletRunner] MIDlet-Name: " + midletName);
            System.out.println("[MIDletRunner] MIDlet-Version: " + midletVersion);

            // 2. Determine MIDlet class name
            String className;
            if (classNameOverride != null && !classNameOverride.isEmpty()) {
                className = classNameOverride;
            } else {
                className = parseMIDletClassName(manifestAttrs);
            }

            if (className == null) {
                System.out.println("[MIDletRunner] ERROR: No MIDlet class found in manifest");
                return;
            }
            System.out.println("[MIDletRunner] MIDlet class: " + className);

            // 3. Initialize properties (manifest attributes available to MIDlet)
            MIDlet.initProps(manifestAttrs);
            MIDlet.resetDestroyRequest();

            // Apply FPS limit from system property (set by iOS native side)
            String fpsStr = System.getProperty("j2me.fps.limit");
            if (fpsStr != null) {
                try {
                    Canvas.setLimitFps(Integer.parseInt(fpsStr));
                } catch (NumberFormatException ignored) {}
            }

            // 4. Load and instantiate MIDlet class
            System.out.println("[MIDletRunner] Loading class: " + className);
            Class<?> clazz = Class.forName(className);
            MIDlet midlet = (MIDlet) clazz.newInstance();

            // 5. Run lifecycle
            runLifecycle(midlet);

        } catch (Exception e) {
            System.out.println("[MIDletRunner] ERROR: " + e.getClass().getName() + ": " + e.getMessage());
            e.printStackTrace();
        }
    }

    /**
     * Read all attributes from the JAR's META-INF/MANIFEST.MF (case-insensitive)
     * and merge companion .jad attributes if present (strict J2ME MIDP 2.0 spec).
     */
    private static Map<String, String> readManifest(String jarPath) throws Exception {
        Map<String, String> result = new HashMap<String, String>();

        ZipFile zipFile = new ZipFile(jarPath);
        try {
            ZipEntry entry = zipFile.getEntry("META-INF/MANIFEST.MF");
            if (entry == null) {
                Enumeration<? extends ZipEntry> entries = zipFile.entries();
                while (entries.hasMoreElements()) {
                    ZipEntry e = entries.nextElement();
                    if (e.getName() != null && e.getName().equalsIgnoreCase("META-INF/MANIFEST.MF")) {
                        entry = e;
                        break;
                    }
                }
            }
            if (entry == null) {
                System.out.println("[MIDletRunner] WARNING: No MANIFEST.MF in JAR");
            } else {
                parseKeyValueStream(zipFile.getInputStream(entry), result);
            }
        } finally {
            zipFile.close();
        }

        // Standard J2ME: overlay companion .jad file if present next to .jar
        try {
            int dot = jarPath.lastIndexOf('.');
            String jadPath = (dot > 0 ? jarPath.substring(0, dot) : jarPath) + ".jad";
            File jadFile = new File(jadPath);
            if (jadFile.exists() && jadFile.isFile()) {
                System.out.println("[MIDletRunner] Merging companion JAD: " + jadPath);
                InputStream jadIs = new FileInputStream(jadFile);
                try {
                    parseKeyValueStream(jadIs, result);
                } finally {
                    jadIs.close();
                }
            }
        } catch (Throwable ignored) {}

        return result;
    }

    private static void parseKeyValueStream(InputStream is, Map<String, String> result) throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(is, "UTF-8"));
        try {
            String lastKey = null;
            String line;
            boolean firstLine = true;
            while ((line = reader.readLine()) != null) {
                if (firstLine) {
                    firstLine = false;
                    if (line.length() > 0 && line.charAt(0) == '\uFEFF') {
                        line = line.substring(1);
                    }
                }
                if (line.isEmpty()) continue;

                // Continuation line (starts with space)
                if (line.charAt(0) == ' ' && lastKey != null) {
                    String prev = result.get(lastKey);
                    result.put(lastKey, (prev != null ? prev : "") + line.substring(1));
                    continue;
                }

                int colon = line.indexOf(':');
                if (colon > 0) {
                    String key = line.substring(0, colon).trim();
                    String value = line.substring(colon + 1).trim();
                    result.put(key, value);
                    lastKey = key;
                }
            }
        } finally {
            reader.close();
        }
    }

    /**
     * Parse the MIDlet class name from MIDlet-1 attribute.
     * Format: "Name, Icon, ClassName"
     */
    private static String parseMIDletClassName(Map<String, String> attrs) {
        // Try MIDlet-1 first
        String midlet1 = attrs.get("MIDlet-1");
        if (midlet1 == null) {
            // Try any MIDlet-N (case-insensitive)
            for (Map.Entry<String, String> entry : attrs.entrySet()) {
                String key = entry.getKey();
                if (key.length() > 7 && key.substring(0, 7).equalsIgnoreCase("MIDlet-")) {
                    String suffix = key.substring(7);
                    boolean isNum = suffix.length() > 0;
                    for (int i = 0; i < suffix.length(); i++) {
                        char c = suffix.charAt(i);
                        if (c < '0' || c > '9') { isNum = false; break; }
                    }
                    if (isNum) {
                        midlet1 = entry.getValue();
                        break;
                    }
                }
            }
        }

        if (midlet1 == null) return null;

        System.out.println("[MIDletRunner] MIDlet-1: " + midlet1);

        // Parse "Name, Icon, ClassName"
        String rawClass = null;
        String[] parts = midlet1.split(",");
        if (parts.length >= 3) {
            rawClass = parts[2].trim();
        } else if (parts.length == 2) {
            rawClass = parts[1].trim();
        } else if (parts.length == 1) {
            rawClass = parts[0].trim();
        }

        if (rawClass != null && rawClass.length() > 0) {
            if (rawClass.endsWith(".class")) {
                rawClass = rawClass.substring(0, rawClass.length() - 6);
            }
            rawClass = rawClass.replace('/', '.');
            return rawClass;
        }

        return null;
    }

    /**
     * Run the MIDlet lifecycle: startApp → (wait) → pauseApp → destroyApp
     */
    private static void runLifecycle(MIDlet midlet) {
        try {
            // startApp
            System.out.println("[MIDletRunner] >>> Calling startApp()");
            midlet.callStartApp();
            System.out.println("[MIDletRunner] <<< startApp() returned");

            // Run event/render loop — blocks until MIDlet calls notifyDestroyed().
            // Always run the loop — MIDlet may set Display.setCurrent()
            // asynchronously from its own thread (e.g. Gravity Defied).
            // If native stop was already requested (user pressed Back during init/startApp),
            // the loop will detect it on the first iteration and exit immediately.
            Display display = Display.getDisplay(midlet);
            display.runEventLoop();

            // pauseApp
            if (!MIDlet.isDestroyRequested()) {
                System.out.println("[MIDletRunner] >>> Calling pauseApp()");
                midlet.callPauseApp();
                System.out.println("[MIDletRunner] <<< pauseApp() returned");
            }

            // destroyApp
            System.out.println("[MIDletRunner] >>> Calling destroyApp(true)");
            midlet.callDestroyApp(true);
            System.out.println("[MIDletRunner] <<< destroyApp() returned");

            System.out.println("[MIDletRunner] MIDlet lifecycle complete");

        } catch (MIDletStateChangeException e) {
            System.out.println("[MIDletRunner] MIDletStateChangeException: " + e.getMessage());
        } catch (Exception e) {
            System.out.println("[MIDletRunner] ERROR in lifecycle: " + e.getClass().getName()
                    + ": " + e.getMessage());
            e.printStackTrace();
        }
    }
}
