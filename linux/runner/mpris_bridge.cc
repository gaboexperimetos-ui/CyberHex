#include "mpris_bridge.h"

#include <gio/gio.h>

// MPRIS 2.2, sin dependencias más allá de GIO (que ya entra con GTK).
//
// Registro: `org.mpris.MediaPlayer2.cyberhex` en la sesión de D-Bus, con un
// único objeto `/org/mpris/MediaPlayer2` que expone dos interfaces. GDBus añade
// solo la introspección y `org.freedesktop.DBus.Properties` para los objetos
// registrados, así que las propiedades se leen y escriben por el camino
// estándar y las señales se emiten a mano con `emit_changed()`.

static const gchar kObjectPath[] = "/org/mpris/MediaPlayer2";
static const gchar kBusName[] = "org.mpris.MediaPlayer2.cyberhex";
static const gchar kTrackPath[] = "/com/gaboexperimetos/cyberhex/track/current";

static const gchar kRootXml[] =
    "<node>"
    "  <interface name='org.mpris.MediaPlayer2'>"
    "    <method name='Raise'/>"
    "    <method name='Quit'/>"
    "    <property name='Identity' type='s' access='read'/>"
    "    <property name='DesktopEntry' type='s' access='read'/>"
    "    <property name='CanQuit' type='b' access='read'/>"
    "    <property name='CanRaise' type='b' access='read'/>"
    "    <property name='HasTrackList' type='b' access='read'/>"
    "    <property name='SupportedUriSchemes' type='as' access='read'/>"
    "    <property name='SupportedMimeTypes' type='as' access='read'/>"
    "  </interface>"
    "</node>";

static const gchar kPlayerXml[] =
    "<node>"
    "  <interface name='org.mpris.MediaPlayer2.Player'>"
    "    <method name='Next'/>"
    "    <method name='Previous'/>"
    "    <method name='Pause'/>"
    "    <method name='PlayPause'/>"
    "    <method name='Stop'/>"
    "    <method name='Play'/>"
    "    <method name='Seek'>"
    "      <arg name='Offset' type='x' direction='in'/>"
    "    </method>"
    "    <method name='SetPosition'>"
    "      <arg name='TrackId' type='o' direction='in'/>"
    "      <arg name='Position' type='x' direction='in'/>"
    "    </method>"
    "    <method name='OpenUri'>"
    "      <arg name='Uri' type='s' direction='in'/>"
    "    </method>"
    "    <signal name='Seeked'>"
    "      <arg name='Position' type='x'/>"
    "    </signal>"
    "    <property name='PlaybackStatus' type='s' access='read'/>"
    "    <property name='LoopStatus' type='s' access='readwrite'/>"
    "    <property name='Rate' type='d' access='read'/>"
    "    <property name='Shuffle' type='b' access='readwrite'/>"
    "    <property name='Metadata' type='a{sv}' access='read'/>"
    "    <property name='Volume' type='d' access='readwrite'/>"
    "    <property name='Position' type='x' access='read'/>"
    "    <property name='MinimumRate' type='d' access='read'/>"
    "    <property name='MaximumRate' type='d' access='read'/>"
    "    <property name='CanGoNext' type='b' access='read'/>"
    "    <property name='CanGoPrevious' type='b' access='read'/>"
    "    <property name='CanPlay' type='b' access='read'/>"
    "    <property name='CanPause' type='b' access='read'/>"
    "    <property name='CanSeek' type='b' access='read'/>"
    "    <property name='CanControl' type='b' access='read'/>"
    "  </interface>"
    "</node>";

struct _MprisBridge {
  MprisCommandCallback on_command;
  gpointer user_data;

  GDBusConnection* connection;
  guint owner_id;
  guint root_registration;
  guint player_registration;

  gchar* title;
  gchar* artist;
  gchar* album;
  gchar* loop_status;
  gboolean shuffle;
  gboolean playing;
  gboolean has_track;
  gdouble volume;
  gint64 duration_us;
  gint64 position_us;
};

// ---------------------------------------------------------------------------
// Señales
// ---------------------------------------------------------------------------

static void emit_changed(MprisBridge* self,
                         const gchar* interface_name,
                         GVariant* changed) {
  if (self->connection == NULL) {
    g_variant_unref(g_variant_ref_sink(changed));
    return;
  }
  g_dbus_connection_emit_signal(
      self->connection, NULL, kObjectPath, "org.freedesktop.DBus.Properties",
      "PropertiesChanged",
      g_variant_new("(s@a{sv}@as)", interface_name, changed,
                    g_variant_new_strv(NULL, 0)),
      NULL);
}

