//! Pure calculations over one person's daily contribution counts: the Windows mirror of Swift's
//! `ContributionHistory`. Keys are GitHub's civil days and `today` is the local day from the
//! `Clock`, so nothing here reads the time or a time zone. Later tickets add month totals and
//! active days beside `total` and `current_streak`, with the same names as the Swift functions.
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

/// Consecutive days with at least one contribution, ending today, or ending yesterday when today
/// has none yet (a streak stays alive until today is over). A day missing from the calendar
/// counts as none, so a run that reaches the calendar's first day stops there: the result never
/// exceeds what the calendar shows. This is the raw count; the board shows it only from 2, and
/// above 365 as "365+".
pub fn current_streak(days: &BTreeMap<NaiveDate, u32>, today: NaiveDate) -> u32 {
    let contributed = |day: NaiveDate| days.get(&day).is_some_and(|count| *count > 0);
    let mut day = if contributed(today) {
        today
    } else {
        today - Duration::days(1)
    };
    let mut streak = 0;
    while contributed(day) {
        streak += 1;
        day -= Duration::days(1);
    }
    streak
}
