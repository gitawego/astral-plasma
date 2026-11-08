//! The runner's own contract: order, idempotence, and refusing to continue past
//! a failure. Driven with explicit migrations so a broken one never ships.

use astral_plasma::application::migrations::{
    CompletedMigration, Migration, MigrationContext, MigrationOutcome, MigrationRunner,
};
use astral_plasma::domain::ports::DynResult;
use std::sync::Arc;

struct Recording {
    name: &'static str,
    log: Arc<std::sync::Mutex<Vec<&'static str>>>,
    outcome: MigrationOutcome,
}

impl Migration for Recording {
    fn name(&self) -> &'static str {
        self.name
    }
    fn describe(&self) -> &'static str {
        "records that it ran"
    }
    fn run(&self, _ctx: &MigrationContext) -> DynResult<MigrationOutcome> {
        self.log.lock().unwrap().push(self.name);
        Ok(self.outcome.clone())
    }
}

struct Failing {
    name: &'static str,
    log: Arc<std::sync::Mutex<Vec<&'static str>>>,
}

impl Migration for Failing {
    fn name(&self) -> &'static str {
        self.name
    }
    fn describe(&self) -> &'static str {
        "fails"
    }
    fn run(&self, _ctx: &MigrationContext) -> DynResult<MigrationOutcome> {
        self.log.lock().unwrap().push(self.name);
        Err("disk on fire".into())
    }
}

fn log() -> Arc<std::sync::Mutex<Vec<&'static str>>> {
    Arc::new(std::sync::Mutex::new(Vec::new()))
}

#[test]
fn migrations_run_in_order_and_only_once() {
    let root = tempfile::tempdir().unwrap();
    let ctx = MigrationContext::rooted_at(root.path());
    let log = log();

    let runner = MigrationRunner::with_migrations(
        ctx.marker_dir.clone(),
        vec![
            Box::new(Recording {
                name: "001_first",
                log: log.clone(),
                outcome: MigrationOutcome::Changed("first ran".into()),
            }),
            Box::new(Recording {
                name: "002_second",
                log: log.clone(),
                outcome: MigrationOutcome::AlreadySatisfied,
            }),
        ],
    );

    let first = runner.run_pending(&ctx).unwrap();
    assert_eq!(first.len(), 2);
    assert_eq!(*log.lock().unwrap(), vec!["001_first", "002_second"]);
    assert!(first[0].changed && first[0].message.as_deref() == Some("first ran"));
    assert!(
        !first[1].changed && first[1].message.is_none(),
        "AlreadySatisfied must not be reported as a repair"
    );

    let second = runner.run_pending(&ctx).unwrap();
    assert!(second.is_empty(), "markers make the second run a no-op");
    assert_eq!(log.lock().unwrap().len(), 2, "no migration ran twice");
}

#[test]
fn a_failure_names_itself_and_blocks_the_rest() {
    let root = tempfile::tempdir().unwrap();
    let ctx = MigrationContext::rooted_at(root.path());
    let log = log();

    let runner = MigrationRunner::with_migrations(
        ctx.marker_dir.clone(),
        vec![
            Box::new(Failing {
                name: "001_explodes",
                log: log.clone(),
            }),
            Box::new(Recording {
                name: "002_would_run",
                log: log.clone(),
                outcome: MigrationOutcome::Changed("ran".into()),
            }),
        ],
    );

    let err = runner.run_pending(&ctx).expect_err("a failure must propagate");
    assert!(
        err.to_string().contains("001_explodes") && err.to_string().contains("disk on fire"),
        "the error must name the migration and the reason: {err}"
    );
    assert_eq!(
        *log.lock().unwrap(),
        vec!["001_explodes"],
        "later migrations must not run after a failure"
    );
    assert!(
        !runner.marker_dir().join("001_explodes").exists(),
        "a failed migration must not be marked complete, or it would never retry"
    );
    assert_eq!(runner.pending().len(), 2, "both are still pending after the failure");
}

#[test]
fn a_marker_records_when_and_what() {
    let root = tempfile::tempdir().unwrap();
    let ctx = MigrationContext::rooted_at(root.path());
    let runner = MigrationRunner::with_migrations(
        ctx.marker_dir.clone(),
        vec![Box::new(Recording {
            name: "001_marked",
            log: log(),
            outcome: MigrationOutcome::Changed("done".into()),
        })],
    );

    runner.run_pending(&ctx).unwrap();
    let marker = std::fs::read_to_string(runner.marker_dir().join("001_marked")).unwrap();
    assert!(marker.contains("001_marked"));
    assert!(marker.contains("completed_at_unix"));
    assert!(marker.contains("done"), "the message is kept for later diagnosis: {marker}");
}

#[test]
fn completed_entries_serialize_for_the_cli() {
    let entry = CompletedMigration {
        name: "001_adopt_legacy_install".into(),
        changed: true,
        message: Some("adopted".into()),
    };
    let json = serde_json::to_string(&entry).unwrap();
    assert!(json.contains("\"changed\":true"));
    assert!(json.contains("\"message\":\"adopted\""));
}
