#include "cyberhex_core.h"

#include <string.h>

const char* ch_result_str(ch_result r) {
    switch (r) {
        case CH_OK: return "OK";
        case CH_ERR_NOMEM: return "sin memoria";
        case CH_ERR_INVALID_ARG: return "argumento invalido";
        case CH_ERR_DECODE: return "error de decodificacion";
        case CH_ERR_DEVICE: return "error de dispositivo de audio";
        case CH_ERR_IO: return "error de E/S";
        case CH_ERR_FORMAT: return "formato no soportado";
        case CH_ERR_NOT_FOUND: return "no encontrado";
        case CH_ERR_UNSUPPORTED: return "no soportado";
        case CH_ERR_STATE: return "estado invalido";
        case CH_ERR_BUSY: return "dispositivo ocupado";
        case CH_ERR_CANCELLED: return "cancelado";
        default: return "codigo de error desconocido";
    }
}
