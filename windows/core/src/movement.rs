use super::*;

/// The Windows whose rows show movement since the first refresh of the day.
const MOVEMENT_WINDOWS: [Window; 2] = [Window::Today, Window::ThisMonth];

pub(crate) fn finish_refresh(state: &mut State, today: NaiveDate, now: i64) -> Vec<Notification> {
    for window in MOVEMENT_WINDOWS {
        if state
            .baselines
            .get(&window)
            .is_some_and(|(day, _)| *day == today)
        {
            continue;
        }
        let ranks: BTreeMap<String, usize> = ranked_rows(state, window, today, now)
            .iter()
            .filter(|r| r.contributions.is_some() && !state.failed.contains_key(&r.person.login))
            .map(|r| (r.person.login.clone(), r.rank))
            .collect();
        if !ranks.is_empty() {
            state.baselines.insert(window, (today, ranks));
        }
    }
    let month_final = month_final(state, today);
    let mut notifications = rank_changes(state, today, now);
    notifications.splice(0..0, month_final);
    notifications
}

/// "October final: you finished #3 of 8", once per finished month per account on this PC, on the
/// first refresh where every saved calendar reloads.
/// The month counts as handled even with Leaderboard Notifications off, so turning them on later
/// in the month doesn't send a stale result; only the posting needs them on.
fn month_final(state: &mut State, today: NaiveDate) -> Option<Notification> {
    let owner = state.saved.owner.clone()?;
    let month = previous_month(today);
    if state.saved.announced.get(&owner) >= Some(&month) {
        return None;
    }
    // Someone whose saved calendar didn't refresh may be missing the end of last month. Someone
    // who has never loaded can't hold it back, or a page that always fails would block it forever.
    let stale = state.saved.people.iter().any(|p| {
        !state.saved.hidden(&p.login)
            && state.failed.contains_key(&p.login)
            && state.saved.counts.contains_key(&p.login)
    });
    if stale {
        return None;
    }
    let standings = final_standings(state, month, today)?;
    let mine = standings.rows.iter().find(|row| row.is_you)?;
    let notification = Notification {
        title: format!("{} final", standings.month_name),
        body: format!("You finished #{} of {}", mine.rank, standings.rows.len()),
    };
    state.saved.announced.insert(owner, month);
    state.saved.settings.notifications.then_some(notification)
}

/// Rank changes in the selected Window since the last refresh today.
fn rank_changes(state: &mut State, today: NaiveDate, now: i64) -> Vec<Notification> {
    let window = state.selected;
    let current: BTreeMap<_, _> = ranked_rows(state, window, today, now)
        .iter()
        .filter(|r| !state.failed.contains_key(&r.person.login))
        .filter_map(|r| Some((r.person.login.clone(), r.contributions?)))
        .collect();
    let previous = state.previous.insert(window, (today, current.clone()));
    if !state.saved.settings.notifications {
        return vec![];
    }
    let Some((_, previous)) = previous.filter(|(day, _)| *day == today) else {
        return vec![];
    };
    let Some(owner) = &state.saved.owner else {
        return vec![];
    };
    let (Some(&before), Some(&now)) = (previous.get(owner), current.get(owner)) else {
        return vec![];
    };
    let mut notifications = vec![];
    for (login, &rival_now) in &current {
        if login == owner {
            continue;
        }
        let Some(&rival_before) = previous.get(login) else {
            continue;
        };
        if rival_before <= before && rival_now > now {
            notifications.push(Notification {
                title: format!("😤 {login} passed you"),
                body: format!("They're ahead {rival_now}–{now}. Time to catch up!"),
            });
        } else if rival_before >= before && rival_now < now {
            notifications.push(Notification {
                title: format!("🎉 You passed {login}!"),
                body: format!("You're ahead {now}–{rival_now}. Keep climbing!"),
            });
        }
    }
    // Match NotificationService on the Mac: summarize a flurry of more than three.
    if notifications.len() > 3 {
        vec![Notification {
            title: format!("{} position changes", notifications.len()),
            body: "Your standings shifted since the last check.".into(),
        }]
    } else {
        notifications
    }
}
