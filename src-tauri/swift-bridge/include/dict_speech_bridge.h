#ifndef DICT_SPEECH_BRIDGE_H
#define DICT_SPEECH_BRIDGE_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*DictSpeechResultCallback)(void *context, const char *text, bool is_final);
typedef void (*DictSpeechLevelCallback)(void *context, float level);
typedef void (*DictSpeechErrorCallback)(void *context, const char *error);

void dict_speech_set_callbacks(
    void *context,
    DictSpeechResultCallback on_result,
    DictSpeechLevelCallback on_level,
    DictSpeechErrorCallback on_error
);

void dict_speech_start(const char *language);
void dict_speech_stop(void);
void dict_speech_cancel(void);

typedef void (*DictSpeechPermissionCallback)(bool speech_granted, bool mic_granted);
void dict_speech_request_permissions(DictSpeechPermissionCallback callback);

#ifdef __cplusplus
}
#endif

#endif /* DICT_SPEECH_BRIDGE_H */
