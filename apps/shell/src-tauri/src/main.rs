fn main() {
    // WebKitGTK's DMA-BUF renderer draws the text of scrolled areas blurry (seen on GNOME, Wayland) - its
    // shared-memory one doesn't. Set before WebKit starts; an explicit setting of the user's stays.
    #[cfg(target_os = "linux")]
    if std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none() {
        // SAFETY: no other thread runs yet that could read the environment.
        unsafe { std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1") };
    }
    turtle_base_lib::run();
}
