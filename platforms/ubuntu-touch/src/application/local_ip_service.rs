// SPDX-License-Identifier: Apache-2.0
//
// Enumerates the device's local IPv4 addresses.
// Mirrors the ranking logic in app/lib/provider/local_ip_provider.dart
// (_rankIpAddresses): non-.1 addresses first, .1 last.

use if_addrs::IfAddr;

/// Returns local IPv4 addresses, ranked.
///
/// - `whitelist`: if `Some`, only interfaces in this list are included.
/// - `blacklist`: if `Some`, interfaces in this list are excluded.
///
/// Whitelist and blacklist entries are matched against the interface name
/// (e.g. "wlan0", "eth0"). Matching is case-sensitive for now; Flutter's
/// implementation is also name-based.
pub fn list_local_ips(
    whitelist: Option<&[String]>,
    blacklist: Option<&[String]>,
) -> Vec<String> {
    let ifaces = match if_addrs::get_if_addrs() {
        Ok(v) => v,
        Err(e) => {
            log::warn!("get_if_addrs failed: {e}");
            return Vec::new();
        }
    };

    let mut out: Vec<String> = Vec::new();
    for iface in ifaces {
        let name = &iface.name;

        if let Some(wl) = whitelist {
            if !wl.iter().any(|n| n == name) {
                continue;
            }
        }
        if let Some(bl) = blacklist {
            if bl.iter().any(|n| n == name) {
                continue;
            }
        }

        if let IfAddr::V4(v4) = iface.addr {
            // Skip loopback and link-local (169.254.x.x).
            if v4.ip.is_loopback() || v4.ip.is_link_local() {
                continue;
            }
            out.push(v4.ip.to_string());
        }
    }

    rank_ips(&mut out);
    out
}

/// Sort in place: non-.1 first, .1 last, then alphabetical for stability.
fn rank_ips(ips: &mut Vec<String>) {
    ips.sort_by(|a, b| {
        let sa = score(a);
        let sb = score(b);
        sb.cmp(&sa).then_with(|| a.cmp(b))
    });
}

fn score(ip: &str) -> u8 {
    if ip.ends_with(".1") {
        0
    } else {
        1
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rank_puts_dot_one_last() {
        let mut v = vec![
            "192.168.1.1".to_string(),
            "10.0.0.42".to_string(),
            "172.16.5.7".to_string(),
        ];
        rank_ips(&mut v);
        assert_eq!(v.last().unwrap(), "192.168.1.1");
    }

    #[test]
    fn score_basic() {
        assert_eq!(score("10.0.0.42"), 1);
        assert_eq!(score("10.0.0.1"), 0);
    }
}