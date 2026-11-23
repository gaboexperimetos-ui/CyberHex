#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

#include <cstring>

#include "flutter/generated_plugin_registrant.h"
#include "mpris_bridge.h"

// Runner de escritorio de CyberHex.
//
// Además de lo que trae la plantilla de Flutter, aquí se resuelve lo que solo
// puede hacer la capa nativa:
//  * **`%U` / abrir con…**: `G_APPLICATION_HANDLES_COMMAND_LINE` con instancia
//    única; la segunda ejecución reenvía su línea de comandos a la primera por
//    D-Bus y las rutas acaban en el canal `cyberhex/intent` (`onOpenFile`), o en
//    `getInitialFile` si la app acaba de arrancar.
//  * **Drag & drop de archivos y carpetas**: `GtkWindow` acepta
//    `text/uri-list`/`text/plain` y manda las rutas al canal
//    `cyberhex/desktop` (`onDropPaths`), porque Flutter no trae DnD de archivos.
//  * **MPRIS2** (`mpris_bridge.cc`): teclas multimedia, playerctl, widgets de
//    KDE/GNOME y Bluetooth de coche hablan D-Bus, no X11.
//  * **Siempre encima** (`setAlwaysOnTop`) y **notificaciones** de escritorio
//    (`GNotification`) a petición de Dart.
//
// Nada de esto reproduce audio: el motor sigue en Dart.

struct _MyApplication {
  GtkApplication parent_instance;

  char** dart_entrypoint_arguments;

  GtkWindow* window;
  FlMethodChannel* intent_channel;
  FlMethodChannel* desktop_channel;
  MprisBridge* mpris;

  /// Primer archivo de la línea de comandos, esperando `getInitialFile`.
  gchar* initial_path;
  /// Rutas extra del arranque (se mandan como drop al montar el canal).
  GPtrArray* initial_extras;

  gboolean always_on_top;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// ---------------------------------------------------------------------------
// Utilidades del canal
// ---------------------------------------------------------------------------

static void respond_with_value(FlMethodCall* call, FlValue* value) {
  g_autoptr(FlMethodResponse) response = FL_METHOD_RESPONSE(
      fl_method_success_response_new(value));
  fl_method_call_respond(call, response, nullptr);
}

static void respond_null(FlMethodCall* call) {
  respond_with_value(call, fl_value_new_null());
}

static FlValue* lookup(FlValue* map, const gchar* key) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  return fl_value_lookup_string(map, key);
}

