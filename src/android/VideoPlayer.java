package com.joohyoung.cordova.videoplayer;

import android.annotation.TargetApi;
import android.app.Dialog;
import android.content.DialogInterface;
import android.content.DialogInterface.OnDismissListener;
import android.content.res.AssetFileDescriptor;
import android.media.MediaPlayer;
import android.media.MediaPlayer.OnCompletionListener;
import android.media.MediaPlayer.OnErrorListener;
import android.media.MediaPlayer.OnPreparedListener;
import android.net.Uri;
import android.os.Build;
import android.util.Log;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.Window;
import android.view.WindowManager;
import android.view.WindowManager.LayoutParams;
import android.widget.LinearLayout;

import org.apache.cordova.CallbackContext;
import org.apache.cordova.CordovaArgs;
import org.apache.cordova.CordovaPlugin;
import org.apache.cordova.CordovaResourceApi;
import org.apache.cordova.PluginResult;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.IOException;

public class VideoPlayer extends CordovaPlugin implements OnCompletionListener, OnPreparedListener, OnErrorListener, OnDismissListener {

    protected static final String LOG_TAG = "VideoPlayer";

    protected static final String ASSETS = "/android_asset/";

    private CallbackContext callbackContext = null;

    private Dialog dialog;

    private MediaPlayer player;

    /**
     * Executes the request and returns PluginResult.
     *
     * @param action          The action to execute.
     * @param args            JSONArray of arguments for the plugin.
     * @param callbackContext The callback id used when calling back into JavaScript.
     * @return A PluginResult object with a status and message.
     */
    public boolean execute(String action, CordovaArgs args, CallbackContext callbackContext) throws JSONException {
        if (action.equals("play")) {
            this.callbackContext = callbackContext;

            CordovaResourceApi resourceApi = webView.getResourceApi();
            String target = args.getString(0);
            final JSONObject options = args.getJSONObject(1);

            String fileUriStr;
            try {
                Uri targetUri = resourceApi.remapUri(Uri.parse(target));
                fileUriStr = targetUri.toString();
            } catch (IllegalArgumentException e) {
                fileUriStr = target;
            }

            Log.v(LOG_TAG, fileUriStr);

            final String path = stripFileProtocol(fileUriStr);

            // Create dialog in new thread
            cordova.getActivity().runOnUiThread(() -> openVideoDialog(path, options));

            // Don't return any result now
            PluginResult pluginResult = new PluginResult(PluginResult.Status.NO_RESULT);
            pluginResult.setKeepCallback(true);
            callbackContext.sendPluginResult(pluginResult);

            return true;
        } else if (action.equals("close")) {
            handleClose();
            return true;
        }
        return false;
    }

    /**
     * Removes the "file://" prefix from the given URI string, if applicable.
     * If the given URI string doesn't have a "file://" prefix, it is returned unchanged.
     *
     * @param uriString the URI string to operate on
     * @return a path without the "file://" prefix
     */
    public static String stripFileProtocol(String uriString) {
        if (uriString.startsWith("file://")) {
            return Uri.parse(uriString).getPath();
        }
        return uriString;
    }

    @TargetApi(Build.VERSION_CODES.JELLY_BEAN)
    protected void openVideoDialog(String path, JSONObject options) {
        dialog = new Dialog(cordova.getActivity(), android.R.style.Theme_NoTitleBar);
        dialog.requestWindowFeature(Window.FEATURE_NO_TITLE);
        dialog.setCancelable(true);
        dialog.setOnDismissListener(this);

        LinearLayout main = new LinearLayout(cordova.getActivity());
        main.setLayoutParams(new LinearLayout.LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT));
        dialog.setContentView(main);

        // SurfaceView를 생성 및 설정
        // SurfaceView를 생성 및 설정
        SurfaceView surfaceView = new SurfaceView(cordova.getActivity());
        surfaceView.setOnClickListener(v -> {
            // 터치 이벤트가 발생하면 handleClose 메소드를 호출하도록 수정
            handleClose();
        });
        main.addView(surfaceView);
        final SurfaceHolder holder = surfaceView.getHolder();

        player = new MediaPlayer();
        player.setOnPreparedListener(this);
        player.setOnCompletionListener(this);
        player.setOnErrorListener(this);

