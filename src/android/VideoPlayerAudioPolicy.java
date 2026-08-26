package com.joohyoung.cordova.videoplayer;

final class VideoPlayerAudioPolicy {

    private VideoPlayerAudioPolicy() {
    }

    static float effectiveVolume(
            float requestedVolume,
            boolean respectSilentMode,
            int ringerMode,
            int silentRingerMode,
            int vibrateRingerMode) {
        if (respectSilentMode
                && (ringerMode == silentRingerMode || ringerMode == vibrateRingerMode)) {
            return 0.0f;
        }
        return requestedVolume;
    }
}
