package org.xennis.apps.turtlebase

import android.accounts.Account
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.result.ActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import app.tauri.annotation.ActivityCallback
import app.tauri.annotation.Command
import app.tauri.annotation.InvokeArg
import app.tauri.annotation.TauriPlugin
import app.tauri.plugin.Invoke
import app.tauri.plugin.JSObject
import app.tauri.plugin.Plugin
import com.google.android.gms.auth.api.identity.AuthorizationClient
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.auth.api.identity.RevokeAccessRequest
import com.google.android.gms.common.api.Scope
import java.io.File

@InvokeArg
class AuthorizeArgs {
    var interactive: Boolean = false
}

@InvokeArg
class SignOutArgs {
    var account: String? = null
}

@InvokeArg
class SystemBarsArgs {
    var dark: Boolean = false
}

@InvokeArg
class OpenFileArgs {
    lateinit var path: String
    var mimeType: String? = null
}

@InvokeArg
class DisplayNameArgs {
    lateinit var uri: String
}

/**
 * What the app needs on Android beyond Tauri's own plugins (see
 * android_platform in the shell's android.rs): Google sign-in for Drive sync,
 * the system bars' style, opening a file with another app and the name of a
 * picked file.
 */
@TauriPlugin
class AndroidPlatformPlugin(private val activity: Activity) : Plugin(activity) {

    /**
     * An access token for the drive.file scope, through Play services'
     * AuthorizationClient: the first time it asks for an account and consent
     * (with `interactive`, else it rejects with NEEDS_CONSENT), after that it
     * hands out a valid token without asking. Needs only the Android OAuth
     * client (package name and signing certificate), no client id in the app.
     */
    @Command
    fun authorize(invoke: Invoke) {
        val interactive = invoke.parseArgs(AuthorizeArgs::class.java).interactive
        googleAuth()
            .authorize(AuthorizationRequest.builder().setRequestedScopes(DRIVE_SCOPES).build())
            .addOnSuccessListener { result ->
                val consent = result.pendingIntent
                when {
                    !result.hasResolution() -> resolveWith(invoke, result)
                    !interactive || consent == null ->
                        invoke.reject("Google Drive access needs the user's consent", "NEEDS_CONSENT")
                    else -> startIntentSenderForResult(
                        invoke,
                        IntentSenderRequest.Builder(consent.intentSender).build(),
                        "onConsent",
                    )
                }
            }
            .addOnFailureListener { error -> invoke.reject(error.message, error) }
    }

    @ActivityCallback
    fun onConsent(invoke: Invoke, result: ActivityResult) {
        if (result.resultCode != Activity.RESULT_OK) {
            invoke.reject("Google sign-in was cancelled", "CANCELLED")
            return
        }
        try {
            resolveWith(invoke, googleAuth().getAuthorizationResultFromIntent(result.data))
        } catch (error: Exception) {
            invoke.reject(error.message, error)
        }
    }

    /** Takes the app's access back, so connecting again asks for an account. */
    @Command
    fun signOut(invoke: Invoke) {
        val account = invoke.parseArgs(SignOutArgs::class.java).account
        if (account == null) {
            invoke.resolve()
            return
        }
        googleAuth()
            .revokeAccess(
                RevokeAccessRequest.builder().setAccount(Account(account, "com.google")).setScopes(DRIVE_SCOPES).build()
            )
            .addOnSuccessListener { invoke.resolve() }
            .addOnFailureListener { error -> invoke.reject(error.message, error) }
    }

    /** Light icons on the status and navigation bars for a dark page, dark ones for a light page. */
    @Command
    fun setSystemBarsStyle(invoke: Invoke) {
        val dark = invoke.parseArgs(SystemBarsArgs::class.java).dark
        activity.runOnUiThread {
            WindowCompat.getInsetsController(activity.window, activity.window.decorView).apply {
                isAppearanceLightStatusBars = !dark
                isAppearanceLightNavigationBars = !dark
            }
            invoke.resolve()
        }
    }

    /** Opens a file of the app's cache with the system's app for its type - shared through the FileProvider. */
    @Command
    fun openFile(invoke: Invoke) {
        val args = invoke.parseArgs(OpenFileArgs::class.java)
        try {
            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", File(args.path))
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, args.mimeType ?: activity.contentResolver.getType(uri))
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            activity.startActivity(Intent.createChooser(intent, null))
            invoke.resolve()
        } catch (error: ActivityNotFoundException) {
            invoke.reject("No app to open ${args.path}", error)
        } catch (error: IllegalArgumentException) {
            invoke.reject(error.message, error)
        }
    }

    /** The name a picked file (a content:// URI from the file picker) has for the user. */
    @Command
    fun displayName(invoke: Invoke) {
        val uri = Uri.parse(invoke.parseArgs(DisplayNameArgs::class.java).uri)
        val name = activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        invoke.resolve(JSObject().put("name", name ?: uri.lastPathSegment ?: "file"))
    }

    private fun googleAuth(): AuthorizationClient = Identity.getAuthorizationClient(activity)

    @Suppress("DEPRECATION") // The account only comes this way - needed to revoke the access again.
    private fun resolveWith(invoke: Invoke, result: AuthorizationResult) {
        val token = result.accessToken
        if (token == null) {
            invoke.reject("No access token from Google")
            return
        }
        val resolved = JSObject().put("accessToken", token)
        result.toGoogleSignInAccount()?.account?.name?.let { resolved.put("account", it) }
        invoke.resolve(resolved)
    }

    private companion object {
        val DRIVE_SCOPES = listOf(Scope("https://www.googleapis.com/auth/drive.file"))
    }
}
