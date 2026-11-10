//! Pure calculations over one person's daily contribution counts: the Windows mirror of Swift's
//! `ContributionHistory`. Keys are GitHub's civil days and `today` is the local day from the
//! `Clock`, so nothing here reads the time or a time zone. Later tickets add streaks, month
//! totals and active days beside `total`, with the same names as the Swift functions.
use crate::Window;
use chrono::{Duration, NaiveDate};
use std::collections::BTreeMap;

/// Contributions in `window` as of `today`, inclusive: today and the `window.days() - 1` days
/// before it. Days after `today` are never counted, and a day missing from the calendar adds 0.
pub fn total(days: &BTreeMap<NaiveDate, u32>, window: Window, today: NaiveDate) -> u32 {
    days.range((today - Duration::days(window.days() - 1))..=today)
        .map(|(_, count)| count)
        .sum()
}
