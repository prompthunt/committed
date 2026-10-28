mod adapters;
mod updates;
use committed_core::*;
use std::sync::Arc;
use tauri::{
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Emitter, Manager,
};
use tauri_plugin_autostart::ManagerExt;
use tauri_plugin_opener::OpenerExt;

struct Desktop {
    core: Arc<BoardCore>,
}
#[derive(serde::Serialize)]
struct DesktopSettings {
    launch_at_login: bool,
    version: String,
}
#[tauri::command]
fn get_settings(state: tauri::State<Desktop>) -> Settings {
    state.core.settings()
}
#[tauri::command]
fn get_desktop_settings(app: tauri::AppHandle) -> Result<DesktopSettings, String> {
    Ok(DesktopSettings {
        launch_at_login: app.autolaunch().is_enabled().map_err(|e| e.to_string())?,
        version: app.package_info().version.to_string(),
    })
}
#[tauri::command]
fn set_launch_at_login(app: tauri::AppHandle, enabled: bool) -> Result<(), String> {
    if enabled {
        app.autolaunch().enable()
    } else {
        app.autolaunch().disable()
    }
    .map_err(|e| e.to_string())
}
#[tauri::command]
fn set_setting(
    app: tauri::AppHandle,
    state: tauri::State<Desktop>,
    setting: String,
    enabled: bool,
) -> Result<(), String> {
    state.core.set_setting(&setting, enabled)?;
    let _ = app.emit("board-changed", ());
    Ok(())
}
#[tauri::command]
fn set_hidden(
    app: tauri::AppHandle,
    state: tauri::State<Desktop>,
    login: String,
    hidden: bool,
) -> Result<(), String> {
    state.core.set_hidden(&login, hidden)?;
    let _ = app.emit("board-changed", ());
    if !hidden {
        launch_refresh(&app, RefreshReason::WindowChanged);
    }
    Ok(())
}
#[tauri::command]
fn open_profile(app: tauri::AppHandle, login: String) -> Result<(), String> {
    if login.is_empty()
        || login.len() > 39
        || !login
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'-')
    {
        return Err("Invalid GitHub username".into());
    }
    app.opener()
        .open_url(format!("https://github.com/{login}"), None::<&str>)
        .map_err(|e| e.to_string())
}
#[tauri::command]
fn get_board(state: tauri::State<Desktop>, window: Window) -> Board {
    state.core.select_window(window);
    state.core.board(window)
}
#[tauri::command]
fn list_people(
    state: tauri::State<Desktop>,
    search: String,
    filter: PeopleFilter,
) -> Vec<PersonVisibility> {
    state.core.people(&search, filter)
}
#[tauri::command]
async fn start_connect(state: tauri::State<'_, Desktop>) -> Result<DevicePrompt, String> {
    state.core.start_connect().await
}
#[tauri::command]
async fn poll_connect(
    app: tauri::AppHandle,
    state: tauri::State<'_, Desktop>,
) -> Result<ConnectStatus, String> {
    let status = state.core.poll_connect().await?;
    if status == ConnectStatus::Connected {
        if let Some(setup) = app.get_webview_window("setup") {
            let _ = setup.hide();
        }
        show_window(&app, "board")?;
        launch_refresh(&app, RefreshReason::Manual);
    }
    Ok(status)
}
#[tauri::command]
fn disconnect(app: tauri::AppHandle, state: tauri::State<Desktop>) -> Result<(), String> {
    state.core.disconnect()?;
    if let Some(board) = app.get_webview_window("board") {
        let _ = board.hide();
    }
    show_window(&app, "setup")?;
    let _ = app.emit("board-changed", ());
    Ok(())
}
#[tauri::command]
fn request_refresh(app: tauri::AppHandle, reason: RefreshReason) {
    launch_refresh(&app, reason);
}
fn launch_refresh(app: &tauri::AppHandle, reason: RefreshReason) {
    let app = app.clone();
    let core = app.state::<Desktop>().core.clone();
    tauri::async_runtime::spawn(async move {
        let refresh = core.refresh(reason);
        tokio::pin!(refresh);
        // Poll once before emitting so listeners can read the refreshing snapshot.
        tokio::select! { result = &mut refresh => { if let Err(error) = result { let _ = app.emit("app-error", error); } },
            _ = tokio::time::sleep(std::time::Duration::from_millis(50)) => {
                let _ = app.emit("board-changed", ());
                if let Err(error) = refresh.await { let _ = app.emit("app-error", error); }
            }
        }
        let board = core.board(Window::Today);
        if let Some(tray) = app.tray_by_id("committed") {
            let tooltip = if board.rows.len() > 1 {
                board
                    .rows
                    .iter()
                    .find(|r| r.is_you)
                    .map(|r| format!("Committed · #{} of {}", r.rank, board.rows.len()))
                    .unwrap_or_else(|| "Committed".into())
            } else {
                "Committed".into()
            };
            let _ = tray.set_tooltip(Some(tooltip));
        }
        let _ = app.emit("board-changed", ());
    });
}
fn show_window(app: &tauri::AppHandle, label: &str) -> Result<(), String> {
    let window = app
        .get_webview_window(label)
        .ok_or("Window not available")?;
    window
        .show()
        .and_then(|_| window.set_focus())
        .map_err(|e| e.to_string())
}
#[tauri::command]
fn open_window(app: tauri::AppHandle, label: String) -> Result<(), String> {
    if !matches!(label.as_str(), "people" | "about" | "setup") {
        return Err("Unknown window".into());
    }
    show_window(&app, &label)
}
#[tauri::command]
fn open_github(app: tauri::AppHandle, page: String) -> Result<(), String> {
    let url = match page.as_str() {
        "device" => "https://github.com/login/device",
        "contributions" => "https://github.com/settings/profile",
        _ => return Err("Unknown GitHub page".into()),
    };
    app.opener()
        .open_url(url, None::<&str>)
        .map_err(|e| e.to_string())
}
#[tauri::command]
async fn quit(app: tauri::AppHandle) {
    updates::quit(app).await;
}
#[tauri::command]
fn hide_board(app: tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("board") {
        let _ = window.hide();
    }
}

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            let _ = show_window(app, "board");
        }))
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(
            tauri_plugin_autostart::Builder::new()
                .args(["--autostart"])
                .build(),
        )
        .plugin(tauri_plugin_updater::Builder::new().build())
        .setup(|app| {
            let dir = app.path().app_data_dir()?;
            std::fs::create_dir_all(&dir)?;
            let core = Arc::new(BoardCore::new(
                Arc::new(adapters::GitHubHttp::new()?),
                Arc::new(adapters::SystemClock),
                Arc::new(adapters::FileStorage::new(dir.join("board.json"))),
                Arc::new(adapters::WindowsCredentials),
                Arc::new(adapters::WindowsNotifier(app.handle().clone())),
            )?);
            let connected = core.connected()?;
            app.manage(Desktop { core });
            app.manage(updates::Updates::default());
            // Webviews must not invoke commands until all managed state exists.
            for config in &app.config().app.windows {
                tauri::WebviewWindowBuilder::from_config(app, config)?.build()?;
            }
            TrayIconBuilder::with_id("committed")
                .icon(tauri::image::Image::from_bytes(include_bytes!(
                    "../icons/32x32.png"
                ))?)
                .tooltip("Committed")
                .show_menu_on_left_click(false)
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        rect,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        let label = if app.state::<Desktop>().core.connected().unwrap_or(false) {
                            "board"
                        } else {
                            "setup"
                        };
                        if let Some(window) = app.get_webview_window(label) {
                            if window.is_visible().unwrap_or(false) {
                                let _ = window.hide();
                                return;
                            }
                            if label == "board" {
                                let scale = window.scale_factor().unwrap_or(1.0);
                                let size = window
                                    .outer_size()
                                    .unwrap_or(tauri::PhysicalSize::new(380, 620));
                                let position = rect.position.to_physical::<f64>(scale);
                                let icon_size = rect.size.to_physical::<f64>(scale);
                                if let Ok(monitors) = app.available_monitors() {
                                    if let Some(monitor) = monitors.iter().find(|m| {
                                        let p = m.position();
                                        let s = m.size();
                                        position.x >= p.x as f64
                                            && position.x < p.x as f64 + s.width as f64
                                            && position.y >= p.y as f64
                                            && position.y < p.y as f64 + s.height as f64
                                    }) {
                                        let area = monitor.work_area();
                                        let left = area.position.x as f64;
                                        let top = area.position.y as f64;
                                        let right = left + area.size.width as f64;
                                        let bottom = top + area.size.height as f64;
                                        let x = (position.x + icon_size.width - size.width as f64)
                                            .clamp(left, (right - size.width as f64).max(left));
                                        let y = if position.y > top + area.size.height as f64 / 2.0
                                        {
                                            position.y - size.height as f64 - 8.0
                                        } else {
                                            position.y + icon_size.height + 8.0
                                        };
                                        let _ = window.set_position(tauri::PhysicalPosition::new(
                                            x as i32,
                                            y.clamp(top, (bottom - size.height as f64).max(top))
                                                as i32,
                                        ));
                                    }
                                }
                            }
                            let _ = window.show();
                            let _ = window.set_focus();
                            if label == "board" {
                                launch_refresh(app, RefreshReason::Opened);
                            }
                        }
                    }
                })
                .build(app)?;
            if !connected {
                show_window(app.handle(), "setup")?;
            } else {
                launch_refresh(app.handle(), RefreshReason::Timer);
            }
            let handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                loop {
                    tokio::time::sleep(std::time::Duration::from_secs(300)).await;
                    launch_refresh(&handle, RefreshReason::Timer);
                }
            });
            let update_handle = app.handle().clone();
            tauri::async_runtime::spawn(async move {
                loop {
                    let _ = updates::check_updates(update_handle.clone(), false).await;
                    tokio::time::sleep(std::time::Duration::from_secs(14400)).await;
                }
            });
            Ok(())
        })
        .on_window_event(|window, event| match event {
            tauri::WindowEvent::Focused(false) if window.label() == "board" => {
                let _ = window.hide();
            }
            tauri::WindowEvent::CloseRequested { api, .. } => {
                api.prevent_close();
                let _ = window.hide();
            }
            _ => {}
        })
        .invoke_handler(tauri::generate_handler![
            get_board,
            list_people,
            start_connect,
            poll_connect,
            disconnect,
            request_refresh,
            open_window,
            open_github,
            quit,
            hide_board,
            get_settings,
            get_desktop_settings,
            set_launch_at_login,
            set_setting,
            set_hidden,
            open_profile,
            updates::get_update_status,
            updates::check_updates,
            updates::install_update
        ])
        .run(tauri::generate_context!())
        .expect("Could not start Committed");
}
