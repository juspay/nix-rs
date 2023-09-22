//! Information about the environment in which Nix will run
use std::{fmt::Display, path::Path};

use bytesize::ByteSize;
use os_info;
use serde::{Deserialize, Serialize};

use crate::flake::url::FlakeUrl;

/// The environment in which Nix operates
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NixEnv {
    /// Current user ($USER)
    pub current_user: String,
    /// Current flake context
    pub current_flake: Option<FlakeUrl>,
    /// Underlying OS in which Nix runs
    pub os: OS,
    /// Total disk space of the volume where /nix exists.
    ///
    /// This is either root volume or the dedicated /nix volume.
    pub total_disk_space: ByteSize,
    /// Total memory
    pub total_memory: ByteSize,
}

impl NixEnv {
    /// Determine [NixEnv] on the user's system
    #[cfg(feature = "ssr")]
    pub async fn detect(current_flake: Option<FlakeUrl>) -> Result<NixEnv, NixEnvError> {
        use sysinfo::{DiskExt, SystemExt};
        let current_user = std::env::var("USER")?;
        let os = OS::detect().await;
        let sys = sysinfo::System::new_with_specifics(
            sysinfo::RefreshKind::new().with_disks_list().with_memory(),
        );
        let total_disk_space = to_bytesize(get_nix_disk(&sys)?.total_space());
        let total_memory = to_bytesize(sys.total_memory());
        Ok(NixEnv {
            current_user,
            current_flake,
            os,
            total_disk_space,
            total_memory,
        })
    }

    /// Return [NixEnv::current_flake] as a local path if it is one
    pub fn current_local_flake(&self) -> Option<&Path> {
        self.current_flake
            .as_ref()
            .and_then(|url| url.as_local_path())
    }
}

/// Get the disk where /nix exists
#[cfg(feature = "ssr")]
fn get_nix_disk(sys: &sysinfo::System) -> Result<&sysinfo::Disk, NixEnvError> {
    use sysinfo::{DiskExt, SystemExt};
    let by_mount_point: std::collections::HashMap<&Path, &sysinfo::Disk> = sys
        .disks()
        .iter()
        .map(|disk| (disk.mount_point(), disk))
        .collect();
    // Lookup /nix first, then /.
    by_mount_point
        .get(Path::new("/nix"))
        .copied()
        .or_else(|| by_mount_point.get(Path::new("/")).copied())
        .ok_or(NixEnvError::NoDisk)
}

/// The system under which Nix is installed and operates
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum OS {
    /// On macOS
    MacOS {
        /// Using https://github.com/LnL7/nix-darwin
        nix_darwin: bool,
        arch: MacOSArch,
    },
    /// https://nixos.org/
    NixOS,
    /// Nix is individually installed on Linux or macOS
    Other(os_info::Type),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum MacOSArch {
    Arm64(AppleEmulation),
    Other(Option<String>),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum AppleEmulation {
    None,
    Rosetta,
}

impl AppleEmulation {
    #[cfg(feature = "ssr")]
    pub fn new() -> Self {
        use is_proc_translated::is_proc_translated;
        if is_proc_translated() {
            AppleEmulation::Rosetta
        } else {
            AppleEmulation::None
        }
    }
}

#[cfg(feature = "ssr")]
impl Default for AppleEmulation {
    fn default() -> Self {
        Self::new()
    }
}

impl MacOSArch {
    #[cfg(feature = "ssr")]
    pub fn from(os_arch: Option<&str>) -> MacOSArch {
        match os_arch {
            Some("arm64") => MacOSArch::Arm64(AppleEmulation::new()),
            other => MacOSArch::Other(other.map(|s| s.to_string())),
        }
    }
}

impl Display for OS {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            OS::MacOS {
                nix_darwin,
                arch: _,
            } => {
                if *nix_darwin {
                    write!(f, "nix-darwin")
                } else {
                    write!(f, "macOS")
                }
            }
            OS::NixOS => write!(f, "NixOS"),
            OS::Other(os_type) => write!(f, "{}", os_type),
        }
    }
}

impl OS {
    #[cfg(feature = "ssr")]
    pub async fn detect() -> Self {
        let os_info = tokio::task::spawn_blocking(os_info::get).await.unwrap();
        let os_type = os_info.os_type();
        let arch = MacOSArch::from(os_info.architecture());
        async fn is_symlink(file_path: &str) -> std::io::Result<bool> {
            let metadata = tokio::fs::symlink_metadata(file_path).await?;
            Ok(metadata.file_type().is_symlink())
        }
        match os_type {
            os_info::Type::Macos => {
                // To detect that we are on NixDarwin, we check if /etc/nix/nix.conf
                // is a symlink (which nix-darwin manages like NixOS does)
                let nix_darwin = is_symlink("/etc/nix/nix.conf").await.unwrap_or(false);
                OS::MacOS { nix_darwin, arch }
            }
            os_info::Type::NixOS => OS::NixOS,
            _ => OS::Other(os_type),
        }
    }

    /// The Nix for this [OS] is configured automatically through a `configuration.nix`
    pub fn has_configuration_nix(&self) -> bool {
        match self {
            OS::MacOS {
                nix_darwin,
                arch: _,
            } if *nix_darwin => true,
            OS::NixOS => true,
            _ => false,
        }
    }
}

/// Errors while trying to fetch [NixEnv]
#[cfg(feature = "ssr")]
#[derive(thiserror::Error, Debug)]
pub enum NixEnvError {
    #[error("Failed to fetch ENV: {0}")]
    EnvVarError(#[from] std::env::VarError),

    #[error("Unable to find root disk or /nix volume")]
    NoDisk,
}

/// Convert bytes to a closest [ByteSize]
///
/// Useful for displaying disk space and memory which are typically in GBs / TBs
#[cfg(feature = "ssr")]
fn to_bytesize(bytes: u64) -> ByteSize {
    let kb = bytes / 1024;
    let mb = kb / 1024;
    let gb = mb / 1024;
    if gb > 0 {
        ByteSize::gib(gb)
    } else if mb > 0 {
        ByteSize::mib(mb)
    } else if kb > 0 {
        ByteSize::kib(kb)
    } else {
        ByteSize::b(bytes)
    }
}

/// Test for [to_bytesize]
#[cfg(feature = "ssr")]
#[test]
fn test_to_bytesize() {
    assert_eq!(to_bytesize(0), ByteSize::b(0));
    assert_eq!(to_bytesize(1), ByteSize::b(1));
    assert_eq!(to_bytesize(1023), ByteSize::b(1023));
    assert_eq!(to_bytesize(1024), ByteSize::kib(1));
    assert_eq!(to_bytesize(1024 * 1024), ByteSize::mib(1));
    assert_eq!(to_bytesize(1024 * 1024 * 1024), ByteSize::gib(1));
}