        if (path.startsWith(ASSETS)) {
            String f = path.substring(15);
            AssetFileDescriptor fd;
            try {
                fd = cordova.getActivity().getAssets().openFd(f);
                player.setDataSource(fd.getFileDescriptor(), fd.getStartOffset(), fd.getLength());
            } catch (Exception e) {
                PluginResult result = new PluginResult(PluginResult.Status.ERROR, e.getLocalizedMessage());
                result.setKeepCallback(false); // release status callback in JS side
                callbackContext.sendPluginResult(result);
                callbackContext = null;
                return;
            }
        } else {
            try {
                player.setDataSource(path);
            } catch (Exception e) {
                PluginResult result = new PluginResult(PluginResult.Status.ERROR, e.getLocalizedMessage());
                result.setKeepCallback(false); // release status callback in JS side
                callbackContext.sendPluginResult(result);
                callbackContext = null;
                return;
            }
        }

        try {
            float volume = Float.parseFloat(options.getString("volume"));
            Log.d(LOG_TAG, "setVolume: " + volume);
            player.setVolume(volume, volume);
        } catch (Exception e) {
            PluginResult result = new PluginResult(PluginResult.Status.ERROR, e.getLocalizedMessage());
            result.setKeepCallback(false); // release status callback in JS side
            callbackContext.sendPluginResult(result);
            callbackContext = null;
            return;
        }

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.JELLY_BEAN) {
            try {
                int scalingMode = options.getInt("scalingMode");
                if (scalingMode == MediaPlayer.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING) {
                    Log.d(LOG_TAG, "setVideoScalingMode VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING");
                    player.setVideoScalingMode(MediaPlayer.VIDEO_SCALING_MODE_SCALE_TO_FIT_WITH_CROPPING);
                } else {
                    Log.d(LOG_TAG, "setVideoScalingMode VIDEO_SCALING_MODE_SCALE_TO_FIT");
                    player.setVideoScalingMode(MediaPlayer.VIDEO_SCALING_MODE_SCALE_TO_FIT);
                }
            } catch (Exception e) {
                PluginResult result = new PluginResult(PluginResult.Status.ERROR, e.getLocalizedMessage());
                result.setKeepCallback(false); // release status callback in JS side
                callbackContext.sendPluginResult(result);
                callbackContext = null;
                return;
            }
        }

        holder.addCallback(new SurfaceHolder.Callback() {
            @Override
            public void surfaceCreated(SurfaceHolder surfaceHolder) {
                player.setDisplay(surfaceHolder);
                try {
                    // MediaPlayer 준비
                    player.prepare();
                } catch (IOException e) {
                    handleError(e.getLocalizedMessage());
                }
            }

            @Override
            public void surfaceChanged(SurfaceHolder surfaceHolder, int i, int i1, int i2) {
                // Surface 변경 사항 처리
            }

            @Override
            public void surfaceDestroyed(SurfaceHolder surfaceHolder) {
                if (player != null) {
                    player.release();
                    player = null;
                }
            }
        });

        WindowManager.LayoutParams lp = new WindowManager.LayoutParams();
        lp.copyFrom(dialog.getWindow().getAttributes());
        dialog.show();
        dialog.getWindow().setAttributes(lp);
    }

    private void handleError(String errorMessage) {
        PluginResult result = new PluginResult(PluginResult.Status.ERROR, errorMessage);
        result.setKeepCallback(false);
        callbackContext.sendPluginResult(result);
        callbackContext = null;
        if (dialog != null) {
            dialog.dismiss();
        }
    }

    // 중앙화된 자원 해제 메소드
    private void handleClose() {
        // 화면 터치 시 player가 null이 아닐 때만 처리하도록 수정
        if (player != null) {
            if (player.isPlaying()) {
                player.stop();
            }
            player.release();
            player = null; // player를 해제한 후 null로 설정하여 중복 해제 방지
        }
        if (dialog != null) {
            dialog.dismiss();
            dialog = null;
        }
        if (callbackContext != null) {
            PluginResult result = new PluginResult(PluginResult.Status.OK);
            result.setKeepCallback(false);
            callbackContext.sendPluginResult(result);
            callbackContext = null;
        }
    }

    // 기존의 onError 메소드
    @Override
    public boolean onError(MediaPlayer mp, int what, int extra) {
        Log.e(LOG_TAG, "MediaPlayer.onError(" + what + ", " + extra + ")");
        handleError("MediaPlayer error occurred");
        return false;
    }

    @Override
    public void onPrepared(MediaPlayer mp) {
        mp.start();
    }

    // 기존의 onCompletion 메소드
    @Override
    public void onCompletion(MediaPlayer mp) {
        Log.d(LOG_TAG, "MediaPlayer completed");
        handleClose();
    }

    @Override
    public void onDismiss(DialogInterface dialog) {
        Log.d(LOG_TAG, "Dialog dismissed");
        handleClose();
    }

}