static gboolean lookup_bool(FlValue* map, const gchar* key) {
  FlValue* value = lookup(map, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_BOOL &&
         fl_value_get_bool(value);
}

static gint64 lookup_int(FlValue* map, const gchar* key) {
  FlValue* value = lookup(map, key);
  if (value == nullptr ||
      fl_value_get_type(value) != FL_VALUE_TYPE_INT) {
    return 0;
  }
  return fl_value_get_int(value);
}

static const gchar* lookup_string(FlValue* map, const gchar* key) {
  FlValue* value = lookup(map, key);
  if (value == nullptr ||
      fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

/// Invoca un método de Dart sin esperar respuesta (resultado ignorado).
static void invoke_no_result(FlMethodChannel* channel,
                             const gchar* method,
                             FlValue* arguments) {
  if (channel == nullptr) {
    return;
  }
  fl_method_channel_invoke_method(channel, method, arguments, nullptr, nullptr,
                                  nullptr);
}

// ---------------------------------------------------------------------------
// Dart → nativo
// ---------------------------------------------------------------------------

/// `cyberhex/intent`: `getInitialFile` (el archivo con el que se abrió la app).
static void intent_method_call_cb(FlMethodChannel* channel,
                                  FlMethodCall* call,
                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* name = fl_method_call_get_name(call);

  if (g_strcmp0(name, "getInitialFile") == 0) {
    respond_with_value(
        call, fl_value_new_string(self->initial_path != nullptr
                                      ? self->initial_path
                                      : ""));
    // Solo se entrega una vez: si se repite, Dart volvería a abrir la pista.
    g_clear_pointer(&self->initial_path, g_free);
    return;
  }

  fl_method_call_respond_not_implemented(call, nullptr);
}

/// `cyberhex/desktop`: MPRIS, siempre encima y notificaciones.
static void desktop_method_call_cb(FlMethodChannel* channel,
                                   FlMethodCall* call,
                                   gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* name = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);

  if (g_strcmp0(name, "setAlwaysOnTop") == 0) {
    const gboolean enabled = args != nullptr &&
                             fl_value_get_type(args) == FL_VALUE_TYPE_BOOL &&
                             fl_value_get_bool(args);
    self->always_on_top = enabled;
    if (self->window != nullptr) {
      gtk_window_set_keep_above(self->window, enabled ? TRUE : FALSE);
    }
    respond_null(call);
    return;
  }

  if (g_strcmp0(name, "notifyTrack") == 0) {
    const gchar* title = lookup_string(args, "title");
    const gchar* body = lookup_string(args, "body");
    if (title != nullptr && *title != '\0') {
      g_autoptr(GNotification) notification = g_notification_new(title);
      if (body != nullptr && *body != '\0') {
        g_notification_set_body(notification, body);
      }
      g_notification_set_icon(notification,
                              g_themed_icon_new("audio-x-generic"));
      // Sin «app.raise» registrada, la notificación no es clicable.
      g_notification_set_default_action(notification, "app.raise");
      g_application_send_notification(G_APPLICATION(self), "track",
                                      notification);
    }
    respond_null(call);
    return;
  }

  if (g_strcmp0(name, "updateMetadata") == 0) {
    mpris_bridge_set_metadata(self->mpris, lookup_string(args, "title"),
                              lookup_string(args, "artist"),
                              lookup_string(args, "album"),
                              lookup_int(args, "durationMicros"));
    respond_null(call);
    return;
  }

  if (g_strcmp0(name, "updateState") == 0) {
    const gint64 position_us = lookup_int(args, "positionMicros");
    mpris_bridge_set_playback(self->mpris, lookup_bool(args, "playing"),
                              position_us);
    mpris_bridge_set_loop_and_shuffle(self->mpris,
                                      lookup_string(args, "loop"),
                                      lookup_bool(args, "shuffle"));
    FlValue* volume = lookup(args, "volume");
    if (volume != nullptr && fl_value_get_type(volume) == FL_VALUE_TYPE_FLOAT) {
      mpris_bridge_set_volume(self->mpris, fl_value_get_float(volume));
    }
    respond_null(call);
    return;
  }

  if (g_strcmp0(name, "notifySeek") == 0) {
    mpris_bridge_emit_seeked(self->mpris, lookup_int(args, "positionMicros"));
    respond_null(call);
    return;
  }

  fl_method_call_respond_not_implemented(call, nullptr);
}

// ---------------------------------------------------------------------------
// MPRIS → nativo → Dart
// ---------------------------------------------------------------------------

static void send_string_command(MyApplication* self,
                                const gchar* method,
                                const gchar* value) {
  g_autoptr(FlValue) argument =
      fl_value_new_string(value != nullptr ? value : "");
  invoke_no_result(self->desktop_channel, method, argument);
}

static void send_number_command(MyApplication* self,
                                const gchar* method,
                                const gchar* value) {
  const gdouble number = value != nullptr ? g_ascii_strtod(value, nullptr) : 0.0;
  g_autoptr(FlValue) argument = fl_value_new_float(number);
  invoke_no_result(self->desktop_channel, method, argument);
}

static void open_path(MyApplication* self, const gchar* path) {
  if (path == nullptr || *path == '\0') {
    return;
  }
  if (self->intent_channel == nullptr) {
    // Dart todavía no montó su lado: se guarda para `getInitialFile`.
    g_free(self->initial_path);
    self->initial_path = g_strdup(path);
    return;
  }
  g_autoptr(FlValue) argument = fl_value_new_string(path);
  invoke_no_result(self->intent_channel, "onOpenFile", argument);
}

static void send_drop_paths(MyApplication* self, GPtrArray* paths) {
  if (paths == nullptr || paths->len == 0) {
    return;
  }
  g_autoptr(FlValue) list = fl_value_new_list();
  for (guint i = 0; i < paths->len; i++) {
    fl_value_append_take(list,
                         fl_value_new_string(static_cast<gchar*>(paths->pdata[i])));
  }
  if (self->desktop_channel == nullptr) {
    // Se guardan para cuando Dart pregunte (canal recién montado).
    for (guint i = 0; i < paths->len; i++) {
      g_ptr_array_add(self->initial_extras,
                      g_strdup(static_cast<gchar*>(paths->pdata[i])));
    }
    return;
  }
  invoke_no_result(self->desktop_channel, "onDropPaths", list);
}

static void dispatch_paths(MyApplication* self,
                           GPtrArray* paths,
                           gboolean from_drop) {
  if (paths == nullptr || paths->len == 0) {
    return;
  }
  if (from_drop) {
    send_drop_paths(self, paths);
    return;
  }
  open_path(self, static_cast<const gchar*>(paths->pdata[0]));
  if (paths->len > 1) {
    g_autoptr(GPtrArray) rest =
        g_ptr_array_new_with_free_func(g_free);
    for (guint i = 1; i < paths->len; i++) {
      g_ptr_array_add(rest,
                      g_strdup(static_cast<gchar*>(paths->pdata[i])));
    }
    send_drop_paths(self, rest);
  }
}

static void on_mpris_command(const gchar* command, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (command == nullptr) {
    return;
  }

  if (g_strcmp0(command, "raise") == 0) {
    if (self->window != nullptr) {
      gtk_window_present(self->window);
    }
    return;
  }
  if (g_strcmp0(command, "quit") == 0) {
    g_application_quit(G_APPLICATION(self));
    return;
  }
  if (g_str_has_prefix(command, "open:")) {
    const gchar* uri = command + strlen("open:");
    g_autofree gchar* path = g_str_has_prefix(uri, "file://")
                                 ? g_filename_from_uri(uri, nullptr, nullptr)
                                 : g_strdup(uri);
    open_path(self, path);
    return;
  }

  g_auto(GStrv) parts = g_strsplit(command, ":", 2);
  const gchar* name = parts[0];
  const gchar* argument = parts[1];

  if (g_strcmp0(name, "seek") == 0) {
    send_number_command(self, "seek", argument);
  } else if (g_strcmp0(name, "seekrel") == 0) {
    send_number_command(self, "seekRelative", argument);
  } else if (g_strcmp0(name, "volume") == 0) {
    send_number_command(self, "setVolume", argument);
  } else if (g_strcmp0(name, "loop") == 0) {
    send_string_command(self, "setLoop", argument);
  } else if (g_strcmp0(name, "shuffle") == 0) {
    g_autoptr(FlValue) value =
        fl_value_new_bool(g_strcmp0(argument, "1") == 0);
    invoke_no_result(self->desktop_channel, "setShuffle", value);
  } else if (g_strcmp0(name, "play") == 0 || g_strcmp0(name, "pause") == 0 ||
             g_strcmp0(name, "toggle") == 0 || g_strcmp0(name, "stop") == 0 ||
             g_strcmp0(name, "next") == 0 ||
             g_strcmp0(name, "previous") == 0) {
    invoke_no_result(self->desktop_channel, name, nullptr);
  } else {
    g_debug("MPRIS: orden desconocida '%s'", command);
  }
}

// ---------------------------------------------------------------------------
// Drag & drop
// ---------------------------------------------------------------------------

static void on_drag_data_received(GtkWidget* widget,
                                  GdkDragContext* context,
                                  gint x,
                                  gint y,
                                  GtkSelectionData* data,
                                  guint info,
                                  guint time,
                                  gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  (void)widget;
  (void)x;
  (void)y;
  (void)info;

  gboolean handled = FALSE;
  g_auto(GStrv) uris = gtk_selection_data_get_uris(data);
  g_autoptr(GPtrArray) paths = g_ptr_array_new_with_free_func(g_free);

  if (uris != nullptr) {
    for (gint i = 0; uris[i] != nullptr; i++) {
      g_autofree gchar* path = g_filename_from_uri(uris[i], nullptr, nullptr);
      if (path != nullptr) {
        g_ptr_array_add(paths, g_strdup(path));
      }
    }
  }
  if (paths->len == 0) {
    // Algunos gestores mandan la ruta en texto plano.
    const guchar* text = gtk_selection_data_get_text(data);
    if (text != nullptr) {
      g_auto(GStrv) lines = g_strsplit(reinterpret_cast<const gchar*>(text),
                                       "\n", -1);
      for (gint i = 0; lines[i] != nullptr; i++) {
        g_strstrip(lines[i]);
        if (lines[i][0] != '\0') {
          g_ptr_array_add(paths, g_strdup(lines[i]));
        }
      }
    }
  }

  if (paths->len > 0) {
    handled = TRUE;
    dispatch_paths(self, paths, TRUE);
    if (self->window != nullptr) {
      gtk_window_present(self->window);
    }
  }

  gtk_drag_finish(context, handled, FALSE, time);
}

// ---------------------------------------------------------------------------
// Ciclo de vida de GApplication
// ---------------------------------------------------------------------------

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static void on_raise_action(GSimpleAction* action,
                            GVariant* parameter,
                            gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  (void)action;
  (void)parameter;
  if (self->window != nullptr) {
    gtk_window_present(self->window);
  }
}

static void attach_channels(MyApplication* self, FlView* view) {
  FlEngine* engine = fl_view_get_engine(view);
  if (engine == nullptr) {
    return;
  }
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();

  self->intent_channel =
      fl_method_channel_new(messenger, "cyberhex/intent", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->intent_channel, intent_method_call_cb, self, nullptr);

  self->desktop_channel = fl_method_channel_new(messenger, "cyberhex/desktop",
                                                FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->desktop_channel, desktop_method_call_cb, self, nullptr);

  // Rutas extra que llegaron con el arranque (segundo, tercer archivo…).
  if (self->initial_extras != nullptr && self->initial_extras->len > 0) {
    g_autoptr(GPtrArray) extras = g_ptr_array_new_with_free_func(g_free);
    for (guint i = 0; i < self->initial_extras->len; i++) {
      g_ptr_array_add(extras,
                      g_strdup(static_cast<gchar*>(self->initial_extras->pdata[i])));
    }
    send_drop_paths(self, extras);
    g_ptr_array_set_size(self->initial_extras, 0);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  if (self->window != nullptr) {
    // Segunda activación (icono del escritorio, `%U` sin archivos…).
    gtk_window_present(self->window);
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  gtk_window_set_default_size(window, 1000, 780);
  gtk_window_set_title(window, "CyberHex");

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  attach_channels(self, view);

  if (self->always_on_top) {
    gtk_window_set_keep_above(window, TRUE);
  }

  // Drop de archivos y carpetas del escritorio hacia la app.
  static const GtkTargetEntry kDropTargets[] = {
      {const_cast<gchar*>("text/uri-list"), 0, 0},
      {const_cast<gchar*>("text/plain"), 0, 1},
  };
  gtk_drag_dest_set(GTK_WIDGET(window), GTK_DEST_DEFAULT_ALL, kDropTargets, 2,
                    GDK_ACTION_COPY);
  g_signal_connect(window, "drag-data-received",
                   G_CALLBACK(on_drag_data_received), self);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::command-line (flags: HANDLES_COMMAND_LINE).
static gint my_application_command_line(GApplication* application,
                                        GApplicationCommandLine* command_line) {
  MyApplication* self = MY_APPLICATION(application);

  gint argc = 0;
  g_auto(GStrv) argv =
      g_application_command_line_get_arguments(command_line, &argc);

  g_autoptr(GPtrArray) paths = g_ptr_array_new_with_free_func(g_free);
  for (gint i = 1; i < argc; i++) {
    if (argv[i][0] == '-') {
      continue;  // La app no tiene opciones propias.
    }
    g_autoptr(GFile) file = g_file_new_for_commandline_arg(argv[i]);
    g_autofree gchar* path = g_file_get_path(file);
    if (path != nullptr && *path != '\0') {
      g_ptr_array_add(paths, g_strdup(path));
    }
  }

  // Sin el nombre del binario, como espera `fl_dart_project_*`.
  self->dart_entrypoint_arguments = g_strdupv(argv + 1);

  if (self->window == nullptr) {
    // Arranque en frío: la primera ruta espera a `getInitialFile`; el resto se
    // manda como drop al montar el canal.
    if (paths->len > 0) {
      g_free(self->initial_path);
      self->initial_path = g_strdup(static_cast<gchar*>(paths->pdata[0]));
      for (guint i = 1; i < paths->len; i++) {
        g_ptr_array_add(self->initial_extras,
                        g_strdup(static_cast<gchar*>(paths->pdata[i])));
      }
    }
    g_application_activate(application);
  } else {
    // Instancia ya abierta: se reenvía lo que pidió el segundo proceso.
    dispatch_paths(self, paths, FALSE);
    gtk_window_present(self->window);
  }

  g_application_command_line_set_exit_status(command_line, 0);
  return 0;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);

  static const GActionEntry kActions[] = {
      {"raise", on_raise_action, nullptr, nullptr, nullptr},
  };
  g_action_map_add_action_entries(G_ACTION_MAP(self), kActions, 1, self);

  self->mpris = mpris_bridge_new(on_mpris_command, self);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  if (self->mpris != nullptr) {
    mpris_bridge_free(self->mpris);
    self->mpris = nullptr;
  }

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);

  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_pointer(&self->initial_path, g_free);
  g_clear_pointer(&self->initial_extras, g_ptr_array_unref);
  g_clear_object(&self->intent_channel);
  g_clear_object(&self->desktop_channel);

  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->initial_extras = g_ptr_array_new_with_free_func(g_free);
  self->always_on_top = FALSE;
}

MyApplication* my_application_new() {
  g_set_prgname(APPLICATION_ID);

  // HANDLES_COMMAND_LINE + id de aplicación único: la segunda ejecución
  // («Abrir con CyberHex» con la app ya abierta) se reenvía a la primera por
  // D-Bus en vez de abrir un proceso gemelo sin ventana.
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_COMMAND_LINE,
                                     nullptr));
}
