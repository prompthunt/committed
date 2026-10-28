use crate::Desktop;
use base64::Engine;
use std::{collections::BTreeMap, sync::Mutex, time::Duration};

pub struct Avatars {
    client: reqwest::Client,
    cache: Mutex<BTreeMap<String, String>>,
    permits: tokio::sync::Semaphore,
}
impl Avatars {
    pub fn new() -> Result<Self, reqwest::Error> {
        Ok(Self {
            client: reqwest::Client::builder()
                .timeout(Duration::from_secs(10))
                .redirect(reqwest::redirect::Policy::none())
                .build()?,
            cache: Mutex::new(BTreeMap::new()),
            permits: tokio::sync::Semaphore::new(6),
        })
    }
}
#[tauri::command]
pub async fn get_avatar(
    state: tauri::State<'_, Avatars>,
    desktop: tauri::State<'_, Desktop>,
    login: String,
) -> Result<Option<String>, String> {
    let Some(url) = desktop
        .core
        .people(&login, committed_core::PeopleFilter::All)
        .into_iter()
        .find(|p| p.person.login == login)
        .and_then(|p| p.person.avatar_url)
    else {
        return Ok(None);
    };
    let mut parsed = reqwest::Url::parse(&url).map_err(|_| "Invalid avatar URL")?;
    if parsed.scheme() != "https"
        || parsed.host_str() != Some("avatars.githubusercontent.com")
        || parsed.port().is_some()
        || !parsed.username().is_empty()
        || parsed.password().is_some()
    {
        return Ok(None);
    }
    parsed.query_pairs_mut().append_pair("s", "96");
    let _permit = state
        .permits
        .acquire()
        .await
        .map_err(|_| "Avatar loading stopped")?;
    if let Some(data) = state.cache.lock().unwrap().get(&url).cloned() {
        return Ok(Some(data));
    }
    // Public images are fetched natively too; the webview has no network access.
    let mut response = state
        .client
        .get(parsed)
        .send()
        .await
        .map_err(|_| "Avatar unavailable")?;
    if !response.status().is_success() {
        return Ok(None);
    }
    let content_type = response
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .unwrap_or("")
        .to_owned();
    if !matches!(
        content_type.as_str(),
        "image/png" | "image/jpeg" | "image/webp" | "image/gif"
    ) {
        return Ok(None);
    }
    let mut bytes = vec![];
    while let Some(chunk) = response.chunk().await.map_err(|_| "Avatar unavailable")? {
        if bytes.len() + chunk.len() > 256 * 1024 {
            return Ok(None);
        }
        bytes.extend_from_slice(&chunk);
    }
    let data = format!(
        "data:{content_type};base64,{}",
        base64::engine::general_purpose::STANDARD.encode(bytes)
    );
    let mut cache = state.cache.lock().unwrap();
    if cache.len() >= 256 {
        cache.clear();
    }
    cache.insert(url, data.clone());
    Ok(Some(data))
}
