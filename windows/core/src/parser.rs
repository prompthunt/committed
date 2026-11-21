use chrono::NaiveDate;
use scraper::{Html, Selector};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

fn count(label: &str) -> Option<u32> {
    let label = label.trim().to_ascii_lowercase();
    if label.starts_with("no contributions") {
        return Some(0);
    }
    let mut words = label.split_whitespace();
    let number = words.next()?.replace(',', "").parse().ok()?;
    words.next()?.starts_with("contribution").then_some(number)
}
pub fn parse(html: &str) -> Result<BTreeMap<NaiveDate, u32>, String> {
    let doc = Html::parse_fragment(html);
    let tooltips: BTreeMap<_, _> = doc
        .select(&Selector::parse("tool-tip[for]").unwrap())
        .filter_map(|node| {
            Some((
                node.value().attr("for")?.to_string(),
                count(&node.text().collect::<String>())?,
            ))
        })
        .collect();
    let mut days = BTreeMap::new();
    // HTML parsers discard orphan td elements outside tables. Wrap legacy fixtures,
    // and parse the full response this way too so both GitHub forms behave alike.
    let wrapped = Html::parse_document(&format!("<table>{html}</table>"));
    for node in wrapped.select(&Selector::parse("td[data-date]").unwrap()) {
        let Some(date) = node
            .value()
            .attr("data-date")
            .and_then(|d| NaiveDate::parse_from_str(d, "%Y-%m-%d").ok())
        else {
            continue;
        };
        let direct = node.value().attr("data-count").and_then(|s| s.parse().ok());
        let tooltip = node
            .value()
            .attr("id")
            .and_then(|id| tooltips.get(id).copied());
        let label = node.value().attr("aria-label").and_then(count).or_else(|| {
            node.select(&Selector::parse("[aria-label]").unwrap())
                .find_map(|n| n.value().attr("aria-label").and_then(count))
        });
        if let Some(count) = direct.or(tooltip).or(label) {
            days.insert(date, count);
        }
    }
    if days.is_empty() {
        Err("No day counts resolved".into())
    } else {
        Ok(days)
    }
}
/// Five-minute polling with one minute of leeway. Matches Swift's `TrollCheck`.
pub const MAX_BURST_INTERVAL: i64 = 360;
/// A burst is more than this many times the person's usual big day…
pub const TROLL_MULTIPLE: u32 = 5;
/// …and more than this many contributions. Matches the Mac and iPhone (`TrollCheck`).
pub const TROLL_FLOOR: u32 = 100;

/// An increase observed between two closely spaced calendar reads on the same day.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct Burst {
    pub date: NaiveDate,
    pub count: u32,
    /// Their usual big day before it: the count 9 in 10 of their earlier active days stay under.
    pub usual: u32,
}

/// The count 9 in 10 of these days' active (non-zero) days stay under; 0 with none.
pub fn usual_big_day(counts: impl Iterator<Item = u32>) -> u32 {
    let mut active: Vec<u32> = counts.filter(|&count| count > 0).collect();
    if active.is_empty() {
        return 0;
    }
    active.sort_unstable();
    let index = (active.len() as f64 * 0.9) as usize;
    active[index.min(active.len() - 1)]
}

