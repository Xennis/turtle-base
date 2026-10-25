package org.xennis.apps.turtlebase;

import android.accounts.Account;
import android.app.Activity;
import androidx.activity.result.ActivityResult;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.IntentSenderRequest;
import androidx.activity.result.contract.ActivityResultContracts;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.google.android.gms.auth.api.identity.AuthorizationClient;
import com.google.android.gms.auth.api.identity.AuthorizationRequest;
import com.google.android.gms.auth.api.identity.AuthorizationResult;
import com.google.android.gms.auth.api.identity.Identity;
import com.google.android.gms.auth.api.identity.RevokeAccessRequest;
import com.google.android.gms.common.api.Scope;
import java.util.List;

/**
 * Access to the user's Google Drive for the sync (the drive.file scope),
 * through Play services' AuthorizationClient: the first time it asks for an
 * account and consent, after that it hands out a valid access token without
 * asking - Play services keeps and refreshes it. Needs only the Android OAuth
 * client (package name and signing certificate), no client id in the app.
 */
@CapacitorPlugin(name = "TurtleGoogleAuth")
public class GoogleAuthPlugin extends Plugin {

    private static final List<Scope> SCOPES = List.of(new Scope("https://www.googleapis.com/auth/drive.file"));

    private ActivityResultLauncher<IntentSenderRequest> consent;
    private PluginCall waitingForConsent;

    @Override
    public void load() {
        // Registered while the activity is being created - later isn't allowed.
        consent = getActivity().registerForActivityResult(new ActivityResultContracts.StartIntentSenderForResult(), this::onConsent);
    }

    /** An access token; with `interactive`, asks for account and consent where needed, else rejects with NEEDS_CONSENT. */
    @PluginMethod
    public void authorize(PluginCall call) {
        boolean interactive = call.getBoolean("interactive", false);
        client()
            .authorize(AuthorizationRequest.builder().setRequestedScopes(SCOPES).build())
            .addOnSuccessListener((result) -> {
                if (!result.hasResolution()) {
                    resolveWith(call, result);
                } else if (!interactive || result.getPendingIntent() == null) {
                    call.reject("Google Drive access needs the user's consent", "NEEDS_CONSENT");
                } else if (waitingForConsent != null) {
                    call.reject("Another sign-in is in progress");
                } else {
                    waitingForConsent = call;
                    consent.launch(new IntentSenderRequest.Builder(result.getPendingIntent().getIntentSender()).build());
                }
            })
            .addOnFailureListener((e) -> call.reject(e.getMessage(), e));
    }

    /** Takes the app's access back, so connecting again asks for an account. */
    @PluginMethod
    public void signOut(PluginCall call) {
        String account = call.getString("account");
        if (account == null) {
            call.resolve();
            return;
        }
        client()
            .revokeAccess(RevokeAccessRequest.builder().setAccount(new Account(account, "com.google")).setScopes(SCOPES).build())
            .addOnSuccessListener((unused) -> call.resolve())
            .addOnFailureListener((e) -> call.reject(e.getMessage(), e));
    }

    private void onConsent(ActivityResult activityResult) {
        PluginCall call = waitingForConsent;
        waitingForConsent = null;
        if (call == null) return;
        if (activityResult.getResultCode() != Activity.RESULT_OK) {
            call.reject("Google sign-in was cancelled", "CANCELLED");
            return;
        }
        try {
            resolveWith(call, client().getAuthorizationResultFromIntent(activityResult.getData()));
        } catch (Exception e) {
            call.reject(e.getMessage(), e);
        }
    }

    @SuppressWarnings("deprecation") // The account only comes this way - needed to revoke the access again.
    private static void resolveWith(PluginCall call, AuthorizationResult result) {
        if (result.getAccessToken() == null) {
            call.reject("No access token from Google");
            return;
        }
        JSObject resolved = new JSObject();
        resolved.put("accessToken", result.getAccessToken());
        var signedIn = result.toGoogleSignInAccount();
        if (signedIn != null && signedIn.getAccount() != null) resolved.put("account", signedIn.getAccount().name);
        call.resolve(resolved);
    }

    private AuthorizationClient client() {
        return Identity.getAuthorizationClient(getContext());
    }
}
