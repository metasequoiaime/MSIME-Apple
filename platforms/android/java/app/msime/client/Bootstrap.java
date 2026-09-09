package app.msime.client;

import android.content.Context;
import android.util.AtomicFile;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.channels.FileChannel;
import java.nio.channels.FileLock;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.nio.file.StandardOpenOption;
import org.json.JSONArray;
import org.json.JSONObject;

/** First-install preparation only. Existing configurations are never upgraded in place. */
public final class Bootstrap {
    private Bootstrap() {}
    public static boolean prepare(Context context) throws Exception {
        File root = context.getFilesDir();
        try (FileChannel channel = FileChannel.open(new File(root, "bootstrap.lock").toPath(), StandardOpenOption.CREATE, StandardOpenOption.WRITE);
             FileLock lock = channel.lock()) {
            if (!lock.isValid()) throw new IllegalStateException("Bootstrap lock unavailable");
            File configuration = new File(root, "runtime-options.json");
            if (configuration.exists()) return false;
            File resources = new File(root, "bootstrap/resources");
            Files.createDirectories(resources.toPath());
            JSONObject manifest;
            try (InputStream input = context.getAssets().open("desktop-dictionary.lock.json")) {
                // Small immutable APK manifest; large dictionary files are streamed below.
                java.io.ByteArrayOutputStream bytes = new java.io.ByteArrayOutputStream();
                byte[] buffer = new byte[8192];
                int count;
                while ((count = input.read(buffer)) != -1) {
                    if (bytes.size() + count > 16384) throw new IllegalArgumentException("Manifest too large");
                    bytes.write(buffer, 0, count);
                }
                manifest = new JSONObject(bytes.toString(StandardCharsets.UTF_8.name()));
            }
            JSONArray artifacts = manifest.getJSONArray("artifacts");
            for (int index = 0; index < artifacts.length(); index++) {
                String name = artifacts.getJSONObject(index).getString("name");
                if (!name.matches("[A-Za-z0-9_.-]+") || name.contains("..")) throw new IllegalArgumentException("Invalid asset name");
                try (InputStream input = context.getAssets().open("dictionary/" + name)) {
                    Files.copy(input, new File(resources, name).toPath(), StandardCopyOption.REPLACE_EXISTING);
                }
            }
            JSONObject request = new JSONObject().put("resources", resources.getAbsolutePath())
                .put("state_root", new File(root, "bootstrap/state").getAbsolutePath());
            JSONObject result = new JSONObject(NativeClient.prepareHost(request.toString()));
            if (!result.getBoolean("ok")) throw new IllegalStateException("Shared resource verification/preparation failed");
            AtomicFile destination = new AtomicFile(configuration);
            FileOutputStream output = null;
            try {
                output = destination.startWrite();
                output.write(result.getJSONObject("value").toString().getBytes(StandardCharsets.UTF_8));
                destination.finishWrite(output);
            } catch (Exception error) {
                if (output != null) destination.failWrite(output);
                throw error;
            }
            return true;
        }
    }
}
