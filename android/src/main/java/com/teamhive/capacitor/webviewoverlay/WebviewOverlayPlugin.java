package com.teamhive.capacitor.webviewoverlay;
import android.annotation.SuppressLint;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.net.Uri;
import android.os.Message;
//import com.google.android.material.floatingactionbutton.FloatingActionButton;
import android.util.Log;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.teamhive.capacitor.webviewoverlay.R;

import java.io.ByteArrayOutputStream;
import java.net.MalformedURLException;
import java.net.URL;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import android.util.Base64;

@CapacitorPlugin(name = "WebviewOverlayPlugin")
public class WebviewOverlayPlugin extends Plugin {
    // Non-http(s) schemes a page may hand off to another app (ACTION_VIEW).
    // Anything else (file:, content:, intent:, javascript:, unknown) is blocked.
    private static final Set<String> EXTERNAL_SCHEMES = new HashSet<>(Arrays.asList(
        "tel", "mailto", "sms", "geo", "market", "whatsapp", "fb", "twitter",
        // wallet deep links, handled by NanChat itself (see AndroidManifest)
        "nano", "nan", "nanauth", "ban", "xdg", "ana", "xro"
    ));
    // Non-http(s) schemes that may load inside the overlay (in-page frames).
    private static final Set<String> INLINE_SCHEMES = new HashSet<>(Arrays.asList(
        "about", "blob", "data"
    ));

    private WebView webView;
    private boolean hidden = false;
    private boolean fullscreen = false;
    private boolean backButtonListenerRegistered = false;

//  private FloatingActionButton closeFullscreenButton;
    private int width;
    private int height;
    private float x;
    private float y;

    private String targetUrl;

    private PluginCall loadUrlCall;

    @Override
    public void load() {
        super.load();
         // Register Android back button handler using Capacitor
        if (!backButtonListenerRegistered) {
            getActivity().getOnBackPressedDispatcher().addCallback( new androidx.activity.OnBackPressedCallback(true) {
                @Override
                public void handleOnBackPressed() {
                    // When back button is pressed
                    handleBackButtonPress();
                }
            });
            backButtonListenerRegistered = true;
        }
    }
   /**
     * Handle the Android back button press event.
     */
    private void handleBackButtonPress() {
        if (webView != null && webView.canGoBack()) {
            // Go back in WebView if it has history
            webView.goBack();
        } else {
            // Perform default behavior (exit app or go to previous activity)
            getActivity().onBackPressed();
        }
    }
    private float getPixels(int value) {
        return value * getContext().getResources().getDisplayMetrics().density + 0.5f;
    }

