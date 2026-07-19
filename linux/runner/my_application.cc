#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // Restyles the header bar at runtime to match the in-app theme -
  // fed by the "turtle_base/window" method channel (see
  // window_chrome.dart), since GTK can't know the Flutter theme.
  GtkCssProvider* theme_css_provider;
  FlMethodChannel* window_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Handles method calls on the "turtle_base/window" channel. Currently
// only setTitleBarColors, which recolors the GTK header bar so it
// blends with the app's background instead of the desktop theme's gray.
static void window_channel_method_cb(FlMethodChannel* channel,
                                     FlMethodCall* method_call,
                                     gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (g_strcmp0(fl_method_call_get_name(method_call), "setTitleBarColors") !=
      0) {
    fl_method_call_respond_not_implemented(method_call, nullptr);
    return;
  }
  if (self->theme_css_provider == nullptr) {
    // No header bar on this window manager (see my_application_activate)
    // - nothing to restyle.
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(method_call);
  FlValue* background_value =
      fl_value_lookup_string(args, "background");
  FlValue* foreground_value =
      fl_value_lookup_string(args, "foreground");
  const gchar* background =
      background_value != nullptr ? fl_value_get_string(background_value)
                                  : nullptr;
  const gchar* foreground =
      foreground_value != nullptr ? fl_value_get_string(foreground_value)
                                  : nullptr;
  // Parse before splicing into CSS - rejects anything that isn't a
  // plain color.
  GdkRGBA parsed;
  if (background == nullptr || foreground == nullptr ||
      !gdk_rgba_parse(&parsed, background) ||
      !gdk_rgba_parse(&parsed, foreground)) {
    fl_method_call_respond_error(method_call, "bad-args",
                                 "expected parseable background/foreground",
                                 nullptr, nullptr);
    return;
  }
  g_autofree gchar* css = g_strdup_printf(
      "headerbar { background: %s; color: %s; }", background, foreground);
  gtk_css_provider_load_from_data(self->theme_css_provider, css, -1, nullptr);
  fl_method_call_respond_success(method_call, nullptr, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  // Window title for the taskbar/Alt-Tab only - the header bar itself
  // stays blank (an empty custom title widget below suppresses the
  // fallback to this title), matching the app's own chrome-less look.
  gtk_window_set_title(window, "Turtle Base");
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_custom_title(header_bar, gtk_label_new(""));
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));

    // Slim, flat header bar: the window buttons dictate the height
    // instead of GTK's default chunky padding, and border/shadow are
    // dropped so it visually merges with the app content below. The
    // background/foreground colors are applied separately via
    // theme_css_provider once the Dart side reports the app theme.
    GtkCssProvider* base_css = gtk_css_provider_new();
    gtk_css_provider_load_from_data(
        base_css,
        "headerbar { min-height: 0px; padding: 2px 6px; border: none; "
        "box-shadow: none; }",
        -1, nullptr);
    gtk_style_context_add_provider_for_screen(
        gtk_window_get_screen(window), GTK_STYLE_PROVIDER(base_css),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_unref(base_css);

    self->theme_css_provider = gtk_css_provider_new();
    gtk_style_context_add_provider_for_screen(
        gtk_window_get_screen(window),
        GTK_STYLE_PROVIDER(self->theme_css_provider),
        GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "turtle_base/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->window_channel, window_channel_method_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->theme_css_provider);
  g_clear_object(&self->window_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
