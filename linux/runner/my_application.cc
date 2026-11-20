#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  // Native window helpers exposed to Dart (see window_kiosk_linux.dart).
  FlMethodChannel* window_channel;
  GtkWindow* window;       // not owned; the GtkApplication owns the window
  guint inhibit_cookie;    // 0 = no sleep inhibit active
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Must match the icon name installed under hicolor/*/apps/ by the .deb.
static const char kIconName[] = "alochi-monitoring";

// Window icon: prefer the themed icon (installed .deb); fall back to the PNG
// shipped next to the executable (tar.gz, which installs no icon theme file).
static void set_window_icon(GtkWindow* window) {
  GtkIconTheme* theme = gtk_icon_theme_get_default();
  if (gtk_icon_theme_has_icon(theme, kIconName)) {
    gtk_window_set_icon_name(window, kIconName);
    return;
  }
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe == nullptr) return;
  g_autofree gchar* dir = g_path_get_dirname(exe);
  g_autofree gchar* png = g_build_filename(dir, "alochi-monitoring.png", nullptr);
  if (g_file_test(png, G_FILE_TEST_EXISTS)) {
    gtk_window_set_icon_from_file(window, png, nullptr);
  }
}

// Dart -> native window helpers on channel "uz.alochi/window".
static void window_method_call_cb(FlMethodChannel* channel,
                                  FlMethodCall* method_call,
                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  GtkWindow* window = self->window;
  g_autoptr(GError) error = nullptr;

  if (window == nullptr) {
    fl_method_call_respond_error(method_call, "no_window", "No window", nullptr,
                                 &error);
    return;
  }

  if (g_strcmp0(method, "maximize") == 0) {
    gtk_window_maximize(window);
    fl_method_call_respond_success(method_call, nullptr, &error);
  } else if (g_strcmp0(method, "toggleFullscreen") == 0) {
    GdkWindow* gdk = gtk_widget_get_window(GTK_WIDGET(window));
    gboolean full =
        gdk != nullptr && (gdk_window_get_state(gdk) & GDK_WINDOW_STATE_FULLSCREEN);
    if (full) {
      gtk_window_unfullscreen(window);
    } else {
      gtk_window_fullscreen(window);
    }
    g_autoptr(FlValue) result = fl_value_new_bool(!full);
    fl_method_call_respond_success(method_call, result, &error);
  } else if (g_strcmp0(method, "present") == 0) {
    gtk_window_present(window);
    fl_method_call_respond_success(method_call, nullptr, &error);
  } else if (g_strcmp0(method, "isActive") == 0) {
    g_autoptr(FlValue) result = fl_value_new_bool(gtk_window_is_active(window));
    fl_method_call_respond_success(method_call, result, &error);
  } else if (g_strcmp0(method, "inhibitSleep") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    gboolean on = args != nullptr &&
                  fl_value_get_type(args) == FL_VALUE_TYPE_BOOL &&
                  fl_value_get_bool(args);
    GtkApplication* app = GTK_APPLICATION(self);
    if (on && self->inhibit_cookie == 0) {
      self->inhibit_cookie = gtk_application_inhibit(
          app, window,
          static_cast<GtkApplicationInhibitFlags>(GTK_APPLICATION_INHIBIT_IDLE |
                                                  GTK_APPLICATION_INHIBIT_SUSPEND),
          "Student test in progress");
    } else if (!on && self->inhibit_cookie != 0) {
      gtk_application_uninhibit(app, self->inhibit_cookie);
      self->inhibit_cookie = 0;
    }
    g_autoptr(FlValue) result = fl_value_new_bool(self->inhibit_cookie != 0);
    fl_method_call_respond_success(method_call, result, &error);
  } else {
    fl_method_call_respond_not_implemented(method_call, &error);
  }
  if (error != nullptr) {
    g_warning("window channel response failed: %s", error->message);
  }
}

// Pushes focus changes to Dart so isForegroundOurs() can stay synchronous.
static void active_changed_cb(GObject* window, GParamSpec*, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->window_channel == nullptr) return;
  g_autoptr(FlValue) active =
      fl_value_new_bool(gtk_window_is_active(GTK_WINDOW(window)));
  fl_method_channel_invoke_method(self->window_channel, "activeChanged", active,
                                  nullptr, nullptr, nullptr);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // Single instance: a second launch is forwarded here by GApplication (over
  // D-Bus) — raise the existing window instead of building another one.
  GList* existing = gtk_application_get_windows(GTK_APPLICATION(application));
  if (existing != nullptr) {
    gtk_window_present(GTK_WINDOW(existing->data));
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  set_window_icon(window);

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
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Alochi Monitoring");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Alochi Monitoring");
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
      "uz.alochi/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->window_channel,
                                            window_method_call_cb, self, nullptr);
  g_signal_connect(window, "notify::is-active", G_CALLBACK(active_changed_cb),
                   self);

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

  // Unique application (no G_APPLICATION_NON_UNIQUE): a second launch is
  // forwarded to the running instance, which presents its window. Without a
  // D-Bus session GApplication silently falls back to a normal primary.
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     static_cast<GApplicationFlags>(0), nullptr));
}
