using Compat.Test

export createEmptyAtmosphere
"Returns empty ocean type for initialization purposes."
function createEmptyAtmosphere()
    return Atmosphere(false,

                      zeros(1),

                      zeros(1,1),
                      zeros(1,1),
                      zeros(1,1),
                      zeros(1,1),

                      zeros(1),

                      zeros(1,1,1,1),
                      zeros(1,1,1,1),

                      Array{Vector{Int}}(1, 1),

                      1, 1, 1, 1,

                      false,

                      false, [1.,1.,1.], [1,1,1], [1.,1.,1.])
end

export interpolateAtmosphereVelocitiesToCorners
"""
Convert gridded data from Arakawa-C type (decomposed velocities at faces) to 
Arakawa-B type (velocities at corners) through interpolation.
"""
function interpolateAtmosphereVelocitiesToCorners(u_in::Array{Float64, 4},
                                                  v_in::Array{Float64, 4})

    if size(u_in) != size(v_in)
        error("size of u_in ($(size(u_in))) must match v_in ($(size(v_in)))")
    end

    nx, ny, nz, nt = size(u_in)
    #u = Array{Float64}(nx+1, ny+1, nz, nt)
    #v = Array{Float64}(nx+1, ny+1, nz, nt)
    u = zeros(nx+1, ny+1, nz, nt)
    v = zeros(nx+1, ny+1, nz, nt)
    for i=1:nx
        for j=1:ny
            if j < ny - 1
                u[i, j, :, :] = (u_in[i, j, :, :] + u_in[i, j+1, :, :])/2.
            else
                u[i, j, :, :] = u_in[i, j, :, :]
            end
            if i < nx - 1
                v[i, j, :, :] = (v_in[i, j, :, :] + v_in[i+1, j, :, :])/2.
            else
                v[i, j, :, :] = v_in[i, j, :, :]
            end
        end
    end
    return u, v
end

