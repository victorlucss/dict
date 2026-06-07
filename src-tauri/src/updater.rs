//! Over-the-air updates via `tauri-plugin-updater`.
//!
//! Checks a signed `latest.json` manifest (served from GitHub Releases), and on a
//! newer version prompts the user, then downloads + verifies + installs in place
//! and relaunches. Runs a check shortly after launch and every 6 hours; the tray
//! "Check for Updates…" item triggers a manual check that also reports when the
//! app is already up to date.

use tauri::AppHandle;
use tauri_plugin_dialog::{DialogExt, MessageDialogButtons, MessageDialogKind};
use tauri_plugin_updater::UpdaterExt;

const CHECK_INTERVAL_SECS: u64 = 6 * 60 * 60; // every 6 hours

/// Start background checks: one ~5s after launch (so startup isn't slowed), then
/// every 6 hours. Silent when there's nothing new.
pub fn start_background_checks(app: &AppHandle) {
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        tokio::time::sleep(std::time::Duration::from_secs(5)).await;
        loop {
            check(app.clone(), false).await;
            tokio::time::sleep(std::time::Duration::from_secs(CHECK_INTERVAL_SECS)).await;
        }
    });
}

/// Manual check from the tray. Reports "up to date" and errors to the user.
pub fn check_now(app: &AppHandle) {
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        check(app, true).await;
    });
}

async fn check(app: AppHandle, user_initiated: bool) {
    let updater = match app.updater() {
        Ok(u) => u,
        Err(e) => {
            tracing::warn!("Updater unavailable: {}", e);
            if user_initiated {
                notify(
                    &app,
                    "Update check failed",
                    &format!("Couldn't start the updater: {e}"),
                    MessageDialogKind::Error,
                );
            }
            return;
        }
    };

    match updater.check().await {
        Ok(Some(update)) => {
            let version = update.version.clone();
            let current = update.current_version.clone();
            tracing::info!("Update available: {} (current {})", version, current);

            let install = app
                .dialog()
                .message(format!(
                    "Dict {version} is available (you have {current}).\n\nInstall it now? Dict will restart to finish."
                ))
                .title("Update available")
                .buttons(MessageDialogButtons::OkCancelCustom(
                    "Install & Restart".into(),
                    "Later".into(),
                ))
                .blocking_show();

            if install {
                tracing::info!("Downloading update {}", version);
                match update.download_and_install(|_chunk, _total| {}, || {}).await {
                    Ok(_) => {
                        tracing::info!("Update installed; restarting");
                        app.restart();
                    }
                    Err(e) => {
                        tracing::error!("Update install failed: {}", e);
                        notify(
                            &app,
                            "Update failed",
                            &format!("The update couldn't be installed: {e}"),
                            MessageDialogKind::Error,
                        );
                    }
                }
            }
        }
        Ok(None) => {
            tracing::info!("No update available");
            if user_initiated {
                notify(
                    &app,
                    "You're up to date",
                    "You're running the latest version of Dict.",
                    MessageDialogKind::Info,
                );
            }
        }
        Err(e) => {
            tracing::warn!("Update check failed: {}", e);
            if user_initiated {
                notify(
                    &app,
                    "Update check failed",
                    &format!("Couldn't check for updates: {e}"),
                    MessageDialogKind::Info,
                );
            }
        }
    }
}

fn notify(app: &AppHandle, title: &str, body: &str, kind: MessageDialogKind) {
    app.dialog()
        .message(body)
        .title(title)
        .kind(kind)
        .blocking_show();
}