static void emit_metadata(MprisBridge* self) {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&builder, "{sv}", "mpris:trackid",
                        g_variant_new_object_path(kTrackPath));
  if (self->title != NULL && *self->title != '\0') {
    g_variant_builder_add(&builder, "{sv}", "xesam:title",
                          g_variant_new_string(self->title));
  }
  if (self->artist != NULL && *self->artist != '\0') {
    const gchar* artists[] = {self->artist, NULL};
    g_variant_builder_add(&builder, "{sv}", "xesam:artist",
                          g_variant_new_strv(artists, -1));
  }
  if (self->album != NULL && *self->album != '\0') {
    g_variant_builder_add(&builder, "{sv}", "xesam:album",
                          g_variant_new_string(self->album));
  }
  if (self->duration_us > 0) {
    g_variant_builder_add(&builder, "{sv}", "mpris:length",
                          g_variant_new_int64(self->duration_us));
  }
  emit_changed(self, "org.mpris.MediaPlayer2.Player",
               g_variant_builder_end(&builder));
}

static void emit_playback(MprisBridge* self) {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(
      &builder, "{sv}", "PlaybackStatus",
      g_variant_new_string(self->playing
                               ? "Playing"
                               : (self->has_track ? "Paused" : "Stopped")));
  g_variant_builder_add(&builder, "{sv}", "Position",
                        g_variant_new_int64(self->position_us));
  emit_changed(self, "org.mpris.MediaPlayer2.Player",
               g_variant_builder_end(&builder));
}

static void notify_command(MprisBridge* self, const gchar* command) {
  if (self->on_command != NULL) {
    self->on_command(command, self->user_data);
  }
}

// ---------------------------------------------------------------------------
// Propiedades
// ---------------------------------------------------------------------------

static GVariant* build_metadata(MprisBridge* self) {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&builder, "{sv}", "mpris:trackid",
                        g_variant_new_object_path(kTrackPath));
  if (self->title != NULL && *self->title != '\0') {
    g_variant_builder_add(&builder, "{sv}", "xesam:title",
                          g_variant_new_string(self->title));
  }
  if (self->artist != NULL && *self->artist != '\0') {
    const gchar* artists[] = {self->artist, NULL};
    g_variant_builder_add(&builder, "{sv}", "xesam:artist",
                          g_variant_new_strv(artists, -1));
  }
  if (self->album != NULL && *self->album != '\0') {
    g_variant_builder_add(&builder, "{sv}", "xesam:album",
                          g_variant_new_string(self->album));
  }
  if (self->duration_us > 0) {
    g_variant_builder_add(&builder, "{sv}", "mpris:length",
                          g_variant_new_int64(self->duration_us));
  }
  return g_variant_builder_end(&builder);
}

