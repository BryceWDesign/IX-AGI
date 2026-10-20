$ErrorActionPreference = 'Stop'
& gprbuild -p -P vendor/IXBlackFoxAGI/ada/ix_guard.gpr
if ($LASTEXITCODE -ne 0) { throw 'Native Ada gate build failed' }
& julia --project=vendor/IXBlackFoxAGI vendor/IXBlackFoxAGI/test/runtests.jl
if ($LASTEXITCODE -ne 0) { throw 'BlackFox donor regression tests failed' }
& julia --project=. test/runtests.jl
if ($LASTEXITCODE -ne 0) { throw 'IX-AGI native Julia tests failed' }
& julia --project=. bin/ixagi.jl
if ($LASTEXITCODE -ne 0) { throw 'IX-AGI runtime demo failed' }
& julia --project=. experiments/comparison.jl
if ($LASTEXITCODE -ne 0) { throw 'Native comparative campaign failed' }
