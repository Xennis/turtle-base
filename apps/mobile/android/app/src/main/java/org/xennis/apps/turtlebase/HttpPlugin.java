package org.xennis.apps.turtlebase;

import android.util.Base64;
import com.getcapacitor.JSArray;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.IOException;
import java.time.Duration;
import okhttp3.Call;
import okhttp3.Callback;
import okhttp3.Headers;
import okhttp3.MediaType;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.RequestBody;
import okhttp3.Response;
import okhttp3.internal.http.HttpMethod;
import org.json.JSONArray;
import org.json.JSONException;

/**
 * The app's Platform.fetch: requests from outside the web view, so CORS
 * doesn't apply. Bodies cross the bridge as base64, byte for byte both ways -
 * unlike CapacitorHttp, which sends binary only as base64 and hands back JSON
 * responses parsed. Whole bodies, like the desktop shell's IPC fetch.
 */
@CapacitorPlugin(name = "TurtleHttp")
public class HttpPlugin extends Plugin {

    // OkHttp's 10 s for reading is short for slow APIs (e.g. Open Library) and big downloads.
    private final OkHttpClient client = new OkHttpClient.Builder().readTimeout(Duration.ofSeconds(60)).build();

    @PluginMethod
    public void request(PluginCall call) {
        Request request;
        try {
            request = requestOf(call);
        } catch (Exception e) {
            call.reject(e.getMessage(), e);
            return;
        }
        // Asynchronous, so a long download doesn't hold up other plugin calls (e.g. SQL).
        client
            .newCall(request)
            .enqueue(
                new Callback() {
                    @Override
                    public void onFailure(Call ignored, IOException e) {
                        call.reject(e.getMessage(), e);
                    }

                    @Override
                    public void onResponse(Call ignored, Response response) {
                        try (response) {
                            JSArray headers = new JSArray();
                            for (int i = 0; i < response.headers().size(); i++) {
                                headers.put(new JSONArray().put(response.headers().name(i)).put(response.headers().value(i)));
                            }
                            JSObject result = new JSObject();
                            result.put("status", response.code());
                            result.put("statusText", response.message());
                            result.put("headers", headers);
                            result.put("body", Base64.encodeToString(response.body().bytes(), Base64.NO_WRAP));
                            call.resolve(result);
                        } catch (Exception e) {
                            call.reject(e.getMessage(), e);
                        }
                    }
                }
            );
    }

    private static Request requestOf(PluginCall call) throws JSONException {
        String method = call.getString("method", "GET");
        Headers.Builder headers = new Headers.Builder();
        JSArray pairs = call.getArray("headers", new JSArray());
        for (int i = 0; i < pairs.length(); i++) {
            JSONArray pair = pairs.getJSONArray(i);
            headers.add(pair.getString(0), pair.getString(1));
        }
        String encoded = call.getString("body");
        RequestBody body = null;
        if (encoded != null || HttpMethod.requiresRequestBody(method)) {
            String type = headers.get("Content-Type");
            byte[] bytes = encoded == null ? new byte[0] : Base64.decode(encoded, Base64.NO_WRAP);
            body = RequestBody.create(bytes, type == null ? null : MediaType.parse(type));
        }
        return new Request.Builder().url(call.getString("url")).headers(headers.build()).method(method, body).build();
    }
}