static GVariant* on_get_property(GDBusConnection* connection,
                                 const gchar* sender,
                                 const gchar* object_path,
                                 const gchar* interface_name,
                                 const gchar* property_name,
                                 GError** error,
                                 gpointer user_data) {
  MprisBridge* self = static_cast<MprisBridge*>(user_data);
  (void)connection;
  (void)sender;
  (void)object_path;
  (void)error;

  if (g_strcmp0(interface_name, "org.mpris.MediaPlayer2") == 0) {
    if (g_strcmp0(property_name, "Identity") == 0) {
      return g_variant_new_string("CyberHex");
    }
    if (g_strcmp0(property_name, "DesktopEntry") == 0) {
      return g_variant_new_string("cyberhex");
    }
    if (g_strcmp0(property_name, "CanQuit") == 0) {
      return g_variant_new_boolean(TRUE);
    }
    if (g_strcmp0(property_name, "CanRaise") == 0) {
      return g_variant_new_boolean(TRUE);
    }
    if (g_strcmp0(property_name, "HasTrackList") == 0) {
      return g_variant_new_boolean(FALSE);
    }
    if (g_strcmp0(property_name, "SupportedUriSchemes") == 0) {
      const gchar* schemes[] = {"file", NULL};
      return g_variant_new_strv(schemes, -1);
    }
    if (g_strcmp0(property_name, "SupportedMimeTypes") == 0) {
      const gchar* mimes[] = {"audio/mpeg",  "audio/flac", "audio/x-wav",
                              "audio/ogg",   "audio/opus", "audio/mp4",
                              "audio/aac",   "audio/aiff", NULL};
      return g_variant_new_strv(mimes, -1);
    }
    return NULL;
  }

  if (g_strcmp0(interface_name, "org.mpris.MediaPlayer2.Player") != 0) {
    return NULL;
  }

  if (g_strcmp0(property_name, "PlaybackStatus") == 0) {
    return g_variant_new_string(self->playing
                                    ? "Playing"
                                    : (self->has_track ? "Paused" : "Stopped"));
  }
  if (g_strcmp0(property_name, "LoopStatus") == 0) {
    return g_variant_new_string(self->loop_status != NULL ? self->loop_status
                                                          : "None");
  }
  if (g_strcmp0(property_name, "Shuffle") == 0) {
    return g_variant_new_boolean(self->shuffle);
  }
  if (g_strcmp0(property_name, "Rate") == 0 ||
      g_strcmp0(property_name, "MinimumRate") == 0 ||
      g_strcmp0(property_name, "MaximumRate") == 0) {
    return g_variant_new_double(1.0);
  }
  if (g_strcmp0(property_name, "Metadata") == 0) {
    return build_metadata(self);
  }
  if (g_strcmp0(property_name, "Volume") == 0) {
    return g_variant_new_double(self->volume);
  }
  if (g_strcmp0(property_name, "Position") == 0) {
    return g_variant_new_int64(self->position_us);
  }
  if (g_strcmp0(property_name, "CanGoNext") == 0 ||
      g_strcmp0(property_name, "CanGoPrevious") == 0 ||
      g_strcmp0(property_name, "CanPlay") == 0 ||
      g_strcmp0(property_name, "CanPause") == 0 ||
      g_strcmp0(property_name, "CanSeek") == 0 ||
      g_strcmp0(property_name, "CanControl") == 0) {
    return g_variant_new_boolean(TRUE);
  }
  return NULL;
}

static gboolean on_set_property(GDBusConnection* connection,
                                const gchar* sender,
                                const gchar* object_path,
                                const gchar* interface_name,
                                const gchar* property_name,
                                GVariant* value,
                                GError** error,
                                gpointer user_data) {
  MprisBridge* self = static_cast<MprisBridge*>(user_data);
  (void)connection;
  (void)sender;
  (void)object_path;
  (void)error;

  // El estado de verdad lo lleva Dart: aquí solo se reenvía la intención y se
  // deja que el eco de `updateState` repinte la propiedad.
  if (g_strcmp0(interface_name, "org.mpris.MediaPlayer2.Player") != 0) {
    return FALSE;
  }

  if (g_strcmp0(property_name, "LoopStatus") == 0) {
    const gchar* value_text = g_variant_get_string(value, NULL);
    gchar* command = g_strdup_printf("loop:%s", value_text);
    notify_command(self, command);
    g_free(command);
    return TRUE;
  }
  if (g_strcmp0(property_name, "Shuffle") == 0) {
    notify_command(self, g_variant_get_boolean(value) ? "shuffle:1"
                                                      : "shuffle:0");
    return TRUE;
  }
  if (g_strcmp0(property_name, "Volume") == 0) {
    gchar* command = g_strdup_printf("volume:%f", g_variant_get_double(value));
    notify_command(self, command);
    g_free(command);
    return TRUE;
  }
  return FALSE;
}

// ---------------------------------------------------------------------------
// Métodos
// ---------------------------------------------------------------------------

