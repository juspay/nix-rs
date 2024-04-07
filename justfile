default:
    @just --list

# Auto-format the source tree
fmt:
    treefmt

# Compile and watch the project
w:
    cargo watch

test:
    cargo watch -s "cargo test"

changelog:
    convco changelog -p ""

