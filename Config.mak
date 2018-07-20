# Default goal for building this directory
.DEFAULT_GOAL := all

# DUB doesn't work well with flavors but there isn't any need in those
# for neptune apps anyway:
VALID_FLAVORS := dub

F := dub
