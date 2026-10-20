"""Decisions: 0 deny; 1 explore; 2 act; 3 hold. The Ada gate is mandatory."""
function guard_library()
    suffix = Sys.iswindows() ? ".dll" : (Sys.isapple() ? ".dylib" : ".so")
    base = joinpath(dirname(@__DIR__), "ada", "lib")
    path = joinpath(base, "libixbf_guard" * suffix)
    if !isfile(path) && Sys.iswindows()
        path = joinpath(base, "ixbf_guard.dll")
    end
    isfile(path) || error("ADA_GUARD_UNAVAILABLE: run gprbuild -p -P ada/ix_guard.gpr; fail closed")
    return abspath(path)
end

"""Use a native exported C ABI entrypoint. No Julia-side authorization fallback."""
function authorize(kind::Integer; permission::Integer=0, risk::Integer=3,
                   cost::Integer=0, budget::Integer=0, samples::Integer=0,
                   correct::Integer=0, cross_check::Integer=0)
    args = (kind, permission, risk, cost, budget, samples, correct, cross_check)
    all(x -> typemin(Cint) <= x <= typemax(Cint), args) || return 0
    lib = Libdl.dlopen(guard_library())
    try
        function_pointer = Libdl.dlsym(lib, :ixbf_check_proposal)
        result = ccall(function_pointer, Cint,
             (Cint,Cint,Cint,Cint,Cint,Cint,Cint,Cint),
             Cint(kind), Cint(permission), Cint(risk), Cint(cost), Cint(budget),
             Cint(samples), Cint(correct), Cint(cross_check))
        return Int(result)
    finally
        Libdl.dlclose(lib)
    end
end
