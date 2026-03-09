use crate::settings::is_newer_version;
use reqwest::Client;
use std::time::Duration;

const VERSION_URL: &str = "https://dict.tianxu.cloud/version";
const DOWNLOAD_URL: &str = "https://dict.studio/Dict.dmg";
const CURRENT_VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub enum UpdateResult {
    UpdateAvailable {
        remote_version: String,
        current_version: String,
        download_url: String,
    },
    UpToDate {
        current_version: String,
    },
    Error {
        message: String,
    },
}

/// Check for updates by comparing local version against remote
pub async fn check_for_update() -> UpdateResult {
    let client = Client::new();

    let resp = match client
        .get(VERSION_URL)
        .timeout(Duration::from_secs(10))
        .send()
        .await
    {
        Ok(r) => r,
        Err(e) => {
            tracing::warn!("Update check failed: {}", e);
            return UpdateResult::Error {
                message: "Could not connect to the update server.".to_string(),
            };
        }
    };

    let remote_version = match resp.text().await {
        Ok(t) => t.trim().to_string(),
        Err(e) => {
            tracing::warn!("Failed to read version response: {}", e);
            return UpdateResult::Error {
                message: "Could not read version response.".to_string(),
            };
        }
    };

    if remote_version.is_empty() {
        return UpdateResult::Error {
            message: "Empty version response.".to_string(),
        };
    }

    if is_newer_version(&remote_version, CURRENT_VERSION) {
        tracing::info!(
            "Update available: v{} (current: v{})",
            remote_version,
            CURRENT_VERSION
        );
        UpdateResult::UpdateAvailable {
            remote_version,
            current_version: CURRENT_VERSION.to_string(),
            download_url: DOWNLOAD_URL.to_string(),
        }
    } else {
        tracing::info!("Up to date (v{})", CURRENT_VERSION);
        UpdateResult::UpToDate {
            current_version: CURRENT_VERSION.to_string(),
        }
    }
}