/// Check the increase between two successful reads of today's cell.
pub fn observed_burst(
    days: &BTreeMap<NaiveDate, u32>,
    today: NaiveDate,
    previous_count: u32,
) -> Option<Burst> {
    let increase = days.get(&today)?.saturating_sub(previous_count);
    if increase <= TROLL_FLOOR {
        return None;
    }
    let usual = usual_big_day(days.range(..today).map(|(_, &count)| count));
    (increase > TROLL_MULTIPLE.saturating_mul(usual)).then_some(Burst {
        date: today,
        count: increase,
        usual,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn day(d: u32) -> NaiveDate {
        NaiveDate::from_ymd_opt(2026, 5, d).unwrap()
    }
    /// May 1–27 at a steady 20 a day.
    fn steady(count: u32) -> BTreeMap<NaiveDate, u32> {
        (1..=27).map(|d| (day(d), count)).collect()
    }

    #[test]
    fn unreadable_cell_is_not_an_observed_zero() {
        let html = r#"<td data-date="2026-05-27" data-count="0"></td>
            <td data-date="2026-05-28" id="unresolved"></td>
            <tool-tip for="unresolved">Contribution data unavailable</tool-tip>"#;
        assert_eq!(parse(html).unwrap(), BTreeMap::from([(day(27), 0)]));
    }

    fn observe(
        count: u32,
        time: i64,
        date: NaiveDate,
        prior: Option<&crate::Snapshot>,
    ) -> crate::Snapshot {
        let mut days = steady(20);
        days.insert(date, count);
        crate::Snapshot::from_refresh(days, time, date, prior)
    }

    #[test]
    fn flags_the_increase_between_close_reads() {
        let first = observe(19, 1_000, day(28), None);
        let second = observe(803, 1_360, day(28), Some(&first));
        assert_eq!(
            second.burst(crate::Window::Today, day(28)),
            Some(Burst {
                date: day(28),
                count: 784,
                usual: 20
            })
        );
    }

    #[test]
    fn ignores_first_reads_long_gaps_and_day_boundaries() {
        let first = observe(803, 1_000, day(28), None);
        assert!(first.burst(crate::Window::Today, day(28)).is_none());
        let prior = observe(19, 1_000, day(28), None);
        let later = observe(803, 1_361, day(28), Some(&prior));
        assert!(later.burst(crate::Window::Today, day(28)).is_none());
        let tomorrow = observe(803, 1_060, day(29), Some(&prior));
        assert!(tomorrow.burst(crate::Window::Today, day(29)).is_none());
    }

    #[test]
    fn ignores_a_total_of_803_accumulated_gradually() {
        let mut prior = None;
        for (index, count) in (3..=803).step_by(100).enumerate() {
            let snapshot = observe(count, 1_000 + index as i64 * 300, day(28), prior.as_ref());
            assert!(snapshot.burst(crate::Window::Today, day(28)).is_none());
            prior = Some(snapshot);
        }
        assert_eq!(prior.unwrap().days.get(&day(28)), Some(&803));
    }

    #[test]
    fn keeps_the_floor_and_usual_day_threshold() {
        let mut days = steady(40);
        days.insert(day(28), 240);
        assert_eq!(observed_burst(&days, day(28), 40), None);
        let mut days = steady(2);
        days.insert(day(28), 100);
        assert_eq!(observed_burst(&days, day(28), 0), None);
        days.insert(day(28), 101);
        assert_eq!(
            observed_burst(&days, day(28), 0).map(|b| b.count),
            Some(101)
        );
        assert_eq!(observed_burst(&days, day(28), 102), None);
    }

    #[test]
    fn keeps_observed_bursts_in_longer_windows() {
        let first = observe(19, 1_000, day(28), None);
        let burst = observe(803, 1_300, day(28), Some(&first));
        let tomorrow = observe(20, 90_000, day(29), Some(&burst));
        assert!(tomorrow.burst(crate::Window::Today, day(29)).is_none());
        assert_eq!(
            tomorrow.burst(crate::Window::Week, day(29)).unwrap().count,
            784
        );
        let next_week = NaiveDate::from_ymd_opt(2026, 6, 4).unwrap();
        assert!(tomorrow.burst(crate::Window::Week, next_week).is_none());
        assert!(tomorrow.burst(crate::Window::Monthly, next_week).is_some());
    }

    #[test]
    fn usual_big_day_is_the_ninetieth_percentile_of_active_days() {
        assert_eq!(usual_big_day([].into_iter()), 0);
        assert_eq!(usual_big_day(1..=10), 10);
        assert_eq!(usual_big_day([0].into_iter().chain(1..=20)), 19);
    }
}
