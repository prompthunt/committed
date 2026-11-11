use chrono::{Duration, NaiveDate};
use scraper::{Html, Selector};
use serde::Serialize;
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
                count(&node.text().collect::<String>()).unwrap_or(0),
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
        days.insert(date, direct.or(tooltip).or(label).unwrap_or(0));
    }
    if days.is_empty() {
        Err("No day cells found".into())
    } else {
        Ok(days)
    }
}
pub fn sum(days: &BTreeMap<NaiveDate, u32>, length: i64, today: NaiveDate) -> u32 {
    days.range((today - Duration::days(length - 1))..=today)
        .map(|(_, count)| count)
        .sum()
}

/// A trolling day is more than this many times the person's usual big day…
pub const TROLL_MULTIPLE: u32 = 5;
/// …and more than this many contributions. Matches the Mac and iPhone (`TrollCheck`).
pub const TROLL_FLOOR: u32 = 100;

/// One day far above someone's usual. The board marks the row with the troll face; it
/// doesn't change the count or the rank.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
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

/// The window's biggest trolling day, each day judged only against the days before it.
pub fn burst(days: &BTreeMap<NaiveDate, u32>, length: i64, today: NaiveDate) -> Option<Burst> {
    let earliest = today - Duration::days(length - 1);
    days.range(earliest..=today)
        .filter(|(_, &count)| count > TROLL_FLOOR)
        .filter_map(|(&date, &count)| {
            let usual = usual_big_day(days.range(..date).map(|(_, &c)| c));
            (count > TROLL_FLOOR.max(TROLL_MULTIPLE.saturating_mul(usual)))
                .then_some(Burst { date, count, usual })
        })
        .max_by_key(|burst| burst.count)
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
    fn flags_a_day_far_above_their_usual_big_day() {
        let mut days = steady(20);
        days.insert(day(28), 784);
        assert_eq!(burst(&days, 1, day(28)), Some(Burst { date: day(28), count: 784, usual: 20 }));
    }

    #[test]
    fn five_times_usual_is_not_over_the_line() {
        let mut days = steady(40);
        days.insert(day(28), 200);
        assert_eq!(burst(&days, 1, day(28)), None);
    }

    #[test]
    fn needs_more_than_a_hundred() {
        let mut days = steady(2);
        days.insert(day(28), 100);
        assert_eq!(burst(&days, 1, day(28)), None);
        days.insert(day(28), 101);
        assert_eq!(burst(&days, 1, day(28)).map(|b| b.count), Some(101));
    }

    #[test]
    fn stays_in_longer_windows_until_the_day_leaves() {
        let mut days = steady(20);
        days.insert(day(25), 500);
        days.insert(day(28), 20);
        assert_eq!(burst(&days, 1, day(28)), None);
        assert_eq!(burst(&days, 7, day(28)).map(|b| b.date), Some(day(25)));
    }

    #[test]
    fn a_later_day_does_not_raise_the_bar_for_an_earlier_one() {
        let mut days = steady(20);
        days.insert(day(27), 300);
        days.insert(day(28), 5_000);
        assert_eq!(burst(&days, 1, day(27)).map(|b| b.usual), Some(20));
        assert_eq!(burst(&days, 7, day(28)).map(|b| b.count), Some(5_000));
    }

    #[test]
    fn usual_big_day_is_the_ninetieth_percentile_of_active_days() {
        assert_eq!(usual_big_day([].into_iter()), 0);
        assert_eq!(usual_big_day((1..=10).into_iter()), 10);
        assert_eq!(usual_big_day([0].into_iter().chain(1..=20)), 19);
    }
}
