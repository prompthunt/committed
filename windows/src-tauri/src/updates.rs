use crate::Desktop;
use serde::Serialize;
use std::sync::Mutex;
use tauri::{Emitter, Manager};
use tauri_plugin_updater::{Update, UpdaterExt};

#[derive(Clone, Default, Serialize)]
pub struct UpdateStatus {
    pub message: String,
    pub ready: bool,
}
#[derive(Default)]
pub struct Updates {
    inner: Mutex<UpdateState>,
}
#[derive(Default)]
struct UpdateState {
    busy: bool,
    status: UpdateStatus,
    pending: Option<(Update, Vec<u8>)>,
}
fn report(app: &tauri::AppHandle, message: String, ready: bool) {
    let status = UpdateStatus { message, ready };
    app.state::<Updates>().inner.lock().unwrap().status = status.clone();
    let _ = app.emit("update-status", &status);
    if let Some(tray) = app.tray_by_id("committed") {
        if ready {
            let _ = tray.set_tooltip(Some("Committed · Update ready"));
        }
    }
}
#[tauri::command]
pub fn get_update_status(state: tauri::State<Updates>) -> UpdateStatus {
    state.inner.lock().unwrap().status.clone()
}
#[tauri::command]
pub async fn check_updates(app: tauri::AppHandle, manual: bool) -> Result<(), String> {
    if !manual && !app.state::<Desktop>().core.settings().automatic_updates {
        return Ok(());
    }
    {
        let state = app.state::<Updates>();
        let mut inner = state.inner.lock().unwrap();
        if inner.busy || inner.pending.is_some() {
            return Ok(());
        }
        inner.busy = true;
    }
    let result = check(&app, manual).await;
    app.state::<Updates>().inner.lock().unwrap().busy = false;
    if result.is_err() && manual {
        report(
            &app,
            "Could not check for updates. Please try again later.".into(),
            false,
        );
    }
    result
}
async fn check(app: &tauri::AppHandle, manual: bool) -> Result<(), String> {
    let update = app
        .updater()
        .map_err(|e| e.to_string())?
        .check()
        .await
        .map_err(|_| "Could not check for updates")?;
    if let Some(update) = update {
        if !manual && !app.state::<Desktop>().core.settings().automatic_updates {
            return Ok(());
        }
        report(
            app,
            format!("Downloading Committed {}…", update.version),
            false,
        );
        let bytes = update
            .download(|_, _| {}, || {})
            .await
            .map_err(|_| "Could not download or verify the update")?;
        if !manual && !app.state::<Desktop>().core.settings().automatic_updates {
            report(app, "Automatic Updates is off.".into(), false);
            return Ok(());
        }
        let version = update.version.clone();
        app.state::<Updates>().inner.lock().unwrap().pending = Some((update, bytes));
        report(
            app,
            format!("Committed {version} is ready. Restart to update."),
            true,
        );
    } else if manual {
        report(app, "You're up to date.".into(), false);
    }
    Ok(())
}
#[tauri::command]
pub async fn install_update(app: tauri::AppHandle) -> Result<(), String> {
    let pending = app
        .state::<Updates>()
        .inner
        .lock()
        .unwrap()
        .pending
        .take()
        .ok_or("No update is ready")?;
    let result = tauri::async_runtime::spawn_blocking(move || pending.0.install(pending.1))
        .await
        .map_err(|e| e.to_string())?;
    match result {
        Ok(()) => {
            app.restart();
        }
        Err(_) => {
            report(
                &app,
                "The update could not install. Check for Updates to retry.".into(),
                false,
            );
            Err("The update could not install".into())
        }
    }
}
pub async fn quit(app: tauri::AppHandle) {
    let ready = app
        .state::<Updates>()
        .inner
        .lock()
        .unwrap()
        .pending
        .is_some();
    if ready
        && app.state::<Desktop>().core.settings().automatic_updates
        && install_update(app.clone()).await.is_err()
    {
        return;
    }
    app.exit(0);
}