    @SuppressLint("SetJavaScriptEnabled")
    @PluginMethod()
    public void open(final PluginCall call) {
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                hidden = false;
                webView = new WebView(getContext());
                WebSettings settings = webView.getSettings();
                // Remote pages only: no access to local files or content providers,
                // and no http subresources on https pages.
                settings.setAllowContentAccess(false);
                settings.setAllowFileAccess(false);
                settings.setAllowFileAccessFromFileURLs(false);
                settings.setAllowUniversalAccessFromFileURLs(false);
                settings.setJavaScriptEnabled(true);
                settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
                settings.setDomStorageEnabled(true);
                settings.setSupportMultipleWindows(false);
                String userAgent = call.getString("userAgent", "");
                if (!userAgent.isEmpty()) {
                    settings.setUserAgentString(String.format("%s %s", settings.getUserAgentString(), userAgent));
                }

                // Temp fix until this setting is on by default
                bridge.getWebView().getSettings().setJavaScriptCanOpenWindowsAutomatically(true);

                final String javascript = call.getString("javascript", "");

                final int injectionTime = call.getInt("injectionTime", 0);

                //closeFullscreenButton = new FloatingActionButton(getContext());

                //webView.addView(closeFullscreenButton);

                webView.setOnKeyListener(new View.OnKeyListener() {
                                    @Override
                                    public boolean onKey(View v, int keyCode, KeyEvent event) {
                                        if (event.getAction() == KeyEvent.ACTION_DOWN) {
                                            if (keyCode == KeyEvent.KEYCODE_BACK && webView.canGoBack()) {
                                                // WebView goes back on Back button press
                                                webView.goBack();
                                                return true;
                                            }
                                        }
                                        return false;
                                    }
                                });
                webView.setWebChromeClient(new WebChromeClient() {
                    @Override
                    public void onProgressChanged(WebView view, int progress) {
                        JSObject progressValue = new JSObject();
                        progressValue.put("value", progress/100.0);
                        notifyListeners("progress", progressValue);
                    }

                    @Override
                    public boolean onCreateWindow(WebView view, boolean isDialog, boolean isUserGesture, Message resultMsg) {
                        final WebView targetWebView = new WebView(getActivity());
                        targetWebView.setWebViewClient(new WebViewClient() {
                            @Override
                            public void onLoadResource(WebView view, String url) {
                                if (hasListeners("navigationHandler")) {
                                    handleNavigation(url, true);
                                    JSObject progressValue = new JSObject();
                                    progressValue.put("value", 0.1);
                                    notifyListeners("progress", progressValue);
                                }
                                else {
                                    webView.loadUrl(url);
                                }
                                targetWebView.removeAllViews();
                                targetWebView.destroy();
                            }
                        });
                        WebView.WebViewTransport transport = (WebView.WebViewTransport) resultMsg.obj;
                        transport.setWebView(targetWebView);
                        resultMsg.sendToTarget();
                        return true;
                    }

                });

                webView.setWebViewClient(new WebViewClient() {
                    @Override
                    public void onPageStarted(WebView view, String url, Bitmap favicon) {
                        super.onPageStarted(view, url, favicon);

                        if (!javascript.isEmpty() && injectionTime == 0) {
                            webView.evaluateJavascript(javascript, null);
                        }
                    }

                    @Override
                    public void onPageFinished(WebView view, String url) {
                        super.onPageFinished(view, url);
                        if (webView != null) {
                            if (!javascript.isEmpty() && injectionTime == 1) {
                                webView.evaluateJavascript(javascript, null);
                            }
                            if (!hidden) {
                                webView.setVisibility(View.VISIBLE);
                            } else {
                                webView.setVisibility(View.INVISIBLE);
                                notifyListeners("updateSnapshot", new JSObject());
                            }
                        }

                        if (loadUrlCall != null) {
                            loadUrlCall.success();
                            loadUrlCall = null;
                        }
                        notifyListeners("pageLoaded", new JSObject());
                    }

                    @Override
                    public void doUpdateVisitedHistory(WebView view, String url, boolean isReload) {
                        // allow to notify url even when changed by javascript
                        super.doUpdateVisitedHistory(view, url, isReload);
                        if (hasListeners("navigationHandler") && !isReload) {
                            handleNavigation(url, false);
                        }
                    }
                    @Override
                    public boolean shouldOverrideUrlLoading(WebView view, String url) {
                        if (url == null) {
                            return true;
                        }
                        String scheme = Uri.parse(url).getScheme();
                        scheme = scheme == null ? "" : scheme.toLowerCase();
                        if (!scheme.equals("http") && !scheme.equals("https")) {
                            if (EXTERNAL_SCHEMES.contains(scheme)) {
                                // Let another app (or NanChat itself) handle the deep link
                                Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                                intent.addCategory(Intent.CATEGORY_BROWSABLE);
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                                try {
                                    getContext().startActivity(intent);
                                } catch (Exception e) {
                                    // no app installed to handle it
                                }
                                return true;
                            }
                            // about:/blob:/data: frames load in place, everything else is blocked
                            return !INLINE_SCHEMES.contains(scheme);
                        }

                        if (hasListeners("navigationHandler")) {
                            handleNavigation(url, false);
                            if (url.startsWith("https://nanchat.com/")) {
                                return true;
                            }
                            return false;
                        }
                        else {
                            targetUrl = null;
                            return false;
                        }
                    }
                });

                webView.setVisibility(View.INVISIBLE);

                String urlString = call.getString("url", "");

                if (urlString.isEmpty()) {
                    call.error("Must provide a URL to open");
                    return;
                }


                width = (int) getPixels(call.getInt("width", 1));
                height = (int) getPixels(call.getInt("height", 1));
                x = getPixels(call.getInt("x", 0));
                y = getPixels(call.getInt("y", 0));


                ViewGroup.LayoutParams params = new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
                webView.setLayoutParams(params);
                params.width = width;
                params.height = height;
                webView.setX(x);
                webView.setY(y);
                webView.requestLayout();

                ((ViewGroup) getBridge().getWebView().getParent()).addView(webView);

                webView.loadUrl(urlString);
              call.resolve();
            }
        });
    }

    private void handleNavigation(String url, Boolean newWindow) {
        targetUrl = url;
        boolean sameHost;
        try {
            URL currentUrl = new URL(webView.getUrl());
            URL targetUrl = new URL(url);
            sameHost = currentUrl.getHost().equals(targetUrl.getHost());

            JSObject navigationHandlerValue = new JSObject();
            navigationHandlerValue.put("url", url);
            navigationHandlerValue.put("newWindow", newWindow);
            navigationHandlerValue.put("sameHost", sameHost);

            notifyListeners("navigationHandler", navigationHandlerValue);
        }
        catch(MalformedURLException e) { }
    }

    @PluginMethod()
    public void close(final PluginCall call) {
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
            if (webView != null) {
                ViewGroup rootGroup = ((ViewGroup) getBridge().getWebView().getParent());
                int count = rootGroup.getChildCount();
                if (count > 1) {
                    rootGroup.removeView(webView);
                    webView.destroyDrawingCache();
                    webView.destroy();
                    webView = null;
                }
                hidden = false;
            }
            call.resolve();
            }
        });
    }

    @PluginMethod()
    public void show(final PluginCall call) {
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                hidden = false;
                if (webView != null) {
                    webView.setVisibility(View.VISIBLE);
                }
                call.success();
            }
        });
    }

    @PluginMethod()
    public void hide(final PluginCall call) {
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                hidden = true;
                if (webView != null) {
                    webView.setVisibility(View.INVISIBLE);
                }
                call.success();
            }
        });
    }

    @PluginMethod()
    public void updateDimensions(final PluginCall call) {
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                width = (int) getPixels(call.getInt("width", 1));
                height = (int) getPixels(call.getInt("height", 1));
                x = getPixels(call.getInt("x", 0));
                y = getPixels(call.getInt("y", 0));

                if (!fullscreen) {
                    ViewGroup.LayoutParams params = webView.getLayoutParams();
                    params.width = width;
                    params.height = height;
                    webView.setX(x);
                    webView.setY(y);
                    webView.requestLayout();
                }
                else {
                    ViewGroup.LayoutParams params = webView.getLayoutParams();
                    params.width = ViewGroup.LayoutParams.MATCH_PARENT;
                    params.height = ViewGroup.LayoutParams.MATCH_PARENT;
                    webView.setX(0);
                    webView.setY(0);
                    webView.requestLayout();
                }

                if (hidden) {
                    notifyListeners("updateSnapshot", new JSObject());
                }
                call.success();
            }
        });
    }

    private WebView getWebView() {
        return webView;
    }

    @PluginMethod()
    public void getSnapshot(final PluginCall call) {
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                final JSObject object = new JSObject();
                if (webView != null) {
                    Bitmap bm = Bitmap.createBitmap(width == 0 ? 1 : width, height == 0 ? 1 : height, Bitmap.Config.ARGB_8888);
                    Canvas canvas = new Canvas(bm);
                    getWebView().draw(canvas);
                    ByteArrayOutputStream os = new ByteArrayOutputStream();
                    bm.compress(Bitmap.CompressFormat.JPEG, 100, os);
                    byte[] byteArray = os.toByteArray();
                    String src = Base64.encodeToString(byteArray, Base64.DEFAULT);
                    object.put("src", src);
                    call.resolve(object);
                } else {
                    object.put("src", "");
                    call.resolve(object);
                }
            }
        });
    }

    @PluginMethod()
    public void evaluateJavaScript(final PluginCall call) {
        final String javascript = call.getString("javascript", "");
        if (javascript.isEmpty()) {
            call.error("Must provide javascript string");
            return;
        }

        if (webView != null) {
            final JSObject object = new JSObject();
            getActivity().runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    webView.evaluateJavascript(javascript, new ValueCallback<String>() {
                        @Override
                        public void onReceiveValue(String value) {
                            if (value != null) {
                                object.put("result", value);
                                call.resolve(object);
                            }
                        }
                    });
                }
            });
        }
    }

    @PluginMethod()
    public void toggleFullscreen(final PluginCall call) {
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (webView != null) {
                    if (fullscreen) {
                        ViewGroup.LayoutParams params = webView.getLayoutParams();
                        params.width = width;
                        params.height = height;
                        webView.setX(x);
                        webView.setY(y);
                        webView.requestLayout();
                        fullscreen = false;
                        //closeFullscreenButton.setVisibility(View.GONE);
                    }
                    else {
                        ViewGroup.LayoutParams params = webView.getLayoutParams();
                        params.width = ViewGroup.LayoutParams.MATCH_PARENT;
                        params.height = ViewGroup.LayoutParams.MATCH_PARENT;
                        webView.setX(0);
                        webView.setY(0);
                        webView.requestLayout();
                        fullscreen = true;
                        //closeFullscreenButton.setVisibility(View.VISIBLE);
                    }
                }
                if (call != null) {
                    call.success();
                }
            }
        });
    }

    @PluginMethod()
    public void goBack(final PluginCall call) {
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (webView != null) {
                    webView.goBack();
                }
                call.success();
            }
        });
    }

    @PluginMethod()
    public void goForward(final PluginCall call) {
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (webView != null) {
                    webView.goForward();
                }
                call.success();
            }
        });
    }

    @PluginMethod()
    public void reload(final PluginCall call) {
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (webView != null) {
                    webView.reload();
                }
                call.success();
            }
        });
    }

    @PluginMethod()
    public void loadUrl(final PluginCall call) {
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
            if (call.getString("url") != null) {
                webView.loadUrl(call.getString("url"));
                loadUrlCall = call;
            }
            }
        });
    }

    @PluginMethod()
    public void handleNavigationEvent(final PluginCall call) {
        getActivity().runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (webView != null && targetUrl != null) {
                    if (call.getBoolean("allow")) {
                        webView.loadUrl(targetUrl);
                    }
                    else {
                        notifyListeners("pageLoaded", new JSObject());
                    }
                    targetUrl = null;
                }
                call.success();
            }
        });
    }
}
