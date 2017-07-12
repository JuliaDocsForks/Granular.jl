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

                      Array{Array{Int, 1}}(1, 1),

                      false)
end

export interpolateAtmosphereVelocitiesToCorners
"""
Convert gridded data from Arakawa-C type (decomposed velocities at faces) to 
Arakawa-B type (velocities at corners) through interpolation.
"""
function interpolateAtmosphereVelocitiesToCorners(u_in::Array{float, 4},
                                                  v_in::Array{float, 4})

    if size(u_in) != size(v_in)
        error("size of u_in ($(size(u_in))) must match v_in ($(size(v_in)))")
    end

    nx, ny, nz, nt = size(u_in)
    #u = Array{float}(nx+1, ny+1, nz, nt)
    #v = Array{float}(nx+1, ny+1, nz, nt)
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
function interpolateAtmosphereState(atmosphere::Atmosphere, t::float)
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
function createRegularAtmosphereGrid(n::Array{Int, 1},
                                     L::Array{float, 1};
                                     origo::Array{float, 1} = zeros(2),
                                     time::Array{float, 1} = zeros(1),
                                     name::String = "unnamed")

    xq = repmat(linspace(origo[1], L[1], n[1] + 1), 1, n[2] + 1)
    yq = repmat(linspace(origo[2], L[2], n[2] + 1)', n[1] + 1, 1)

    dx = L./n
    xh = repmat(linspace(origo[1] + .5*dx[1], L[1] - .5*dx[1], n[1]), 1, n[2])
    yh = repmat(linspace(origo[2] + .5*dx[2], L[2] - .5*dx[2], n[2])', n[1], 1)

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
                 false)
end

export addAtmosphereDrag!
"""
Add drag from linear and angular velocity difference between atmosphere and all 
ice floes.
"""
function addAtmosphereDrag!(simulation::Simulation)
    if typeof(simulation.atmosphere.input_file) == Bool
        error("no atmosphere data read")
    end

    u, v = interpolateAtmosphereState(simulation.atmosphere, simulation.time)

    for ice_floe in simulation.ice_floes

        if !ice_floe.enabled
            continue
        end

        i, j = ice_floe.atmosphere_grid_pos
        k = 1

        x_tilde, y_tilde = getNonDimensionalCellCoordinates(simulation.
                                                            atmosphere,
                                                            i, j,
                                                            ice_floe.lin_pos)
        if x_tilde < 0. || x_tilde > 1. || y_tilde < 0. || y_tilde > 1.
            warn("""
                 relative coordinates outside bounds ($(x_tilde), $(y_tilde)),
                 pos = $(ice_floe.lin_pos) at i,j = $(i), $(j).

                 """)
        end

        applyAtmosphereDragToIceFloe!(ice_floe,
                                      bilinearInterpolation(u,
                                                            x_tilde, y_tilde,
                                                            i, j, k, 1),
                                      bilinearInterpolation(v,
                                                            x_tilde, y_tilde,
                                                            i, j, k, 1))
        applyAtmosphereVorticityToIceFloe!(ice_floe,
                                           curl(simulation.atmosphere,
                                                x_tilde, y_tilde, i, j, k, 1))
    end
end

export applyAtmosphereDragToIceFloe!
"""
Add Stokes-type drag from velocity difference between atmosphere and a single 
ice floe.
"""
function applyAtmosphereDragToIceFloe!(ice_floe::IceFloeCylindrical,
                                  u::float, v::float)
    rho_a = 1.2754   # atmosphere density
    length = ice_floe.areal_radius*2.
    width = ice_floe.areal_radius*2.

    drag_force = rho_a * 
    (.5*ice_floe.ocean_drag_coeff_vert*width*.1*ice_floe.thickness + 
     ice_floe.atmosphere_drag_coeff_horiz*length*width) *
        ([u, v] - ice_floe.lin_vel)*norm([u, v] - ice_floe.lin_vel)

    ice_floe.force += drag_force
    ice_floe.atmosphere_stress = drag_force/ice_floe.horizontal_surface_area
end

export applyAtmosphereVorticityToIceFloe!
"""
Add Stokes-type torque from angular velocity difference between atmosphere and a 
single ice floe.  See Eq. 9.28 in "Introduction to Fluid Mechanics" by Nakayama 
and Boucher, 1999.
"""
function applyAtmosphereVorticityToIceFloe!(ice_floe::IceFloeCylindrical, 
                                            atmosphere_curl::float)
    rho_a = 1.2754   # atmosphere density

    ice_floe.torque +=
        pi*ice_floe.areal_radius^4.*rho_a*
        (ice_floe.areal_radius/5.*ice_floe.atmosphere_drag_coeff_horiz + 
        .1*ice_floe.thickness*ice_floe.atmosphere_drag_coeff_vert)*
        abs(.5*atmosphere_curl - ice_floe.ang_vel)*
        (.5*atmosphere_curl - ice_floe.ang_vel)
end

export compareAtmospheres
"""
    compareAtmospheres(atmosphere1::atmosphere, atmosphere2::atmosphere)

Compare values of two `atmosphere` objects using the `Base.Test` framework.
"""
function compareAtmospheres(atmosphere1::Atmosphere, atmosphere2::Atmosphere)

    Base.Test.@test atmosphere1.input_file == atmosphere2.input_file
    Base.Test.@test atmosphere1.time ≈ atmosphere2.time

    Base.Test.@test atmosphere1.xq ≈ atmosphere2.xq
    Base.Test.@test atmosphere1.yq ≈ atmosphere2.yq

    Base.Test.@test atmosphere1.xh ≈ atmosphere2.xh
    Base.Test.@test atmosphere1.yh ≈ atmosphere2.yh

    Base.Test.@test atmosphere1.zl ≈ atmosphere2.zl

    Base.Test.@test atmosphere1.u ≈ atmosphere2.u
    Base.Test.@test atmosphere1.v ≈ atmosphere2.v

    if isassigned(atmosphere1.ice_floe_list, 1)
        Base.Test.@test atmosphere1.ice_floe_list == atmosphere2.ice_floe_list
    end
end
