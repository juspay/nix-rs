default:
    @just --list

# Auto-format the source tree
fmt:
    treefmt

# Compile and watch the project
w:
    cargo watch

changelog:
    convco changelog -p ""
