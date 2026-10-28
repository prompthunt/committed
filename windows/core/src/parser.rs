use chrono::{Duration, NaiveDate};
use scraper::{Html, Selector};
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