static void on_method_call(GDBusConnection* connection,
                           const gchar* sender,
                           const gchar* object_path,
                           const gchar* interface_name,
                           const gchar* method_name,
                           GVariant* parameters,
                           GDBusMethodInvocation* invocation,
                           gpointer user_data) {
  MprisBridge* self = static_cast<MprisBridge*>(user_data);
  (void)connection;
  (void)sender;
  (void)object_path;
  (void)parameters;

  if (g_strcmp0(interface_name, "org.mpris.MediaPlayer2") == 0) {
    if (g_strcmp0(method_name, "Raise") == 0) {
      notify_command(self, "raise");
    } else if (g_strcmp0(method_name, "Quit") == 0) {
      notify_command(self, "quit");
    } else {
      g_dbus_method_invocation_return_error(
          invocation, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD,
          "método desconocido: %s", method_name);
      return;
    }
    g_dbus_method_invocation_return_value(invocation, NULL);
    return;
  }

  if (g_strcmp0(interface_name, "org.mpris.MediaPlayer2.Player") != 0) {
    g_dbus_method_invocation_return_error(
        invocation, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_INTERFACE,
        "interfaz desconocida: %s", interface_name);
    return;
  }

  if (g_strcmp0(method_name, "Play") == 0) {
    notify_command(self, "play");
  } else if (g_strcmp0(method_name, "Pause") == 0) {
    notify_command(self, "pause");
  } else if (g_strcmp0(method_name, "PlayPause") == 0) {
    notify_command(self, "toggle");
  } else if (g_strcmp0(method_name, "Stop") == 0) {
    notify_command(self, "stop");
  } else if (g_strcmp0(method_name, "Next") == 0) {
    notify_command(self, "next");
  } else if (g_strcmp0(method_name, "Previous") == 0) {
    notify_command(self, "previous");
  } else if (g_strcmp0(method_name, "Seek") == 0) {
    gint64 offset_us = 0;
    g_variant_get(parameters, "(x)", &offset_us);
    // MPRIS pide microsegundos; Dart trabaja en segundos.
    gchar* command = g_strdup_printf("seekrel:%f",
                                     static_cast<gdouble>(offset_us) / 1e6);
    notify_command(self, command);
    g_free(command);
  } else if (g_strcmp0(method_name, "SetPosition") == 0) {
    const gchar* track_id = NULL;
    gint64 position_us = 0;
    g_variant_get(parameters, "(&ox)", &track_id, &position_us);
    gchar* command = g_strdup_printf("seek:%f",
                                     static_cast<gdouble>(position_us) / 1e6);
    notify_command(self, command);
    g_free(command);
  } else if (g_strcmp0(method_name, "OpenUri") == 0) {
    const gchar* uri = NULL;
    g_variant_get(parameters, "(&s)", &uri);
    gchar* command = g_strdup_printf("open:%s", uri != NULL ? uri : "");
    notify_command(self, command);
    g_free(command);
  } else {
    g_dbus_method_invocation_return_error(
        invocation, G_DBUS_ERROR, G_DBUS_ERROR_UNKNOWN_METHOD,
        "método desconocido: %s", method_name);
    return;
  }

  g_dbus_method_invocation_return_value(invocation, NULL);
}

static const GDBusInterfaceVTable kVtable = {
    on_method_call,
    on_get_property,
    on_set_property,
};

// ---------------------------------------------------------------------------
// Ciclo de vida del nombre
// ---------------------------------------------------------------------------

static void on_bus_acquired(GDBusConnection* connection,
                            const gchar* name,
                            gpointer user_data) {
  MprisBridge* self = static_cast<MprisBridge*>(user_data);
  self->connection = static_cast<GDBusConnection*>(g_object_ref(connection));

  g_autoptr(GError) error = NULL;

  g_autoptr(GDBusNodeInfo) root_info =
      g_dbus_node_info_new_for_xml(kRootXml, &error);
  if (root_info == NULL) {
    g_warning("MPRIS: XML raíz inválido: %s", error->message);
    return;
  }
  self->root_registration = g_dbus_connection_register_object(
      connection, kObjectPath, root_info->interfaces[0], &kVtable, self, NULL,
      &error);
  if (self->root_registration == 0) {
    g_warning("MPRIS: no se pudo registrar la raíz: %s", error->message);
    g_clear_error(&error);
  }

  g_autoptr(GDBusNodeInfo) player_info =
      g_dbus_node_info_new_for_xml(kPlayerXml, &error);
  if (player_info == NULL) {
    g_warning("MPRIS: XML del reproductor inválido: %s", error->message);
    return;
  }
  self->player_registration = g_dbus_connection_register_object(
      connection, kObjectPath, player_info->interfaces[0], &kVtable, self,
      NULL, &error);
  if (self->player_registration == 0) {
    g_warning("MPRIS: no se pudo registrar el reproductor: %s",
              error->message);
  }

  g_debug("MPRIS: %s publicado en %s", name, kObjectPath);
}

static void on_name_lost(GDBusConnection* connection,
                         const gchar* name,
                         gpointer user_data) {
  (void)connection;
  (void)user_data;
  // Sin sesión de D-Bus (SSH, TTY) es normal; no es un error de la app.
  g_message("MPRIS: nombre %s no disponible (¿sin sesión de D-Bus?)", name);
}

// ---------------------------------------------------------------------------
// API pública
// ---------------------------------------------------------------------------