export interpolateAtmosphereState
"""
Atmosphere data is containted in `Atmosphere` type at discrete times 
(`Atmosphere.time`).  This function performs linear interpolation between time 
steps to get the approximate atmosphere state at any point in time.  If the 
`Atmosphere` data set only contains a single time step, values from that time 
are returned.
"""
function interpolateAtmosphereState(atmosphere::Atmosphere, t::Float64)
    if length(atmosphere.time) == 1
        return atmosphere.u, atmosphere.v
    elseif t < atmosphere.time[1] || t > atmosphere.time[end]
        error("selected time (t = $(t)) is outside the range of time steps in 
              the atmosphere data")
    end

    i = 1
    rel_time = 0.
    while i < length(atmosphere.time)
        if atmosphere.time[i+1] < t
            i += 1
            continue
        end

        dt = atmosphere.time[i+1] - atmosphere.time[i]
        rel_time = (t - atmosphere.time[i])/dt
        if rel_time < 0. || rel_time > 1.
            error("time bounds error")
        end
        break
    end

    return atmosphere.u[:,:,:,i]*(1. - rel_time) +
        atmosphere.u[:,:,:,i+1]*rel_time,
        atmosphere.v[:,:,:,i]*(1. - rel_time) +
        atmosphere.v[:,:,:,i+1]*rel_time
end

export createRegularAtmosphereGrid
"""
Initialize and return a regular, Cartesian `Atmosphere` grid with `n[1]` by `n[2]` 
cells in the horizontal dimension, and `n[3]` vertical cells.  The cell corner 
and center coordinates will be set according to the grid spatial dimensions 
`L[1]`, `L[2]`, and `L[3]`.  The grid `u`, `v`, `h`, and `e` fields will contain 
one 4-th dimension matrix per `time` step.  Sea surface will be at `z=0.` with 
the atmosphere spanning `z<0.`.  Vertical indexing starts with `k=0` at the sea 
surface, and increases downwards.
"""
function createRegularAtmosphereGrid(n::Vector{Int},
                                     L::Vector{Float64};
                                     origo::Vector{Float64} = zeros(2),
                                     time::Array{Float64, 1} = zeros(1),
                                     name::String = "unnamed",
                                     bc_west::Integer = 1,
                                     bc_south::Integer = 1,
                                     bc_east::Integer = 1,
                                     bc_north::Integer = 1)

    xq = repmat(linspace(origo[1], origo[1] + L[1], n[1] + 1), 1, n[2] + 1)
    yq = repmat(linspace(origo[2], origo[2] + L[2], n[2] + 1)', n[1] + 1, 1)

    dx = L./n
    xh = repmat(linspace(origo[1] + .5*dx[1], origo[1] + L[1] - .5*dx[1],
                         n[1]), 1, n[2])
    yh = repmat(linspace(origo[2] + .5*dx[2], origo[1] + L[2] - .5*dx[2],
                         n[2])', n[1], 1)

    zl = -linspace(.5*dx[3], L[3] - .5*dx[3], n[3])

    u = zeros(n[1] + 1, n[2] + 1, n[3], length(time))
    v = zeros(n[1] + 1, n[2] + 1, n[3], length(time))

    return Atmosphere(name,
                 time,
                 xq, yq,
                 xh, yh,
                 zl,
                 u, v,
                 Array{Array{Int, 1}}(size(xh, 1), size(xh, 2)),
                 bc_west, bc_south, bc_east, bc_north,
                 false,
                 true, L, n, dx)
end

export addAtmosphereDrag!
"""
Add drag from linear and angular velocity difference between atmosphere and all 
grains.
"""
function addAtmosphereDrag!(simulation::Simulation)
    if typeof(simulation.atmosphere.input_file) == Bool
        error("no atmosphere data read")
    end

    u, v = interpolateAtmosphereState(simulation.atmosphere, simulation.time)
    uv_interp = Vector{Float64}(2)
    sw = Vector{Float64}(2)
    se = Vector{Float64}(2)
    ne = Vector{Float64}(2)
    nw = Vector{Float64}(2)

    for grain in simulation.grains

        if !grain.enabled
            continue
        end

        i, j = grain.atmosphere_grid_pos
        k = 1

        x_tilde, y_tilde = getNonDimensionalCellCoordinates(simulation.
                                                            atmosphere,
                                                            i, j,
                                                            grain.lin_pos)
        x_tilde = clamp(x_tilde, 0., 1.)
        y_tilde = clamp(y_tilde, 0., 1.)

        bilinearInterpolation!(uv_interp, u, v, x_tilde, y_tilde, i, j, k, 1)
        applyAtmosphereDragToGrain!(grain, uv_interp[1], uv_interp[2])
        applyAtmosphereVorticityToGrain!(grain,
                                      curl(simulation.atmosphere,
                                           x_tilde, y_tilde,
                                           i, j, k, 1, sw, se, ne, nw))
    end
    nothing
end

export applyAtmosphereDragToGrain!
"""
Add Stokes-type drag from velocity difference between atmosphere and a single 
grain.
"""
function applyAtmosphereDragToGrain!(grain::GrainCylindrical,
                                  u::Float64, v::Float64)
    rho_a = 1.2754   # atmosphere density
    length = grain.areal_radius*2.
    width = grain.areal_radius*2.

    drag_force = rho_a * 
    (.5*grain.ocean_drag_coeff_vert*width*.1*grain.thickness + 
     grain.atmosphere_drag_coeff_horiz*length*width) *
        ([u, v] - grain.lin_vel)*norm([u, v] - grain.lin_vel)

    grain.force += drag_force
    grain.atmosphere_stress = drag_force/grain.horizontal_surface_area
    nothing
end

export applyAtmosphereVorticityToGrain!
"""
Add Stokes-type torque from angular velocity difference between atmosphere and a 
single grain.  See Eq. 9.28 in "Introduction to Fluid Mechanics" by Nakayama 
and Boucher, 1999.
"""
function applyAtmosphereVorticityToGrain!(grain::GrainCylindrical, 
                                            atmosphere_curl::Float64)
    rho_a = 1.2754   # atmosphere density

    grain.torque +=
        pi * grain.areal_radius^4. * rho_a * 
        (grain.areal_radius / 5. * grain.atmosphere_drag_coeff_horiz + 
        .1 * grain.thickness * grain.atmosphere_drag_coeff_vert) * 
        abs(.5 * atmosphere_curl - grain.ang_vel) * 
        (.5 * atmosphere_curl - grain.ang_vel)
    nothing
end

export compareAtmospheres
"""
    compareAtmospheres(atmosphere1::atmosphere, atmosphere2::atmosphere)

Compare values of two `atmosphere` objects using the `Base.Test` framework.
"""
function compareAtmospheres(atmosphere1::Atmosphere, atmosphere2::Atmosphere)

    @test atmosphere1.input_file == atmosphere2.input_file
    @test atmosphere1.time ≈ atmosphere2.time

    @test atmosphere1.xq ≈ atmosphere2.xq
    @test atmosphere1.yq ≈ atmosphere2.yq

    @test atmosphere1.xh ≈ atmosphere2.xh
    @test atmosphere1.yh ≈ atmosphere2.yh

    @test atmosphere1.zl ≈ atmosphere2.zl

    @test atmosphere1.u ≈ atmosphere2.u
    @test atmosphere1.v ≈ atmosphere2.v

    if isassigned(atmosphere1.grain_list, 1)
        @test atmosphere1.grain_list == atmosphere2.grain_list
    end
    nothing
end
