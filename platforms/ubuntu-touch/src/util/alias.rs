// SPDX-License-Identifier: Apache-2.0
//
// Random device alias ("Adjective Fruit"), ported from the Flutter app
// (app/lib/util/alias_generator.dart).
//
// The Flutter app generates a random alias on the first start, so two
// devices never look like the same one. The Ubuntu Touch frontend used a
// fixed "LocalSend" alias, which made the own device look like the peer
// in the device list.

/// Alias used by the frontend before the random generator existed.
///
/// Devices that still carry it are migrated to a random alias on startup,
/// otherwise they would keep showing up as "LocalSend" next to the peer.
pub const LEGACY_DEFAULT_ALIAS: &str = "LocalSend";

/// Same list as `aliasGenerator.adjectives` in app/assets/i18n/en.json.
const ADJECTIVES: &[&str] = &[
    "Adorable",
    "Beautiful",
    "Big",
    "Bright",
    "Clean",
    "Clever",
    "Cool",
    "Cute",
    "Cunning",
    "Determined",
    "Energetic",
    "Efficient",
    "Fantastic",
    "Fast",
    "Fine",
    "Fresh",
    "Good",
    "Gorgeous",
    "Great",
    "Handsome",
    "Hot",
    "Kind",
    "Lovely",
    "Mystic",
    "Neat",
    "Nice",
    "Patient",
    "Pretty",
    "Powerful",
    "Rich",
    "Secret",
    "Smart",
    "Solid",
    "Special",
    "Strategic",
    "Strong",
    "Tidy",
    "Wise",
];

/// Same list as `aliasGenerator.fruits` in app/assets/i18n/en.json.
const FRUITS: &[&str] = &[
    "Apple",
    "Avocado",
    "Banana",
    "Blackberry",
    "Blueberry",
    "Broccoli",
    "Carrot",
    "Cherry",
    "Coconut",
    "Grape",
    "Lemon",
    "Lettuce",
    "Mango",
    "Melon",
    "Mushroom",
    "Onion",
    "Orange",
    "Papaya",
    "Peach",
    "Pear",
    "Pineapple",
    "Potato",
    "Pumpkin",
    "Raspberry",
    "Strawberry",
    "Tomato",
];

/// xorshift64* — the frontend has no `rand` dependency and only needs a
/// couple of random indices.
fn next_index(seed: &mut u64, len: usize) -> usize {
    let mut x = *seed;
    x ^= x >> 12;
    x ^= x << 25;
    x ^= x >> 27;
    *seed = x;
    ((x.wrapping_mul(0x2545_F491_4F6C_DD1D) >> 33) as usize) % len
}

fn seed() -> u64 {
    use std::sync::atomic::{AtomicU64, Ordering};
    static COUNTER: AtomicU64 = AtomicU64::new(0);

    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_nanos() as u64)
        .unwrap_or(0x9E37_79B9_7F4A_7C15);
    // Mix in the pid and a counter so two calls (even within the same
    // nanosecond) never produce the same alias.
    let counter = COUNTER.fetch_add(1, Ordering::Relaxed);
    nanos
        ^ ((std::process::id() as u64) << 32)
        ^ counter.wrapping_mul(0x9E37_79B9_7F4A_7C15)
}

/// A random alias like "Energetic Banana".
pub fn random_alias() -> String {
    let mut seed = seed();
    // A zero seed would make xorshift stuck on zero.
    if seed == 0 {
        seed = 0x9E37_79B9_7F4A_7C15;
    }
    let adjective = ADJECTIVES[next_index(&mut seed, ADJECTIVES.len())];
    let fruit = FRUITS[next_index(&mut seed, FRUITS.len())];
    format!("{adjective} {fruit}")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn alias_has_the_fluutter_shape() {
        let alias = random_alias();
        let (adjective, fruit) = alias.split_once(' ').expect("alias has two words");
        assert!(ADJECTIVES.contains(&adjective), "unknown adjective: {adjective}");
        assert!(FRUITS.contains(&fruit), "unknown fruit: {fruit}");
    }

    #[test]
    fn alias_is_not_the_legacy_default() {
        assert_ne!(random_alias(), LEGACY_DEFAULT_ALIAS);
    }

    #[test]
    fn consecutive_aliases_differ() {
        // The seed is time based, so two calls in a row must not collide.
        let a = random_alias();
        let b = random_alias();
        assert_ne!(a, b);
    }
}