MprisBridge* mpris_bridge_new(MprisCommandCallback on_command,
                              gpointer user_data) {
  MprisBridge* self = g_new0(MprisBridge, 1);
  self->on_command = on_command;
  self->user_data = user_data;
  self->title = g_strdup("");
  self->artist = g_strdup("");
  self->album = g_strdup("");
  self->loop_status = g_strdup("None");
  self->volume = 1.0;
  self->owner_id = g_bus_own_name(G_BUS_TYPE_SESSION, kBusName,
                                  G_BUS_NAME_OWNER_FLAGS_NONE, on_bus_acquired,
                                  NULL, on_name_lost, self, NULL);
  return self;
}

void mpris_bridge_free(MprisBridge* self) {
  if (self == NULL) {
    return;
  }
  if (self->owner_id != 0) {
    g_bus_unown_name(self->owner_id);
    self->owner_id = 0;
  }
  if (self->connection != NULL) {
    if (self->player_registration != 0) {
      g_dbus_connection_unregister_object(self->connection,
                                          self->player_registration);
      self->player_registration = 0;
    }
    if (self->root_registration != 0) {
      g_dbus_connection_unregister_object(self->connection,
                                          self->root_registration);
      self->root_registration = 0;
    }
    g_clear_object(&self->connection);
  }
  g_free(self->title);
  g_free(self->artist);
  g_free(self->album);
  g_free(self->loop_status);
  g_free(self);
}

void mpris_bridge_set_metadata(MprisBridge* self,
                               const gchar* title,
                               const gchar* artist,
                               const gchar* album,
                               gint64 duration_us) {
  if (self == NULL) {
    return;
  }
  g_free(self->title);
  g_free(self->artist);
  g_free(self->album);
  self->title = g_strdup(title != NULL ? title : "");
  self->artist = g_strdup(artist != NULL ? artist : "");
  self->album = g_strdup(album != NULL ? album : "");
  self->has_track = self->title != NULL && *self->title != '\0';
  self->duration_us = duration_us > 0 ? duration_us : 0;
  if (self->position_us > self->duration_us) {
    self->position_us = self->duration_us;
  }
  emit_metadata(self);
  emit_playback(self);
}

void mpris_bridge_set_playback(MprisBridge* self,
                               gboolean playing,
                               gint64 position_us) {
  if (self == NULL) {
    return;
  }
  const gboolean changed = self->playing != playing;
  self->playing = playing;
  self->position_us = position_us > 0 ? position_us : 0;
  if (changed) {
    emit_playback(self);
  }
}

void mpris_bridge_set_loop_and_shuffle(MprisBridge* self,
                                       const gchar* loop_status,
                                       gboolean shuffle) {
  if (self == NULL) {
    return;
  }
  const gchar* next_loop = loop_status != NULL ? loop_status : "None";
  const gboolean loop_changed = g_strcmp0(self->loop_status, next_loop) != 0;
  const gboolean shuffle_changed = self->shuffle != shuffle;
  if (loop_changed) {
    g_free(self->loop_status);
    self->loop_status = g_strdup(next_loop);
  }
  self->shuffle = shuffle;

  if (!loop_changed && !shuffle_changed) {
    return;
  }
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  if (loop_changed) {
    g_variant_builder_add(&builder, "{sv}", "LoopStatus",
                          g_variant_new_string(self->loop_status));
  }
  if (shuffle_changed) {
    g_variant_builder_add(&builder, "{sv}", "Shuffle",
                          g_variant_new_boolean(self->shuffle));
  }
  emit_changed(self, "org.mpris.MediaPlayer2.Player",
               g_variant_builder_end(&builder));
}

void mpris_bridge_set_volume(MprisBridge* self, gdouble volume) {
  if (self == NULL) {
    return;
  }
  const gdouble clamped = volume < 0.0 ? 0.0 : (volume > 1.0 ? 1.0 : volume);
  if (clamped == self->volume) {
    return;
  }
  self->volume = clamped;
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&builder, "{sv}", "Volume",
                        g_variant_new_double(self->volume));
  emit_changed(self, "org.mpris.MediaPlayer2.Player",
               g_variant_builder_end(&builder));
}

void mpris_bridge_emit_seeked(MprisBridge* self, gint64 position_us) {
  if (self == NULL) {
    return;
  }
  self->position_us = position_us > 0 ? position_us : 0;
  if (self->connection == NULL) {
    return;
  }
  g_dbus_connection_emit_signal(
      self->connection, NULL, kObjectPath, "org.mpris.MediaPlayer2.Player",
      "Seeked", g_variant_new("(x)", self->position_us), NULL);
}
