package com.joohyoung.cordova.videoplayer;

public final class VideoPlayerAudioPolicyTests {

    private static final int SILENT = 0;
    private static final int VIBRATE = 1;
    private static final int NORMAL = 2;

    private static void assertVolume(float expected, float actual, String message) {
        if (Float.compare(expected, actual) != 0) {
            throw new AssertionError(message + ": expected " + expected + ", got " + actual);
        }
    }

    public static void main(String[] args) {
        assertVolume(0.6f, VideoPlayerAudioPolicy.effectiveVolume(
                0.6f, false, SILENT, SILENT, VIBRATE),
                "disabled option must preserve requested volume in silent mode");
        assertVolume(0.0f, VideoPlayerAudioPolicy.effectiveVolume(
                0.6f, true, SILENT, SILENT, VIBRATE),
                "silent mode must mute when the option is enabled");
        assertVolume(0.0f, VideoPlayerAudioPolicy.effectiveVolume(
                0.6f, true, VIBRATE, SILENT, VIBRATE),
                "vibrate mode must mute when the option is enabled");
        assertVolume(0.6f, VideoPlayerAudioPolicy.effectiveVolume(
                0.6f, true, NORMAL, SILENT, VIBRATE),
                "normal mode must preserve requested volume");
        assertVolume(0.6f, VideoPlayerAudioPolicy.effectiveVolume(
                0.6f, true, 99, SILENT, VIBRATE),
                "unknown modes must preserve requested volume");

        System.out.println("VideoPlayerAudioPolicy tests passed");
    }
}
