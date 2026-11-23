#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ch_engine ch_engine;

const char* ch_core_version(void);
/*
 * Version del ABI del nucleo. Sube cuando cambia algo incompatible (firmas,
 * structs o semantica). La app puede exigir un minimo antes de usar funciones
 * nuevas; el resto se detecta con dlsym/providesSymbol.
 */
int32_t ch_engine_abi_version(void);
const char* ch_core_last_error(void);

ch_engine* ch_engine_create(void);
void ch_engine_destroy(ch_engine* engine);

int32_t ch_engine_load(ch_engine* engine, const char* utf8_path);
/* Reproduce la pista `index` de la cola sin vaciarla. */
int32_t ch_engine_play_index(ch_engine* engine, int32_t index);
/* Añade la pista al final de la cola y la reproduce (la cola se conserva). */
int32_t ch_engine_load_add(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_play(ch_engine* engine);
int32_t ch_engine_pause(ch_engine* engine);
int32_t ch_engine_seek(ch_engine* engine, double seconds);

/* Cola editable: mover, quitar e insertar pistas sin cortar el audio. */
int32_t ch_engine_queue_move(ch_engine* engine, int32_t from, int32_t to);
int32_t ch_engine_queue_remove(ch_engine* engine, int32_t index);
int32_t ch_engine_queue_insert(ch_engine* engine, int32_t index, const char* utf8_path);

int32_t ch_engine_set_volume(ch_engine* engine, float volume);
float   ch_engine_volume(ch_engine* engine);

/* DSP de reproduccion. */
int32_t ch_engine_set_crossfeed(ch_engine* engine, int32_t enabled, float strength);
int32_t ch_engine_crossfeed(ch_engine* engine, float* strength);
int32_t ch_engine_set_mono(ch_engine* engine, int32_t enabled);
int32_t ch_engine_mono(ch_engine* engine);
int32_t ch_engine_set_balance(ch_engine* engine, float balance);
float   ch_engine_balance(ch_engine* engine);
int32_t ch_engine_set_gain_db(ch_engine* engine, float gain_db); /* -24 .. +24 */
float   ch_engine_gain_db(ch_engine* engine);
/* Guarda la caratula `index` de la pista audible en `path` (0 si ok). */
int32_t ch_engine_save_cover(ch_engine* engine, int32_t index, const char* path);
int32_t ch_engine_set_stereo_width(ch_engine* engine, float width); /* 0 .. 2 */
float   ch_engine_stereo_width(ch_engine* engine);
int32_t ch_engine_set_trim_silence(ch_engine* engine, int32_t enabled, float threshold_db);
int32_t ch_engine_trim_silence(ch_engine* engine, float* threshold_db);
int32_t ch_engine_set_fade_out(ch_engine* engine, float seconds); /* 0 .. 30 */
float   ch_engine_fade_out(ch_engine* engine);
int32_t ch_engine_set_fade_in(ch_engine* engine, float seconds); /* 0 .. 30 */
float   ch_engine_fade_in(ch_engine* engine);
int32_t ch_engine_set_gap(ch_engine* engine, float seconds); /* 0 .. 30 */
float   ch_engine_gap(ch_engine* engine);
int32_t ch_engine_set_8d(ch_engine* engine, int32_t enabled, float speed, float depth);
int32_t ch_engine_8d(ch_engine* engine, float* speed, float* depth);
int32_t ch_engine_set_reverb(ch_engine* engine, int32_t enabled, float mix);
int32_t ch_engine_reverb(ch_engine* engine, float* mix);
int32_t ch_engine_set_compressor(ch_engine* engine, int32_t enabled, float threshold_db, float ratio, float attack_s, float release_s);
int32_t ch_engine_compressor(ch_engine* engine, float* threshold_db, float* ratio);
int32_t ch_engine_set_peq(ch_engine* engine, int32_t band, int32_t enabled, int32_t type, float freq, float gain_db, float q);
int32_t ch_engine_peq(ch_engine* engine, int32_t band, int32_t* type, float* freq, float* gain_db, float* q);
int32_t ch_engine_set_hrtf(ch_engine* engine, int32_t enabled, float angle);
int32_t ch_engine_hrtf(ch_engine* engine, float* angle);
int32_t ch_engine_stats(ch_engine* engine, uint64_t* play_count, double* listen_seconds);
int32_t ch_engine_set_tag(ch_engine* engine, const char* key, const char* value);
int32_t ch_library_export_json(const void* lib, const char* path);
int32_t ch_library_export_csv(const void* lib, const char* path);
int32_t ch_engine_set_avoid_recent(ch_engine* engine, int32_t enabled);
int32_t ch_engine_avoid_recent(ch_engine* engine);
int32_t ch_engine_recent_count(ch_engine* engine);
int32_t ch_engine_recent_clear(ch_engine* engine);
int32_t ch_engine_set_pause_at_dir_end(ch_engine* engine, int32_t enabled);
int32_t ch_engine_pause_at_dir_end(ch_engine* engine);
int32_t ch_engine_load_dir(ch_engine* engine, const char* dir);
int32_t ch_engine_set_auto_gain(ch_engine* engine, int32_t enabled, double target_lufs);
int32_t ch_engine_auto_gain(ch_engine* engine, double* target_lufs);
int32_t ch_engine_queue_export_json(ch_engine* engine, const char* path);
int32_t ch_engine_queue_sort(ch_engine* engine);
int32_t ch_engine_queue_reverse(ch_engine* engine);
int32_t ch_engine_queue_shuffle(ch_engine* engine, uint32_t seed);
int32_t ch_engine_queue_insert_sorted(ch_engine* engine, const char* path);
int32_t ch_engine_queue_keep_current(ch_engine* engine);
int32_t ch_engine_queue_duplicate_current(ch_engine* engine);
int32_t ch_engine_queue_rotate(ch_engine* engine);
int32_t ch_engine_queue_count_ext(ch_engine* engine, const char* ext);
int32_t ch_engine_queue_import_json(ch_engine* engine, const char* path);
int32_t ch_library_remove(void* lib, const char* path);
int32_t ch_engine_queue_export_m3u_ext(ch_engine* engine, const char* path);
int32_t ch_engine_queue_sort_title(ch_engine* engine);
int32_t ch_engine_queue_sort_artist(ch_engine* engine);
int32_t ch_engine_queue_sort_album(ch_engine* engine);
int32_t ch_engine_queue_sort_year(ch_engine* engine);
int32_t ch_engine_queue_sort_track(ch_engine* engine);
int32_t ch_engine_queue_sort_duration(ch_engine* engine);
int32_t ch_engine_queue_sort_albumartist(ch_engine* engine);
int32_t ch_engine_queue_sort_genre(ch_engine* engine);
int32_t ch_engine_queue_sort_composer(ch_engine* engine);
int32_t ch_engine_queue_sort_filesize(ch_engine* engine);
const char* ch_engine_queue_path(ch_engine* engine, int32_t index);
int32_t ch_engine_queue_current_index(ch_engine* engine);
const char* ch_engine_queue_title(ch_engine* engine, int32_t index);
const char* ch_engine_queue_artist(ch_engine* engine, int32_t index);
const char* ch_engine_queue_album(ch_engine* engine, int32_t index);
double ch_engine_queue_duration(ch_engine* engine, int32_t index);
int32_t ch_engine_queue_cover_count(ch_engine* engine, int32_t index);
int32_t ch_engine_queue_prune(ch_engine* engine);
int32_t ch_engine_queue_dedup(ch_engine* engine);
int32_t ch_engine_favorites_add(ch_engine* engine, const char* path);
int32_t ch_engine_favorites_remove(ch_engine* engine, const char* path);
int32_t ch_engine_favorites_count(ch_engine* engine);
const char* ch_engine_favorites_path(ch_engine* engine, int32_t index);
int32_t ch_engine_favorites_save(ch_engine* engine, const char* path);
int32_t ch_engine_favorites_load(ch_engine* engine, const char* path);
int32_t ch_engine_favorites_export_m3u(ch_engine* engine, const char* path);
int32_t ch_engine_queue_filter_dir(ch_engine* engine, const char* dir);
int32_t ch_engine_queue_dedup_hash(ch_engine* engine);
int32_t ch_engine_analyze_current(ch_engine* engine, double* lufs, double* peak_db);
int32_t ch_engine_normalize_current(ch_engine* engine, double target_lufs, double* applied_db);
int32_t ch_engine_album_loudness(ch_engine* engine, double* lufs_out);
int32_t ch_engine_normalize_album(ch_engine* engine, double target_lufs, double* applied_db);
int32_t ch_engine_meter(ch_engine* engine, float* peak_l_db, float* peak_r_db, float* rms_db);

/* Bucle A-B en segundos (a < b). */
int32_t ch_engine_set_ab_loop(ch_engine* engine, double a_seconds, double b_seconds);
int32_t ch_engine_clear_ab_loop(ch_engine* engine);
int32_t ch_engine_ab_loop(ch_engine* engine, double* a_seconds, double* b_seconds);

/*
 * Balance estereo: -1 todo a la izquierda, 0 centrado, +1 a la derecha
 * (se acota). El canal favorecido no se amplifica, el otro se atenua.
 */
int32_t ch_engine_set_balance(ch_engine* engine, float balance);
float   ch_engine_balance(ch_engine* engine);

/*
 * Modo de canales: 0 = estereo normal, 1 = mono (misma señal en los dos
 * altavoces), 2 = canales intercambiados. Util con auriculares de un solo lado
 * o altavoces mal cableados. Devuelve -2 si el modo no existe.
 */
int32_t ch_engine_set_channel_mode(ch_engine* engine, int32_t mode);
int32_t ch_engine_channel_mode(ch_engine* engine);

/*
 * Temporizador de apagado: pausa (o termina) tras `seconds`, con fundido
 * final de `fade_seconds`. `seconds <= 0` lo desactiva. `ch_engine_sleep_remaining`
 * devuelve los segundos que faltan o -1 si no hay temporizador activo.
 * Al agotarse se emite CH_EVENT_SLEEP y CH_EVENT_STATE(0).
 */
int32_t ch_engine_set_sleep_timer(ch_engine* engine, double seconds, double fade_seconds);
double  ch_engine_sleep_remaining(ch_engine* engine);

/* ReplayGain: aplica la ganancia de pista si el archivo trae la etiqueta. */
int32_t ch_engine_set_replaygain(ch_engine* engine, int32_t enabled);
float   ch_engine_replaygain_gain_db(ch_engine* engine);
float   ch_engine_replaygain_peak(ch_engine* engine);
/*
 * 0 = ganancia por pista (REPLAYGAIN_TRACK_*), 1 = por album
 * (REPLAYGAIN_ALBUM_*). Si el archivo no trae tags de ReplayGain se usa
 * R128_TRACK_GAIN / R128_ALBUM_GAIN (Q7.8, formato Opus). Afecta a las pistas
 * que se abran despues.
 */
int32_t ch_engine_set_replaygain_mode(ch_engine* engine, int32_t mode);
int32_t ch_engine_replaygain_mode(ch_engine* engine);

/*
 * Niveles de salida para vumetros: escribe rms_l, rms_r, peak_l, peak_r
 * (0.0-1.0, pico incluido por canal) y devuelve cuantos valores escribio.
 * Se miden despues de EQ, ganancia y limitador, con caida exponencial de
 * ~200 ms; baja a cero al pausar. Seguro desde el hilo de UI.
 */
int32_t ch_engine_levels(ch_engine* engine, float* out, int32_t count);

/* Limitador de picos en caliente (ceiling en dBFS, p.ej. -1.0). */
int32_t ch_engine_set_limiter(ch_engine* engine, int32_t enabled, float ceiling_db);
int32_t ch_engine_limiter(ch_engine* engine);

/* Dispositivos de salida. index -1 = predeterminado del sistema. */
int32_t     ch_engine_output_device_count(void);
const char* ch_engine_output_device_name(int32_t index);
int32_t     ch_engine_output_device(ch_engine* engine);
int32_t     ch_engine_set_output_device(ch_engine* engine, int32_t index);

/* Lista de reproducción y avance gapless. */
int32_t ch_engine_queue_add(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_queue_count(ch_engine* engine);
/* Ruta de la pista `index` de la cola ("" si no existe). Valida hasta que
 * cambie la cola: copiala, no guardes el puntero. */
const char* ch_engine_queue_item(ch_engine* engine, int32_t index);
int32_t ch_engine_queue_index(ch_engine* engine);
int32_t ch_engine_queue_clear(ch_engine* engine);
/* Mueve la pista `from` a la posición `to` (reordena sin cortar el audio). */
int32_t ch_engine_queue_move(ch_engine* engine, int32_t from, int32_t to);
/* Quita la pista `index`. Si es la que suena, continúa con la siguiente. */
int32_t ch_engine_queue_remove(ch_engine* engine, int32_t index);
/* Inserta `utf8_path` en la posición `index` (<=0 = principio, negativo = final). */
int32_t ch_engine_queue_insert(ch_engine* engine, int32_t index, const char* utf8_path);
/* Importa M3U/M3U8/PLS y añade sus pistas al final; devuelve cuántas añadió. */
int32_t ch_engine_queue_import(ch_engine* engine, const char* list_path);
/* Exporta la cola actual como M3U8. */
int32_t ch_engine_queue_export(ch_engine* engine, const char* list_path);
int32_t ch_engine_next(ch_engine* engine);
int32_t ch_engine_previous(ch_engine* engine);
int32_t ch_engine_set_gapless(ch_engine* engine, int32_t enabled);
int32_t ch_engine_gapless(ch_engine* engine);

/* Repeticion: 0 = apagada, 1 = toda la cola, 2 = pista actual. */
int32_t ch_engine_set_repeat(ch_engine* engine, int32_t mode);
int32_t ch_engine_repeat(ch_engine* engine);

/* Orden aleatorio reproducible: la semilla manda en el orden de la cola. */
int32_t ch_engine_set_shuffle(ch_engine* engine, int32_t enabled);
int32_t ch_engine_shuffle(ch_engine* engine);
int32_t ch_engine_set_shuffle_seed(ch_engine* engine, uint32_t seed);

/* Crossfade entre pistas al pasar de una a otra (0 = desactivado). */
int32_t ch_engine_set_crossfade(ch_engine* engine, float seconds);
float   ch_engine_crossfade(ch_engine* engine);

/* Velocidad de reproduccion sin cambiar el tono (0.25 - 4.0, 1 = normal). */
int32_t ch_engine_set_speed(ch_engine* engine, float speed);
float   ch_engine_speed(ch_engine* engine);

/* Tono en semitonos sin cambiar la duracion (-12 a +12, 0 = normal). */
int32_t ch_engine_set_pitch(ch_engine* engine, float semitones);
float   ch_engine_pitch(ch_engine* engine);

/*
 * Analizador de espectro sobre el audio que suena (post-EQ, post-volumen).
 * Escribe `bands` valores 0.0-1.0 en `out`, repartidos logaritmicamente de
 * 20 Hz a 20 kHz (-80 dB .. 0 dB). Pensado para vúmetros/visualizadores.
 */
int32_t ch_engine_spectrum(ch_engine* engine, float* out, int32_t bands);

int32_t ch_engine_eq_band_count(void);
/* Frecuencia central (Hz) de la banda `index`; 0 si está fuera de rango. */
float   ch_engine_eq_band_freq(int32_t index);
int32_t ch_engine_set_eq_gains(ch_engine* engine, const float* gains_db, int32_t count);
/* Cambia una sola banda (±18 dB) conservando el resto. */
int32_t ch_engine_set_band_gain(ch_engine* engine, int32_t band, float db);
/*
 * Preamp del EQ en dB (0 a -24, nunca amplifica): baja la senal antes del
 * banco de filtros para que un refuerzo no haga recortar al limitador.
 */
int32_t ch_engine_set_eq_preamp(ch_engine* engine, float db);
float   ch_engine_eq_preamp(ch_engine* engine);
int32_t ch_engine_save_eq_preset(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_load_eq_preset(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_write_replaygain(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_export_spectrum_csv(ch_engine* engine, const char* utf8_path, int32_t points);
int32_t ch_engine_export_waveform_csv(ch_engine* engine, const char* utf8_path, int32_t buckets);
int32_t ch_engine_export_waveform_png(ch_engine* engine, const char* utf8_path, int32_t width, int32_t height);
int32_t ch_engine_export_spectrum_png(ch_engine* engine, const char* utf8_path, int32_t width, int32_t height, int32_t bands);
int32_t ch_engine_eq_preset_count(void);
int32_t ch_engine_eq_preset_name(int32_t index, char* out, int32_t out_len);
int32_t ch_engine_apply_eq_preset(ch_engine* engine, int32_t index);
int32_t ch_engine_copy_tags(const char* src_path, const char* dst_path);
int32_t ch_engine_export_queue_csv(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_save_lyrics(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_load_lyrics(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_shift_lyrics(ch_engine* engine, double delta_s);
double  ch_engine_lyrics_offset_ms(ch_engine* engine);
int32_t ch_engine_cover_count_current(ch_engine* engine);
int32_t ch_engine_save_cover_current(ch_engine* engine, int32_t index, const char* utf8_path);
int32_t ch_engine_eq_preset_find(const char* name);
int32_t ch_engine_write_bpm(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_export_wav(ch_engine* engine, const char* src_path, const char* dst_path, double start_s, double dur_s, int32_t rate, int32_t channels);
int32_t ch_engine_detect_key(ch_engine* engine, const char* utf8_path, char* out, uint32_t out_size, double* confidence);
int32_t ch_engine_key_current(ch_engine* engine, char* out, uint32_t out_size, double* confidence);
int32_t ch_engine_seek_relative(ch_engine* engine, double delta_s);
int32_t ch_engine_toggle_play(ch_engine* engine);
int32_t ch_engine_queue_export_m3u_relative(ch_engine* engine, const char* utf8_path);
int32_t ch_engine_write_replaygain_dir(ch_engine* engine, const char* utf8_dir);
int32_t ch_engine_write_replaygain_queue(ch_engine* engine);
int32_t ch_engine_count_silences(ch_engine* engine, const char* utf8_path, float threshold_db, double min_s, double* out, int32_t max_segments);
int32_t ch_engine_strip_silence(ch_engine* engine, const char* src_path, const char* dst_path, float threshold_db, double min_s, double gap_s, int32_t rate);
int32_t ch_engine_concat_wav(ch_engine* engine, const char* const* src_paths, int32_t count, const char* dst_path, int32_t rate);
int32_t ch_engine_split_by_silence(ch_engine* engine, const char* src_path, const char* prefix, float threshold_db, double min_s, int32_t rate);
int32_t ch_engine_spectrogram_png(ch_engine* engine, const char* utf8_path, const char* utf8_out, int32_t width, int32_t height);
int32_t ch_library_export_json_meta(const void* lib, const char* utf8_path);
int32_t ch_engine_queue_add_library(ch_engine* engine, const void* lib, const char* needle);
double  ch_bpm_detect_path(const char* utf8_path);
double  ch_engine_bpm(ch_engine* engine);
double  ch_dr_measure_path(const char* utf8_path, uint32_t* out_blocks);
double  ch_engine_dr(ch_engine* engine, uint32_t* out_blocks);

const char* ch_engine_title(ch_engine* engine);
const char* ch_engine_artist(ch_engine* engine);
const char* ch_engine_album(ch_engine* engine);

/* Etiquetas adicionales y acceso generico ("" si no existe). */
const char* ch_engine_tag(ch_engine* engine, const char* key);
const char* ch_engine_date(ch_engine* engine);
const char* ch_engine_genre(ch_engine* engine);
const char* ch_engine_composer(ch_engine* engine);
int32_t     ch_engine_track_number(ch_engine* engine);
int32_t     ch_engine_disc_number(ch_engine* engine);
/* Devuelve la carátula embebida (JPEG/PNG) o NULL; escribe el tamaño en bytes. */
const uint8_t* ch_engine_cover(ch_engine* engine, uint64_t* size);
/* Numero de caratulas embebidas en la pista audible. */
int32_t ch_engine_cover_count(ch_engine* engine);
/* Caratula `index` (0 = primera) de la pista audible; NULL si no existe. */
const uint8_t* ch_engine_cover_at(ch_engine* engine, int32_t index, uint64_t* size);

/* Letra sincronizada (LRC) buscada junto al audio (.lrc con el mismo nombre). */
int32_t ch_engine_lyrics_count(ch_engine* engine);
/* Copia la linea activa en `out` (UTF-8). Devuelve bytes escritos o -1. */
int32_t ch_engine_lyric_line(ch_engine* engine, char* out, uint32_t out_size);

/* Fundido al pausar/reanudar, en segundos (0 = corte inmediato, def. 0.05). */
int32_t ch_engine_set_pause_fade(ch_engine* engine, float seconds);
float   ch_engine_pause_fade(ch_engine* engine);

/*
 * Loop A-B de la pista actual, en segundos. Al llegar a B se salta a A por el
 * mismo camino que un seek (respeta crossfade y estiramiento). `end <= start`
 * lo desactiva; tambien se cancela solo al cambiar de pista.
 */
int32_t ch_engine_set_loop(ch_engine* engine, double start, double end);
double  ch_engine_loop_start(ch_engine* engine);
double  ch_engine_loop_end(ch_engine* engine);

double ch_engine_position(ch_engine* engine);
double ch_engine_duration(ch_engine* engine);
double ch_engine_sample_rate(ch_engine* engine);
int32_t ch_engine_channels(ch_engine* engine);
int32_t ch_engine_is_playing(ch_engine* engine);

/*
 * Eventos de reproduccion (sondeo sin callbacks, seguro desde el hilo de UI).
 * `ch_engine_poll_event` devuelve 1 y llena `out` si hay evento, 0 si la cola
 * esta vacia, o -1 si el motor es NULL. La cola guarda 63 eventos; si se llena,
 * se descarta el mas antiguo.
 *
 * kind = CH_EVENT_STATE: a = 1 reproduciendo / 0 en pausa o fin.
 * kind = CH_EVENT_TRACK: a = indice de pista, b = numero de pistas en la cola.
 * kind = CH_EVENT_QUEUE: a = numero de pistas en la cola.
 * kind = CH_EVENT_END:   fin natural de la cola (no se emite al pausar).
 */
typedef struct ch_event {
    int32_t kind;
    int32_t a;
    int32_t b;
    double  value;
} ch_event;

#define CH_EVENT_STATE 1
#define CH_EVENT_TRACK 2
#define CH_EVENT_QUEUE 3
#define CH_EVENT_END   4
#define CH_EVENT_SLEEP 5

int32_t ch_engine_poll_event(ch_engine* engine, ch_event* out);

const char* ch_engine_last_error(ch_engine* engine);

/* Estadisticas de búfer para diagnostico. */
double ch_engine_buffered_seconds(ch_engine* engine);
uint64_t ch_engine_buffer_underflows(ch_engine* engine);
/* Pistas que se saltaron solas por no poder abrirse (archivo roto). */
uint64_t ch_engine_skipped_tracks(ch_engine* engine);

/* Detecta silencio al principio/fin de un archivo (dBFS). lead/tail en segundos. */
int32_t ch_engine_detect_silence(const char* utf8_path, float threshold_db, double* lead, double* tail);

/* Biblioteca de audio: escaneo incremental de carpetas (handle opaco void*). */
void*     ch_library_create(void);
void      ch_library_destroy(void* lib);
int32_t   ch_library_scan(void* lib, const char* root);
int32_t   ch_library_count(const void* lib);
const char* ch_library_path(const void* lib, int32_t index);
/* Busca rutas que contengan el texto (case-insensitive). Devuelve un buffer de
 * indices (int32) y escribe el total en count_out; liberar con ch_file_free. */
int32_t*  ch_library_search(const void* lib, const char* needle, int32_t* count_out);

/* Libera un buffer devuelto por ch_library_search o ch_file_read_all. */
void      ch_file_free(void* data);
int32_t   ch_library_removed(const void* lib);

/* Marcadores por pista (marcas de posicion persistentes). */
typedef struct ch_markers ch_markers;
ch_markers* ch_markers_create(void);
void      ch_markers_destroy(ch_markers* markers);
int32_t   ch_markers_load(ch_markers* markers, const char* path);
int32_t   ch_markers_save(const ch_markers* markers, const char* path);
int32_t   ch_markers_add(ch_markers* markers, const char* track, double position,
                          const char* name);
int32_t   ch_markers_count(const ch_markers* markers, const char* track);
double    ch_markers_position(const ch_markers* markers, const char* track,
                               int32_t index);
const char* ch_markers_name(const ch_markers* markers, const char* track,
                            int32_t index);
int32_t   ch_markers_remove(ch_markers* markers, const char* track, int32_t index);
int32_t   ch_markers_clear(ch_markers* markers, const char* track);

/* Estado de reproduccion: cola, pista actual, posicion y ajustes. */
int32_t ch_engine_save_state(ch_engine* engine, const char* path);
int32_t ch_engine_load_state(ch_engine* engine, const char* path, double* position_out);
int32_t ch_engine_export_json(ch_engine* engine, const char* path);

/* Sonoridad y picos (analisis offline, sin tocar el motor). */
typedef struct {
    double integrated_lufs;
    double sample_peak_dbfs;
    double duration_s;
} ch_loudness_result;
int32_t ch_loudness_scan(const char* utf8_path, ch_loudness_result* out);
int32_t ch_waveform_peaks(const char* utf8_path, uint32_t buckets, float* out_max);

/* Hojas CUE: una imagen de audio dividida en pistas. */
typedef struct ch_cue ch_cue;
ch_cue*   ch_cue_read(const char* path);
void      ch_cue_free(ch_cue* cue);
int32_t   ch_cue_count(const ch_cue* cue);
const char* ch_cue_album(const ch_cue* cue);
const char* ch_cue_album_performer(const ch_cue* cue);
const char* ch_cue_file(const ch_cue* cue, int32_t index);
const char* ch_cue_title(const ch_cue* cue, int32_t index);
const char* ch_cue_performer(const ch_cue* cue, int32_t index);
double    ch_cue_start(const ch_cue* cue, int32_t index);
double    ch_cue_end(const ch_cue* cue, int32_t index);
int32_t   ch_cue_number(const ch_cue* cue, int32_t index);

#ifdef __cplusplus
}
#endif
