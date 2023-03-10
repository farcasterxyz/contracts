use std::process::Command;

// remove husky configuration from .git/config if it exists
fn main() {
    Command::new("git")
        .arg("config")
        .arg("--unset")
        .arg("core.hooksPath")
        .status()
        .expect("core.hooksPath failed to reset. You should manually run git config --unset core.hooksPath");
}
