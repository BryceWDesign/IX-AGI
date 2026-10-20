#!/usr/bin/env bash
set -euo pipefail
gprbuild -p -P vendor/IXBlackFoxAGI/ada/ix_guard.gpr
julia --project=vendor/IXBlackFoxAGI vendor/IXBlackFoxAGI/test/runtests.jl
julia --project=. test/runtests.jl
julia --project=. bin/ixagi.jl
julia --project=. experiments/comparison.jl
