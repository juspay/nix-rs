default:
    @just --list

# Auto-format the source tree
fmt:
    treefmt

changelog:
    convco changelog -p ""
