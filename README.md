Video Player plugin for Cordova/PhoneGap
========================================

A Cordova plugin that simply allows you to immediately play a video in fullscreen mode.


# Installation

This plugin use the Cordova CLI's plugin command. To install it to your application, simply execute the following (and replace variables).

```
cordova plugin add cordova-plugin-video-player
```


# Using

Just call the  `play` method with a video file path as argument. The video player will close itself when the video will be completed.

```
VideoPlayer.play(path, [options], [completeCallback], [errorCallback]);
```

Stop and close a video currently playing without waiting the end.
```
VideoPlayer.close();
```

The plugin is able to play file-path or http/rtsp URL.

You can optionally add options parameters like volume and calling mode.
You can also add an success callback function to handle completed playback.
You can also add an error callback function to handle unexpected playback errors.

## Example

```javascript
VideoPlayer.play("file:///android_asset/www/movie.mp4");
```

```javascript
VideoPlayer.play(
    "file:///android_asset/www/movie.mp4",
    {
        volume: 0.5,
        scalingMode: VideoPlayer.SCALING_MODE.SCALE_TO_FIT_WITH_CROPPING,
        respectSilentMode: true
    },
    function () {
        console.log("video completed");
    },
    function (err) {
        console.log(err);
    }
);
```

## Options

- `volume`: (Optional) allows you to set the volume on this player. Note that the passed volume value is raw scalars in range 0.0 to 1.0.

- `scalingMode`: (Optional) allows you to sets video scaling mode.

    The following constants are the only values available for the `scalingMode` option:

    - `SCALE_TO_FIT` (default)
    - `SCALE_TO_FIT_WITH_CROPPING`

    Refer to http://developer.android.com/reference/android/media/MediaPlayer.html#setVideoScalingMode(int) for more details.

- `respectSilentMode`: (Optional) controls whether video audio follows the device's silent setting. The default is `false`, which preserves the existing behavior.

    - On iOS, `true` keeps the video playing but silences its audio while iPhone Silent Mode is on. Silent Mode is controlled by the Ring/Silent switch or, on supported iPhone models, the Action button. Haptics are configured separately. Focus and Do Not Disturb are not treated as Silent Mode by this option.
    - On Android, `true` checks the ringer mode immediately before playback starts. Silent or Vibrate starts that video with its effective volume set to zero; Normal uses the requested `volume`. The plugin does not monitor later ringer-mode changes during the same playback and does not change the device's media volume, ringer mode, or Do Not Disturb policy.

### iOS audio session lifecycle

Before playback, the plugin saves the host app's current audio session category, mode, category options, and route-sharing policy. It restores that configuration when playback finishes, the video is tapped, `close` is called, or audio-session activation fails.

The restore uses a best-effort ownership check. If the current category, mode, category options, or route-sharing policy differs from the configuration captured immediately after this plugin configured playback, the plugin keeps the newer configuration instead of applying its snapshot. A restore failure is written to the native Xcode log and does not change the existing JavaScript callback timing or public API.

Only one iOS video can be active at a time. A second `play` call made while the current player is playing or closing is rejected through that call's error callback, which prevents an older playback from changing the newer playback's audio-session state.


# Development

## Bumping the plugin version

The published plugin version is stored in two places that must always match: the `version` field in `package.json` and the `version` attribute on the root `<plugin>` element in `plugin.xml`.

This repository ships a `version-up` agent skill that bumps both values together. It **refuses to proceed if the two files already disagree**, rather than guessing which one is correct, and it likewise stops if the current version is not a stable SemVer `M.m.p`. Given an increment unit (`major`/`minor`/`patch`) or an explicit version it uses that directly; with no argument it proposes candidates and asks. After updating both files it re-reads them and runs `npm test`. It never commits, tags, pushes, publishes, or creates a release.

The skill source lives at `.claude/skills/version-up/SKILL.md`, and `.agents/skills/version-up` is a repository-relative symlink to that same directory so Claude Code and Codex both read one copy. See the **"이 스킬이 두 경로에 있는 이유"** section of that file for the discovery paths and invocation forms of each product — they are documented there only, so that a correction lands in one place. Edit only `.claude/skills/version-up/SKILL.md`.

Use the separate `release` skill only when the version change should also be committed, tagged, and pushed. It runs `version-up`, commits only `package.json` and `plugin.xml`, creates an annotated tag whose name is exactly the new SemVer (for example, `1.2.3`), and atomically pushes the explicit verified commit and tag refs to a single shared `origin` fetch/push URL. Release tags never add prefixes such as `dev/`, `v`, or `release/`. It explicitly disables follow-tags and mirror configuration; it does not publish to npm, create a GitHub release, or write a CHANGELOG. Its shared source is `.claude/skills/release`, with `.agents/skills/release` pointing to the same directory.

# Troubleshooting

**When playing a video for the first time, everything works great. when calling .close() function the video closes great. 2nd time around, the .play() is called the same way as the first time. The video plays fine for the second time. Now when trying to close it before the video ends, the app fatally crash.**

When the "completed" event gets fired, make sure you close the video in the "completed" event to clear that instance so that if you have another video they don't both play.


# Licence MIT

Copyright 2013 Quentin Aupetit

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
