use committed_core::*;
use std::{path::PathBuf, sync::Mutex, time::Duration};
use tauri_plugin_notification::NotificationExt;

pub struct GitHubHttp(reqwest::Client);
impl GitHubHttp {
    pub fn new() -> Result<Self, reqwest::Error> {
        Ok(Self(
            reqwest::Client::builder()
                .user_agent("Committed-Windows")
                .timeout(Duration::from_secs(20))
                .redirect(reqwest::redirect::Policy::none())
                .build()?,
        ))
    }
}
#[async_trait::async_trait]
impl Http for GitHubHttp {
    async fn request(&self, request: Request) -> Result<String, String> {
        let url = reqwest::Url::parse(&request.url).map_err(|_| "Invalid GitHub address")?;
        if url.scheme() != "https"
            || !matches!(url.host_str(), Some("github.com" | "api.github.com"))
        {
            return Err("Only GitHub requests are allowed".into());
        }
        if request.token.is_some() && url.host_str() != Some("api.github.com") {
            return Err("Credentials may only be sent to the GitHub API".into());
        }
        let mut builder = if let Some(form) = request.form {
            self.0.post(url).form(&form)
        } else {
            self.0.get(url)
        };
        builder = builder.header(
            "Accept",
            if request.url.contains("/contributions") {
                "text/html"
            } else {
                "application/json"
            },
        );
        if let Some(token) = request.token {
            builder = builder.bearer_auth(token);
        }
        let response = builder
            .send()
            .await
            .map_err(|_| "Could not reach GitHub. Check your connection.")?;
        if !response.status().is_success() {
            return Err(match response.status().as_u16() {
                401 => "GitHub access expired. Disconnect GitHub and connect again.",
                403 | 429 => "GitHub is limiting requests. Try again later.",
                _ => "GitHub could not complete this request. Try again.",
            }
            .into());
        }
        response
            .text()
            .await
            .map_err(|_| "Could not read GitHub's response".into())
    }
}
pub struct SystemClock;
impl Clock for SystemClock {
    fn now(&self) -> i64 {
        chrono::Utc::now().timestamp()
    }
    fn today(&self) -> chrono::NaiveDate {
        chrono::Local::now().date_naive()
    }
}
pub struct FileStorage {
    path: PathBuf,
    write: Mutex<()>,
}
impl FileStorage {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            write: Mutex::new(()),
        }
    }
}
impl Storage for FileStorage {
    fn load(&self) -> Result<Option<String>, String> {
        match std::fs::read_to_string(&self.path) {
            Ok(text) => Ok(Some(text)),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(_) => Err("Could not read the saved board".into()),
        }
    }
    fn save(&self, value: &str) -> Result<(), String> {
        let _guard = self.write.lock().unwrap();
        let temp = self.path.with_extension("tmp");
        std::fs::write(&temp, value)
            .and_then(|_| std::fs::rename(temp, &self.path))
            .map_err(|_| "Could not save your board. Check free disk space and permissions.".into())
    }
}
pub struct WindowsCredentials;
impl WindowsCredentials {
    fn entry(&self) -> Result<keyring::Entry, String> {
        keyring::Entry::new("com.digg.commitstandings.windows", "github")
            .map_err(|_| "Windows Credential Manager is unavailable".into())
    }
}
impl CredentialStore for WindowsCredentials {
    fn get(&self) -> Result<Option<String>, String> {
        match self.entry()?.get_password() {
            Ok(token) => Ok(Some(token)),
            Err(keyring::Error::NoEntry) => Ok(None),
            Err(_) => Err("Could not read GitHub access from Windows Credential Manager".into()),
        }
    }
    fn set(&self, token: Option<&str>) -> Result<(), String> {
        let entry = self.entry()?;
        match token {
            Some(token) => entry
                .set_password(token)
                .map_err(|_| "Could not save GitHub access in Windows Credential Manager".into()),
            None => match entry.delete_credential() {
                Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
                Err(_) => {
                    Err("Could not delete GitHub access from Windows Credential Manager".into())
                }
            },
        }
    }
}
pub struct WindowsNotifier(pub tauri::AppHandle);
impl Notifier for WindowsNotifier {
    fn post(&self, notification: Notification) {
        let _ = self
            .0
            .notification()
            .builder()
            .title(notification.title)
            .body(notification.body)
            .show();
    }
}
