import app.msime.client.NativeClient;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Comparator;
import java.util.regex.Pattern;

public final class NativeSmoke {
    static void success(String response) { if (!response.contains("\"ok\":true")) throw new AssertionError(response); }
    public static void main(String[] args) throws Exception {
        Path root = Files.createTempDirectory("msime-jni-");
        try {
            StringBuilder options = new StringBuilder("{\"api_version\":1,");
            for (String name : new String[] { "resources", "user_data", "cache", "dictionaries" }) {
                Path directory = Files.createDirectory(root.resolve(name + "-🌲"));
                String path = directory.toString().replace("\\", "\\\\").replace("\"", "\\\"");
                options.append('"').append(name).append("\":\"").append(path).append("\",");
            }
            options.append("\"preferences\":{\"scheme\":\"quanpin\",\"candidate_page_size\":5,\"learning\":false,\"chinese_punctuation\":true}}");
            String created = NativeClient.create(options.toString());
            success(created);
            var matcher = Pattern.compile("\"session\":(\\d+)").matcher(created);
            if (!matcher.find()) throw new AssertionError(created);
            long handle = Long.parseLong(matcher.group(1));
            success(NativeClient.focus(handle, true));
            success(NativeClient.character(handle, 'U', true));
            for (char value : "1f332".toCharArray()) success(NativeClient.character(handle, value, false));
            String committed = NativeClient.command(handle, 1);
            success(committed);
            if (!committed.contains("\"commit\":\"🌲\"")) throw new AssertionError(committed);
            success(NativeClient.destroy(handle));
            if (!NativeClient.view(handle).contains("\"ok\":false")) throw new AssertionError("stale handle accepted");
            System.out.println("JNI consumer: supplementary UTF-8 paths and input commit passed");
        } finally {
            try (var paths = Files.walk(root)) {
                for (Path path : paths.sorted(Comparator.reverseOrder()).toList()) Files.delete(path);
            }
        }
    }
}
